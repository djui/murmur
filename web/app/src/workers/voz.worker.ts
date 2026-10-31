// Voz in its own worker. The page loads it as soon as the models are on disk (compiling takes ~20 s
// in Chromium) and terminates the worker once a transcript is done, which returns its ~1.2 GB.
import type { Voz as VozType } from "@desert-ant-labs/voz";
import type { Envelope, Reply, VozRequest } from "./protocol";

const post = (reply: Reply) => postMessage(reply);
let voz: Promise<VozType> | undefined;

function load(id: number, ort: string): Promise<VozType> {
  voz ??= import("@desert-ant-labs/voz").then(({ Voz }) =>
    Voz.load({ wasmDir: ort || undefined, onProgress: (fraction) => post({ id, kind: "progress", phase: "download", fraction }) }),
  );
  return voz;
}

onmessage = async (event: MessageEvent<Envelope<VozRequest>>) => {
  const { id } = event.data;
  try {
    const model = await load(id, event.data.runtimes.ort);
    if (event.data.op === "load") return post({ id, kind: "done", result: true });
    // A File streams through WebCodecs, so memory stays flat with the length of the recording.
    const result = await model.transcribe(event.data.file, {
      onProgress: (fraction) => post({ id, kind: "progress", phase: "run", fraction }),
    });
    post({ id, kind: "done", result: { words: result.words, duration: result.duration } });
  } catch (error) {
    voz = undefined;
    post({ id, kind: "failed", message: error instanceof Error ? error.message : String(error) });
  }
};
