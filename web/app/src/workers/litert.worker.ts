// Ear, Who, Redact and Clear share one worker: they all run on LiteRT.js, which loads once per worker.
import { paragraphs } from "../core/merge";
import type { RedactedSpan, Word } from "../core/project";
import { spanOver, textOf } from "../core/redactor";
import type { Envelope, LiteRtRequest, Reply } from "./protocol";

// LiteRT.js loads its runtime with `importScripts`, which a module worker has but refuses to run, and
// the model packages need a module worker (top-level await). Stand in with a synchronous fetch and a
// global eval, and tell the Emscripten loader its real address so it finds its .wasm. Reported to
// Desert Ant (web/spike/desert-ant-report.md).
(globalThis as { importScripts?: (...urls: string[]) => void }).importScripts = (...urls: string[]) => {
  for (const url of urls) {
    const request = new XMLHttpRequest();
    request.open("GET", url, false);
    request.send();
    if (request.status !== 200) throw new Error(`could not load ${url}: ${request.status}`);
    (0, eval)(request.responseText.replaceAll("_scriptName = self.location.href", `_scriptName = ${JSON.stringify(url)}`));
  }
};

const post = (reply: Reply) => postMessage(reply);
const loaded = new Map<string, Promise<any>>();

function model(name: "ear" | "who" | "redact" | "clear", id: number, litertWasmDir: string): Promise<any> {
  if (!loaded.has(name)) {
    const onProgress = (fraction: number) => post({ id, kind: "progress", phase: "download", fraction });
    const options = { litertWasmDir, onProgress, accelerator: name === "who" ? "auto" : undefined } as const;
    const load = {
      ear: () => import("@desert-ant-labs/ear").then((m) => m.Ear.load(options)),
      who: () => import("@desert-ant-labs/who").then((m) => m.Who.load(options)),
      redact: () => import("@desert-ant-labs/redact").then((m) => m.Redact.load(options)),
      clear: () => import("@desert-ant-labs/clear").then((m) => m.Clear.load(options)),
    }[name];
    loaded.set(name, load().catch((error) => {
      loaded.delete(name);
      throw error;
    }));
  }
  return loaded.get(name)!;
}

const categories: Record<string, string> = {
  GIVEN_NAME: "name", SURNAME: "name",
  STREET_NAME: "address", BUILDING_NUMBER: "address", SECONDARY_ADDRESS: "address", CITY: "address", STATE: "address", ZIP_CODE: "address",
  EMAIL: "email", PHONE: "phone",
  CREDIT_CARD: "account", BANK_ACCOUNT: "account", ROUTING_NUMBER: "account",
  IP_ADDRESS: "link", URL: "link",
  GOVERNMENT_ID: "ID", PASSPORT: "ID", DRIVERS_LICENSE: "ID", TAX_ID: "ID", SSN: "ID",
  IMEI: "device", ORG: "organisation",
};

/** Personal details in the transcript as time spans over the words, as the Mac app's RedactionFinder. */
async function findRedactions(redact: any, words: Word[]): Promise<RedactedSpan[]> {
  const spans: RedactedSpan[] = [];
  for (const p of paragraphs(words)) {
    const run = words.slice(p.lower, p.upper).filter((w) => !w.isFiller);
    const { text, ranges } = textOf(run);
    if (!text) continue;
    const result = await redact.redaction(text);
    // The model reports UTF-16 offsets; `textOf` counts code points. They agree for most text, and
    // where they don't, the span lands on the neighbouring word at worst.
    for (const item of result.items) {
      const span = spanOver(run, ranges, item.start, item.end, categories[item.label] ?? item.label.toLowerCase(), item.original);
      if (!span) continue;
      // A given name followed by a surname is one name.
      const last = spans.at(-1);
      if (last && last.category === span.category && span.start - last.end < 0.6) {
        last.end = span.end;
        last.original += " " + span.original;
      } else {
        spans.push(span);
      }
    }
  }
  return spans;
}

onmessage = async (event: MessageEvent<Envelope<LiteRtRequest>>) => {
  const request = event.data;
  const { id } = request;
  try {
    const m = await model(request.op, id, request.runtimes.litert);
    post({ id, kind: "progress", phase: "run", fraction: 0 });
    let result: unknown;
    switch (request.op) {
      case "ear": {
        const d = await m.identify(request.samples, 16_000);
        result = { language: d.language, confidence: d.confidence, isReliable: d.isReliable };
        break;
      }
      case "who": {
        const d = await m.diarize({ samples: request.samples, sampleRate: 16_000 });
        result = d.turns.map((t: { speaker: number; start: number; end: number }) => ({ speaker: t.speaker, start: t.start, end: t.end }));
        break;
      }
      case "redact":
        result = await findRedactions(m, request.words);
        break;
      case "clear": {
        const r = await m.enhance(request.samples, 16_000, { outputSampleRate: 16_000, channelMode: "mono" });
        result = r.samples;
        break;
      }
    }
    post({ id, kind: "done", result });
  } catch (error) {
    post({ id, kind: "failed", message: error instanceof Error ? error.message : String(error) });
  }
};
