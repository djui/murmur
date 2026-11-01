// From a file to a project: decode → Ear (and Tongue) → Clear (optional) → Voz → Who → merge → Redact.
// As the Mac app's Pipeline.swift, but sequential, so only one large model is in memory at a time,
// and the transcript appears as soon as Voz is done while Who is still finding the speakers.
import { decode, RATE } from "./audio";
import { assign } from "./core/merge";
import * as Peaks from "./core/peaks";
import * as Repair from "./core/repair";
import * as Timecode from "./core/timecode";
import type { Project, Word } from "./core/project";
import { isDownloaded, releaseLiteRt, releaseVoz, runLiteRt, runtimes, transcribe, vozLanguages } from "./models";

export type StepId = "decode" | "language" | "enhance" | "transcribe" | "speakers" | "redact";
export type StepState = "waiting" | "running" | "done" | "skipped" | "failed";

export interface Step {
  id: StepId;
  title: string;
  detail: string;
  state: StepState;
  fraction?: number;
}

export interface PipelineHooks {
  step(id: StepId, change: Partial<Step>): void;
  peaks(peaks: Float32Array, duration: number): void;
  /** The project as it fills in: words first, then speakers, then redactions. */
  progress(project: Project): void;
  /** Ear heard a language Voz doesn't have. True transcribes anyway. */
  unsupportedLanguage(language: string, confidence: number): Promise<boolean>;
}

export function steps(enhance: boolean): Step[] {
  return [
    { id: "decode", title: "Reading the audio", detail: "", state: "waiting" },
    { id: "language", title: "Detecting the language", detail: "Ear", state: "waiting" },
    ...(enhance ? [{ id: "enhance" as const, title: "Enhancing the audio", detail: "Clear", state: "waiting" as const }] : []),
    { id: "transcribe", title: "Transcribing", detail: "Voz", state: "waiting" },
    { id: "speakers", title: "Finding the speakers", detail: "Who", state: "waiting" },
    { id: "redact", title: "Finding personal details", detail: "Redact", state: "waiting" },
  ];
}

export const languageName = (code: string) => {
  try {
    return new Intl.DisplayNames(["en"], { type: "language" }).of(code) ?? code;
  } catch {
    return code;
  }
};

let tongue: Promise<{ detect(text: string): { language: string | null; isTooCloseToCall: boolean } }> | undefined;
const loadTongue = () => (tongue ??= import("@desert-ant-labs/tongue").then((m) => m.Tongue.load({ from: new URL("tongue", document.baseURI).href })));

export class Cancelled extends Error {}

