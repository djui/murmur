// The models: their workers, where their weights are cached, and what they take on disk.
//
// Weights come from Hugging Face. Voz keeps its bundle in its own Cache API cache; the service worker
// (public/sw.js) keeps everyone else's in "murmur-models". Both survive reloads and work offline.
import type { Envelope, LiteRtRequest, Reply, Results, Runtimes, VozRequest } from "./workers/protocol";
import LiteRtWorker from "./workers/litert.worker?worker";
import VozWorker from "./workers/voz.worker?worker";

export type ModelId = "voz" | "who" | "ear" | "redact" | "clear";

export const models: { id: ModelId; engine: string; title: string; detail: string; required: boolean }[] = [
  { id: "voz", engine: "Voz", title: "Transcription", detail: "25 languages, word timestamps", required: true },
  { id: "who", engine: "Who", title: "Speakers", detail: "Who spoke when, overlaps kept", required: true },
  { id: "ear", engine: "Ear", title: "Language", detail: "Detects the spoken language", required: true },
  { id: "redact", engine: "Redact", title: "Hide personal details", detail: "Finds names, numbers and addresses", required: false },
  { id: "clear", engine: "Clear", title: "Enhance audio", detail: "Denoise and level speech", required: false },
];

/** Voz's languages (ISO 639-1); anything else it would transcribe as confident nonsense. */
export const vozLanguages = new Set(["bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk"]);

export const MODEL_CACHE = "murmur-models";
const repoPath = (id: ModelId) => `/desert-ant-labs/${id}/`;

export function runtimes(): Runtimes {
  // ONNX Runtime finds its own .wasm (bundled); LiteRT.js would fetch its runtime from a CDN otherwise.
  return { ort: "", litert: new URL("litert/", document.baseURI).href };
}

type Progress = (phase: "download" | "run", fraction: number) => void;

/** A worker with request ids, so several calls can be in flight and each gets its own progress. */
class Client<Req> {
  private next = 1;
  private pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: Error) => void; progress?: Progress }>();

  constructor(readonly worker: Worker) {
    worker.onmessage = (event: MessageEvent<Reply>) => {
      const reply = event.data;
      const call = this.pending.get(reply.id);
      if (!call) return;
      if (reply.kind === "progress") call.progress?.(reply.phase, reply.fraction);
      else {
        this.pending.delete(reply.id);
        if (reply.kind === "done") call.resolve(reply.result);
        else call.reject(new Error(reply.message));
      }
    };
    worker.onerror = (event) => {
      for (const call of this.pending.values()) call.reject(new Error(event.message || "The model worker stopped."));
      this.pending.clear();
    };
  }

  call<K extends keyof Results>(request: Req, progress?: Progress, transfer: Transferable[] = []): Promise<Results[K]> {
    const id = this.next++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve: resolve as (v: unknown) => void, reject, progress });
      this.worker.postMessage({ id, ...request } as Envelope<Req>, transfer);
    });
  }

  terminate() {
    this.worker.terminate();
    for (const call of this.pending.values()) call.reject(new Error("Cancelled"));
    this.pending.clear();
  }
}

let voz: Client<VozRequest> | undefined;
let vozLoading: Promise<unknown> | undefined;

/** Starts compiling Voz in the background, so a transcription can start right away. */
export function preloadVoz(progress?: Progress): Promise<unknown> {
  voz ??= new Client<VozRequest>(new VozWorker());
  vozLoading ??= voz.call<"load">({ op: "load", runtimes: runtimes() }, progress).catch((error) => {
    releaseVoz();
    throw error;
  });
  return vozLoading;
}

export async function transcribe(file: Blob | Float32Array, progress?: Progress): Promise<Results["transcribe"]> {
  await preloadVoz(progress);
  const transfer = file instanceof Float32Array ? [file.buffer] : [];
  return voz!.call<"transcribe">({ op: "transcribe", runtimes: runtimes(), file }, progress, transfer);
}

/** Ends Voz's worker, which gives back its memory before Who runs. */
export function releaseVoz() {
  voz?.terminate();
  voz = undefined;
  vozLoading = undefined;
}

let litert: Client<LiteRtRequest> | undefined;

export function runLiteRt<K extends "ear" | "who" | "redact" | "clear">(request: LiteRtRequest & { op: K }, progress?: Progress): Promise<Results[K]> {
  litert ??= new Client<LiteRtRequest>(new LiteRtWorker());
  const transfer = "samples" in request ? [request.samples.buffer] : [];
  return litert.call<K>(request, progress, transfer);
}

export function releaseLiteRt() {
  litert?.terminate();
  litert = undefined;
}

/** Cancels whatever the models are doing. */
export function stopAll() {
  releaseVoz();
  releaseLiteRt();
}

/** Bytes on disk per model. */
export async function sizes(): Promise<Record<ModelId, number>> {
  const out = { voz: 0, who: 0, ear: 0, redact: 0, clear: 0 } as Record<ModelId, number>;
  if (!("caches" in globalThis)) return out;
  for (const name of await caches.keys()) {
    if (name !== MODEL_CACHE && !name.startsWith("desert-ant-voz")) continue;
    const cache = await caches.open(name);
    for (const request of await cache.keys()) {
      const id = models.find((m) => request.url.includes(repoPath(m.id)))?.id;
      if (!id) continue;
      // Cached bodies are disk-backed, so a blob's size is cheap and, unlike content-length, always there.
      out[id] += (await (await cache.match(request))?.blob())?.size ?? 0;
    }
  }
  return out;
}

export async function isDownloaded(id: ModelId): Promise<boolean> {
  return (await sizes())[id] > 0;
}

export async function remove(id: ModelId) {
  if (id === "voz") {
    releaseVoz();
    for (const name of await caches.keys()) if (name.startsWith("desert-ant-voz")) await caches.delete(name);
    return;
  }
  releaseLiteRt();
  const cache = await caches.open(MODEL_CACHE);
  for (const request of await cache.keys()) if (request.url.includes(repoPath(id))) await cache.delete(request);
}

/** Asks the browser not to clear the models when the disk fills up. */
export async function persist(): Promise<boolean> {
  try {
    return (await navigator.storage?.persisted?.()) || (await navigator.storage?.persist?.()) || false;
  } catch {
    return false;
  }
}

export async function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return;
  try {
    await navigator.serviceWorker.register(new URL("sw.js", document.baseURI), { scope: "./" });
  } catch (error) {
    console.warn("Model cache unavailable:", error);
  }
}

/** WebGPU with an adapter: what Voz needs to run at a usable speed. */
export async function hasWebGPU(): Promise<boolean> {
  try {
    return Boolean(await (navigator as { gpu?: { requestAdapter(): Promise<unknown> } }).gpu?.requestAdapter());
  } catch {
    return false;
  }
}
