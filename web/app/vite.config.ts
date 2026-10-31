import { defineConfig } from "vite";

export default defineConfig({
  // Relative URLs, so the build works at /murmur/app/ on GitHub Pages and anywhere else.
  base: "./",
  // The SDK packages find their wasm cores next to their own modules; pre-bundling would move them.
  optimizeDeps: { exclude: ["@desert-ant-labs/voz", "@desert-ant-labs/who", "@desert-ant-labs/ear", "@desert-ant-labs/redact", "@desert-ant-labs/clear", "@desert-ant-labs/core", "@desert-ant-labs/tongue", "onnxruntime-web", "@litertjs/core"] },
  worker: { format: "es" },
  build: { target: "es2022", chunkSizeWarningLimit: 4000 },
  server: { port: 5200, strictPort: true },
  preview: { port: 5201, strictPort: true },
});