export async function run(project: Project, file: File, hooks: PipelineHooks, signal: AbortSignal): Promise<Project> {
  const p = structuredClone(project);
  const check = () => {
    if (signal.aborted) throw new Cancelled("Cancelled");
  };
  const timed = async <T>(id: StepId, body: () => Promise<T>): Promise<T> => {
    const start = performance.now();
    hooks.step(id, { state: "running", fraction: undefined });
    const out = await body();
    check();
    hooks.step(id, { state: "done", fraction: 1, detail: `${(await stepDetail(id)) ?? ""}${((performance.now() - start) / 1000).toFixed(1)} s` });
    return out;
  };
  let detail: Partial<Record<StepId, string>> = {};
  const stepDetail = async (id: StepId) => detail[id];
  const fraction = (id: StepId) => (_: "download" | "run", f: number) => hooks.step(id, { fraction: f });

  p.status = "processing";
  hooks.progress(p);

  // 1. Decode once for the waveform and the language. The samples are let go before Voz runs and
  //    decoded again for Who, so the long recording is never held twice.
  let peaks: Float32Array = new Float32Array(0);
  let samples: Float32Array | undefined = await timed("decode", async () => {
    const s = await decode(file);
    p.duration = s.length / RATE;
    peaks = Peaks.normalize(Peaks.compute(s, RATE));
    hooks.peaks(peaks, p.duration);
    detail = { ...detail, decode: `${Timecode.short(p.duration)} · ` };
    return s;
  });

  // 2. Language: Ear on up to five minutes; Tongue checks the text later when Ear is unsure.
  let language = "en";
  let unsure = false;
  await timed("language", async () => {
    const sample = samples!.slice(0, RATE * 300);
    const d = await runLiteRt({ op: "ear", runtimes: runtimes(), samples: sample }, fraction("language"));
    language = d.language ?? "en";
    p.languageConfidence = d.confidence;
    unsure = !d.isReliable || d.confidence < 0.8;
    if (!vozLanguages.has(language) && !unsure) {
      if (!(await hooks.unsupportedLanguage(language, d.confidence))) throw new Cancelled("Cancelled");
    }
    detail = { ...detail, language: `${languageName(language)}, ${Math.round(d.confidence * 100)}% · ` };
  });

  // 3. Clear, when asked: enhanced audio goes to Voz instead of the file.
  let input: Blob | Float32Array = file;
  if (p.settings.enhance) {
    input = await timed("enhance", () => runLiteRt({ op: "clear", runtimes: runtimes(), samples: samples!.slice() }, fraction("enhance")));
  }
  samples = undefined;
  releaseLiteRt();

  // 4. Voz, then the gaps it left that still hold speech, read again with context (GapRepair); then
  //    let Voz go. The samples decoded here are Who's next.
  let whoSamples: Float32Array | undefined;
  await timed("transcribe", async () => {
    const t = await transcribe(input, (phase, f) => fraction("transcribe")(phase, f * 0.9));
    const heard = (words: { text: string; start: number; end: number }[], offset = 0) =>
      words.map((w): Word => ({ text: w.text, start: w.start + offset, end: Math.max(w.start, w.end) + offset, speaker: 0, isFiller: false, edited: false }));
    p.words = heard(t.words);
    hooks.progress(structuredClone(p));
    whoSamples = await decode(file);
    const found = Repair.gaps(p.words, p.duration, peaks).reverse();
    const before = p.words.length;
    for (const [k, gap] of found.entries()) {
      check();
      const window = whoSamples.slice(Math.floor(gap.windowStart * RATE), Math.min(whoSamples.length, Math.floor(gap.windowEnd * RATE)));
      if (window.length < RATE / 2) continue;
      const again = await transcribe(window);
      p.words = Repair.splice(p.words, gap, heard(again.words, gap.windowStart)) ?? p.words;
      hooks.step("transcribe", { fraction: 0.9 + (0.1 * (k + 1)) / found.length });
    }
    const recovered = p.words.length - before;
    detail = { ...detail, transcribe: `${p.words.length} words${recovered ? `, ${recovered} recovered` : ""} · ` };
  });
  releaseVoz();
  p.speakers = [{ id: 0, name: "", isMe: false }];
  p.transcriber = "voz";

  // Tongue reads the text: it settles the language when Ear was unsure, and flags a mismatch.
  const text = p.words.slice(0, 400).map((w) => w.text).join(" ");
  if (text.length > 30) {
    try {
      const found = (await loadTongue()).detect(text);
      if (found.language && !found.isTooCloseToCall) {
        if (unsure && vozLanguages.has(found.language)) language = found.language;
        else if (found.language !== language) p.languageWarning = found.language;
      }
    } catch (error) {
      console.warn("Tongue unavailable:", error);
    }
  }
  p.language = language;
  hooks.progress(structuredClone(p));

  // 5. Who, now that Voz's memory is back.
  await timed("speakers", async () => {
    const turns = await runLiteRt({ op: "who", runtimes: runtimes(), samples: whoSamples ?? (await decode(file)) }, fraction("speakers"));
    whoSamples = undefined;
    p.words = assign(p.words, turns);
    const ids = [...new Set(p.words.map((w) => w.speaker))].sort((a, b) => a - b);
    p.speakers = (ids.length ? ids : [0]).map((id) => ({ id, name: "", isMe: false }));
    detail = { ...detail, speakers: `${p.speakers.length} speakers · ` };
  });
  hooks.progress(structuredClone(p));

  // 6. Redact, when its model is on this computer (turning redaction on downloads it).
  if (await isDownloaded("redact")) {
    p.redactions = await timed("redact", () => runLiteRt({ op: "redact", runtimes: runtimes(), words: p.words }, fraction("redact")));
  } else {
    hooks.step("redact", { state: "skipped", detail: "Off until you turn redaction on" });
  }
  releaseLiteRt();

  p.status = "ready";
  p.processedAt = new Date().toISOString();
  return p;
}

/** Redaction for a project processed before Redact was downloaded. */
export async function findRedactions(project: Project, progress?: (f: number) => void) {
  try {
    return await runLiteRt({ op: "redact", runtimes: runtimes(), words: project.words }, (_, f) => progress?.(f));
  } finally {
    releaseLiteRt();
  }
}
