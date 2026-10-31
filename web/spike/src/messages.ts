// What the page and the model workers say to each other. Each worker runs one model once and is then
// terminated, so the browser gets its memory back before the next model loads.

export type Request = { file: File; ep: "auto" | "webgpu" | "wasm" } | { samples: Float32Array; accelerator: "wasm" | "auto" };

/** A fetch the worker made, from its own Resource Timing buffer (the page's does not see it). */
export interface Fetch {
  url: string;
  ms: number;
  /** Bytes over the network; 0 for a cache hit, and also when the host sends no Timing-Allow-Origin. */
  transferSize: number;
  bodySize: number;
}

export type Reply =
  | { kind: "progress"; phase: "download" | "run"; fraction: number }
  | { kind: "loaded"; ms: number }
  | { kind: "done"; ms: number; result: unknown; fetches: Fetch[] }
  | { kind: "failed"; message: string; fetches: Fetch[] };

export function fetches(): Fetch[] {
  return (performance.getEntriesByType("resource") as PerformanceResourceTiming[]).map((e) => ({
    url: e.name,
    ms: e.duration,
    transferSize: e.transferSize,
    bodySize: e.decodedBodySize,
  }));
}
