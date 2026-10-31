import { fetches, type Reply, type Request } from "./messages";

// LiteRT.js loads its runtime with `importScripts`, which a module worker has but refuses to run, and
// the Who package needs a module worker (top-level await). Stand in with a synchronous fetch and a
// global eval. The cost: the page's Content-Security-Policy must allow 'unsafe-eval'. The Emscripten
// loader takes a worker's own address as its location and would look for its .wasm next to this file,
// so it is told the script's real address.
(globalThis as any).importScripts = (...urls: string[]) => {
  for (const url of urls) {
    const request = new XMLHttpRequest();
    request.open("GET", url, false);
    request.send();
    if (request.status !== 200) throw new Error(`could not load ${url}: ${request.status}`);
    (0, eval)(request.responseText.replaceAll("_scriptName = self.location.href", `_scriptName = ${JSON.stringify(url)}`));
  }
};

const post = (reply: Reply) => postMessage(reply);

onmessage = async (event: MessageEvent<Request>) => {
  if (!("samples" in event.data)) return;
  try {
    // Imported after the stand-in exists.
    const { Who } = await import("@desert-ant-labs/who");
    const loadStart = performance.now();
    const who = await Who.load({
      litertWasmDir: new URL("/litert/", location.origin).href,
      accelerator: event.data.accelerator,
      onProgress: (fraction) => post({ kind: "progress", phase: "download", fraction }),
    });
    post({ kind: "loaded", ms: performance.now() - loadStart });

    // Samples, not the file: Who decodes a file with Web Audio, which a worker does not have.
    const runStart = performance.now();
    const result = await who.diarize({ samples: event.data.samples, sampleRate: 16_000 });
    const ms = performance.now() - runStart;
    await who.flushTelemetry().catch(() => false);
    post({
      kind: "done",
      ms,
      result: { speakerCount: result.speakerCount, duration: result.duration, turns: result.turns.map((t) => t.toJSON()) },
      fetches: fetches(),
    });
    who.dispose();
  } catch (error) {
    post({ kind: "failed", message: String(error instanceof Error ? error.stack ?? error.message : error), fetches: fetches() });
  }
};
