import { defineConfig } from "vite";

export default defineConfig({
  // The SDK packages find their wasm cores next to their own modules; pre-bundling would move them.
  optimizeDeps: { exclude: ["@desert-ant-labs/voz", "@desert-ant-labs/who", "@desert-ant-labs/core", "onnxruntime-web", "@litertjs/core"] },
  worker: { format: "es" },
  server: { port: 5199, strictPort: true },
});
