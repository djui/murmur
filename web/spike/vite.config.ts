import { appendFileSync } from "node:fs";
import { defineConfig } from "vite";

export default defineConfig({
  // The SDK packages find their wasm cores next to their own modules; pre-bundling would move them.
  optimizeDeps: { exclude: ["@desert-ant-labs/voz", "@desert-ant-labs/who", "@desert-ant-labs/core", "onnxruntime-web", "@litertjs/core"] },
  worker: { format: "es" },
  // SPIKE_COI=1 isolates the page (COOP/COEP), which LiteRT's threaded build needs for SharedArrayBuffer.
  server: {
    port: Number(process.env.SPIKE_PORT ?? 5199),
    strictPort: true,
    headers: process.env.SPIKE_COI
      ? { "Cross-Origin-Opener-Policy": "same-origin", "Cross-Origin-Embedder-Policy": "require-corp" }
      : {},
  },
  plugins: [
    {
      // Each finished run posts its Markdown here and it lands in results.md, so a browser that cannot
      // be clicked (Safari under automation) still reports. Dev server only, this machine only.
      name: "spike-results",
      configureServer(server) {
        server.middlewares.use("/__results", (req, res) => {
          let body = "";
          req.on("data", (chunk) => (body += chunk));
          req.on("end", () => {
            appendFileSync("results.md", `${body}\n\n`);
            res.end("ok");
          });
        });
      },
    },
  ],
});
