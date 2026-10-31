// Copy and export: the text formats from core/formats, and WAV clips of marks or the selection.
import { clip, decode, joinClips, wav } from "../audio";
import { copyFormats, render, textFormats, type RenderOptions, type TextFormat, type TranscriptSection } from "../core/formats";
import { indices } from "../core/merge";
import { displayTitle, type Project } from "../core/project";
import { settings, update } from "../settings";
import { button, dialog, download, h, menu, toast } from "./dom";
import type { Range } from "./timeline";

const CLIP_RATE = 24_000;

function options(): Partial<RenderOptions> {
  const s = settings();
  return { speakerNames: s.speakerNames, hideFillers: s.hideFillers, redactionStyle: s.redactionStyle };
}

/** Snaps a range to whole words, as the Mac app's cuts do. */
export function snapToWords(project: Project, range: Range): Range {
  const [lo, hi] = indices(project.words, range.start, range.end);
  if (hi <= lo) return range;
  return { start: project.words[lo].start, end: project.words[hi - 1].end };
}

export function copyMenu(project: Project, selection: Range | null, at: HTMLElement) {
  const sections = selection ? [{ name: "Selection", ...snapToWords(project, selection) }] : undefined;
  menu([
    { label: selection ? "Copy the selection as" : "Copy the transcript as", heading: true },
    ...copyFormats.map((f) => ({
      label: textFormats.find((t) => t.id === f)!.title,
      checked: settings().copyFormat === f,
      action: async () => {
        update({ copyFormat: f });
        await navigator.clipboard.writeText(render(project, f, sections, options()));
        toast("Copied");
      },
    })),
  ], at);
}

let clipSamples: { file: File; samples: Promise<Float32Array> } | undefined;

/** Samples for clips, decoded once per file at 24 kHz. */
function samplesFor(file: File) {
  if (clipSamples?.file !== file) clipSamples = { file, samples: decode(file, CLIP_RATE) };
  return clipSamples.samples;
}

const safeName = (s: string) => s.replace(/[\\/:*?"<>|]+/g, "-").trim() || "Murmur";

export function showExport(project: Project, file: File | undefined, selection: Range | null) {
  type Scope = "all" | "selection" | "marks";
  type Kind = TextFormat | "clips";
  let scope: Scope = selection ? "selection" : "all";
  let kind: Kind = "markdown";
  let joined = false;
  let relative = false;
  const s = settings();

  const radio = <T extends string>(name: string, value: T, current: T, label: string, set: (v: T) => void, disabled = false) =>
    h("label", { class: "option" }, h("input", { type: "radio", name, value, checked: value === current, disabled, on: { change: () => set(value) } }), label);
  const check = (label: string, checked: boolean, set: (v: boolean) => void) =>
    h("label", { class: "option" }, h("input", { type: "checkbox", checked, on: { change: (e: Event) => set((e.target as HTMLInputElement).checked) } }), label);

  const clipOptions = h("div", { hidden: true }, radio("join", "separate", "separate", "One file per mark", () => (joined = false)), radio("join", "joined", "separate", "One joined file", () => (joined = true)));
  const sectionsFor = (): TranscriptSection[] | undefined =>
    scope === "all" ? undefined : scope === "selection" && selection ? [{ name: "Selection", ...snapToWords(project, selection) }] : project.marks.map((m) => ({ name: m.name, start: m.start, end: m.end }));

  return dialog("Export", (done) => ({
    body: [
      h("div", { class: "grid2" },
        h("span", {}, "What"),
        h("div", {},
          radio("scope", "all", scope, "The whole recording", (v) => (scope = v)),
          radio("scope", "selection", scope, "The selection", (v) => (scope = v), !selection),
          radio("scope", "marks", scope, `The marks (${project.marks.length})`, (v) => (scope = v), project.marks.length === 0)),
        h("span", {}, "Format"),
        h("select", { "aria-label": "Format", on: { change: (e: Event) => {
          kind = (e.target as HTMLSelectElement).value as Kind;
          clipOptions.hidden = kind !== "clips";
        } } },
          textFormats.map((f) => h("option", { value: f.id, selected: f.id === kind }, f.title)),
          h("option", { value: "clips", disabled: !file }, file ? "Audio clips (WAV)" : "Audio clips (needs the media file)")),
        h("span"), clipOptions,
        h("span", {}, "Options"),
        h("div", {},
          check("Speaker names", s.speakerNames, (v) => update({ speakerNames: v })),
          check("Times from the start of each section", relative, (v) => (relative = v)),
          project.settings.redact ? h("div", { class: "note" }, "Personal details stay hidden in the export; clips are bleeped.") : null),
      ),
    ],
    foot: [
      button("Cancel", () => done()),
      button("Export", async () => {
        const base = safeName(displayTitle(project));
        if (kind !== "clips") {
          const f = textFormats.find((t) => t.id === kind)!;
          const text = render(project, kind, sectionsFor(), { ...options(), relativeTimes: relative });
          download(new Blob([text], { type: kind === "json" ? "application/json" : "text/plain;charset=utf-8" }), `${base}.${f.ext}`);
          return done();
        }
        if (!file) return;
        toast("Preparing clips…");
        const samples = await samplesFor(file);
        const ranges = scope === "all" ? [{ name: base, start: 0, end: project.duration }] : sectionsFor()!.map((x) => ({ name: x.name ?? base, start: x.start, end: x.end }));
        const bleep = project.settings.redact ? project.redactions ?? [] : [];
        const clips = ranges.map((r) => ({ name: r.name, samples: clip(samples, CLIP_RATE, r.start, r.end, bleep) }));
        if (joined || clips.length === 1) download(wav(joinClips(clips.map((c) => c.samples), CLIP_RATE), CLIP_RATE), `${base}${clips.length === 1 && scope !== "all" ? ` - ${safeName(clips[0].name)}` : ""}.wav`);
        else clips.forEach((c, i) => setTimeout(() => download(wav(c.samples, CLIP_RATE), `${base} - ${String(i + 1).padStart(2, "0")} ${safeName(c.name)}.wav`), i * 400));
        done();
      }, { class: "primary" }),
    ],
  }));
}
