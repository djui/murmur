// The runtimes' own .wasm are served from this site, not a CDN, so the page talks to no host but
// Hugging Face (weights) and Desert Ant (license). Only the variants the models load are copied.
import { cpSync, mkdirSync, rmSync } from "node:fs";

const copy = (from, to, names) => {
  rmSync(to, { recursive: true, force: true });
  mkdirSync(to, { recursive: true });
  for (const name of names) cpSync(`${from}/${name}`, `${to}/${name}`);
};

// onnxruntime-web/webgpu (Voz) loads the asyncify build.
copy("node_modules/onnxruntime-web/dist", "public/ort", ["ort-wasm-simd-threaded.asyncify.mjs", "ort-wasm-simd-threaded.asyncify.wasm"]);
// LiteRT.js single-threaded: relaxed SIMD where the browser has it, the compat build otherwise.
copy("node_modules/@litertjs/core/wasm", "public/litert", [
  "litert_wasm_internal.js", "litert_wasm_internal.wasm", "litert_wasm_compat_internal.js", "litert_wasm_compat_internal.wasm",
]);
// Tongue's weights ship in its package (2 MB).
copy("node_modules/@desert-ant-labs/tongue/dist", "public/tongue", ["tongue_int8.bin", "tongue_meta.json"]);
