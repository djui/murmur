import { Voz } from "@desert-ant-labs/voz";
import { fetches, type Reply, type Request } from "./messages";

const post = (reply: Reply) => postMessage(reply);

onmessage = async (event: MessageEvent<Request>) => {
  if (!("file" in event.data)) return;
  try {
    const loadStart = performance.now();
    const voz = await Voz.load({
      wasmDir: new URL("/ort/", location.origin).href,
      ep: event.data.ep,
      onProgress: (fraction) => post({ kind: "progress", phase: "download", fraction }),
    });
    post({ kind: "loaded", ms: performance.now() - loadStart });

    // The file itself, not samples: Voz streams it through WebCodecs, so memory stays flat with length.
    const runStart = performance.now();
    const result = await voz.transcribe(event.data.file, {
      onProgress: (fraction) => post({ kind: "progress", phase: "run", fraction }),
    });
    post({
      kind: "done",
      ms: performance.now() - runStart,
      result: {
        words: result.words,
        duration: result.duration,
        realtimeFactor: result.realtimeFactor,
        timings: voz.timings,
      },
      fetches: fetches(),
    });
  } catch (error) {
    post({ kind: "failed", message: String(error instanceof Error ? error.stack ?? error.message : error), fetches: fetches() });
  }
};
