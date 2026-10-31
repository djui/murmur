// Serve the runtimes' own .wasm from this page instead of a CDN, so the page talks to no host but
// Hugging Face (weights) and Desert Ant (license).
import { cpSync, mkdirSync, readdirSync } from "node:fs";

const copy = (from, to, keep) => {
  mkdirSync(to, { recursive: true });
  for (const name of readdirSync(from).filter(keep)) cpSync(`${from}/${name}`, `${to}/${name}`);
};

copy("node_modules/onnxruntime-web/dist", "public/ort", (n) => /^ort-wasm.*\.(mjs|wasm)$/.test(n));
copy("node_modules/@litertjs/core/wasm", "public/litert", () => true);

// Forty seconds with synthetic voices, the same file the landing page's demo plays.
cpSync("../../site/assets/sample.m4a", "public/sample.m4a");
