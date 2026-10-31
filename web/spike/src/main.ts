import type { Fetch, Reply, Request } from "./messages";

type Word = { text: string; start: number; end: number };
type Turn = { speaker: number; start: number; end: number };
type Step = { name: string; seconds?: number; detail: string };

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;

// Every host the page may talk to. Anything else in the network table is a finding.
const allowed = (host: string) =>
  host === location.host || host === "huggingface.co" || host.endsWith(".huggingface.co") || host.endsWith(".hf.co") ||
  host === "events.desertant.com";

const steps: Step[] = [];
const allFetches: Fetch[] = [];
let lines: string[] = [];

async function describeEnvironment() {
  const gpu = (navigator as any).gpu;
  const adapter = gpu ? await gpu.requestAdapter().catch(() => null) : null;
  const info = adapter?.info ?? {};
  const parts = [
    navigator.userAgent.match(/(Chrome|Safari|Firefox)\/[\d.]+/g)?.join(" ") ?? navigator.userAgent,
    adapter ? `WebGPU: ${[info.vendor, info.architecture].filter(Boolean).join(" ") || "yes"}` : "WebGPU: no",
    `WebNN: ${"ml" in navigator ? "yes" : "no"}`,
    `cores: ${navigator.hardwareConcurrency}`,
  ];
  lines = parts;
  $("env").textContent = parts.join(" · ");
}

function render() {
  $("steps").innerHTML = steps
    .map((s) => `<tr><td>${s.name}</td><td class="num">${s.seconds == null ? "…" : s.seconds.toFixed(2)}</td><td>${s.detail}</td></tr>`)
    .join("");

  const hosts = new Map<string, { n: number; transfer: number; body: number }>();
  for (const f of allFetches) {
    const host = new URL(f.url, location.href).host;
    const h = hosts.get(host) ?? { n: 0, transfer: 0, body: 0 };
    h.n += 1;
    h.transfer += f.transferSize;
    h.body += f.bodySize;
    hosts.set(host, h);
  }
  $("network").innerHTML = [...hosts]
    .map(([host, h]) => `<tr><td class="${allowed(host) ? "" : "bad"}">${host}${allowed(host) ? "" : " (not allowed)"}</td>` +
      `<td class="num">${h.n}</td><td class="num">${(h.transfer / 1e6).toFixed(1)}</td><td class="num">${(h.body / 1e6).toFixed(1)}</td></tr>`)
    .join("");
}

function step(name: string, detail = ""): Step {
  const s = { name, detail };
  steps.push(s);
  render();
  return s;
}

/** Run one model in its own worker, then terminate the worker so its memory is released. */
function runWorker<T>(worker: Worker, request: Request, transfer: Transferable[], name: string): Promise<T> {
  const load = step(`${name} load`);
  const run = step(`${name} run`);
  const pct = (f: number) => `${Math.round(f * 100)}%`;
  return new Promise((resolve, reject) => {
    worker.onmessage = (event: MessageEvent<Reply>) => {
      const reply = event.data;
      if (reply.kind === "progress") {
        (reply.phase === "download" ? load : run).detail = `${reply.phase === "download" ? "downloading" : "running"} ${pct(reply.fraction)}`;
      } else if (reply.kind === "loaded") {
        load.seconds = reply.ms / 1000;
        load.detail = "";
      } else {
        allFetches.push(...reply.fetches);
        worker.terminate();
        if (reply.kind === "failed") {
          run.detail = `<span class="bad">${reply.message.split("\n")[0]}</span>`;
          render();
          console.error(reply.message);
          reject(new Error(reply.message));
          return;
        }
        run.seconds = reply.ms / 1000;
        run.detail = "";
        resolve(reply.result as T);
      }
      render();
    };
    worker.onerror = (event) => {
      run.detail = `<span class="bad">${event.message}</span>`;
      render();
      reject(new Error(event.message));
    };
    worker.postMessage(request, transfer);
  });
}

/** Mono 16 kHz samples for Who. Voz reads the file itself. */
async function decode(file: File): Promise<Float32Array> {
  const buffer = await new OfflineAudioContext(1, 1, 16_000).decodeAudioData(await file.arrayBuffer());
  const mono = new Float32Array(buffer.length);
  for (let c = 0; c < buffer.numberOfChannels; c++) {
    const channel = buffer.getChannelData(c);
    for (let i = 0; i < mono.length; i++) mono[i] += channel[i] / buffer.numberOfChannels;
  }
  return mono;
}

async function storage(): Promise<string> {
  const estimate = await navigator.storage?.estimate?.();
  const persisted = await navigator.storage?.persisted?.();
  const out = [`usage ${((estimate?.usage ?? 0) / 1e6).toFixed(0)} MB of ${((estimate?.quota ?? 0) / 1e9).toFixed(0)} GB quota, persisted: ${persisted}`];
  for (const name of await caches.keys()) {
    const cache = await caches.open(name);
    const keys = await cache.keys();
    out.push(`cache "${name}": ${keys.length} entries`);
    for (const k of keys.slice(0, 8)) out.push(`  ${k.url}`);
  }
  return out.join("\n");
}

/** Each word goes to the speaker whose turn overlaps it most; the app's Merge.swift does more. */
function speakerParagraphs(words: Word[], turns: Turn[]): { speaker: number; text: string; start: number }[] {
  const paragraphs: { speaker: number; text: string; start: number }[] = [];
  for (const w of words) {
    let best = -1;
    let bestOverlap = 0;
    for (const t of turns) {
      const overlap = Math.min(w.end, t.end) - Math.max(w.start, t.start);
      if (overlap > bestOverlap) [best, bestOverlap] = [t.speaker, overlap];
    }
    const last = paragraphs.at(-1);
    if (last && (best === -1 || last.speaker === best)) last.text += " " + w.text;
    else paragraphs.push({ speaker: best, text: w.text, start: w.start });
  }
  return paragraphs;
}

const clock = (s: number) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

async function process(file: File) {
  steps.length = 0;
  allFetches.length = 0;
  $("transcript").innerHTML = "";
  $("report").textContent = "";
  ($("copy") as HTMLButtonElement).disabled = true;
  $("storage").textContent = await storage();

  const total = performance.now();
  const decoding = step("Decode for Who", `${file.name}, ${(file.size / 1e6).toFixed(1)} MB`);
  const t0 = performance.now();
  const samples = await decode(file);
  decoding.seconds = (performance.now() - t0) / 1000;
  decoding.detail += `, ${(samples.length / 16_000 / 60).toFixed(1)} min, ${(samples.byteLength / 1e6).toFixed(0)} MB of samples`;
  render();

  try {
    const ep = ($("ep") as HTMLSelectElement).value as "auto" | "webgpu" | "wasm";
    const voz = await runWorker<{ words: Word[]; duration: number; realtimeFactor: number }>(
      new Worker(new URL("./voz.worker.ts", import.meta.url), { type: "module" }), { file, ep }, [], "Voz");
    steps.at(-1)!.detail = `${voz.words.length} words, ${voz.realtimeFactor.toFixed(1)}× real time`;

    const accelerator = ($("accelerator") as HTMLSelectElement).value as "wasm" | "auto";
    const who = await runWorker<{ speakerCount: number; turns: Turn[] }>(
      new Worker(new URL("./who.worker.ts", import.meta.url), { type: "module" }), { samples, accelerator }, [samples.buffer], "Who");
    steps.at(-1)!.detail = `${who.speakerCount} speakers, ${who.turns.length} turns`;
    step("Total").seconds = (performance.now() - total) / 1000;

    $("transcript").innerHTML = speakerParagraphs(voz.words, who.turns)
      .map((p) => `<p><b>${p.speaker < 0 ? "?" : `Speaker ${p.speaker + 1}`}</b> <span class="num">${clock(p.start)}</span> ${p.text}</p>`)
      .join("");
  } finally {
    render();
    $("storage").textContent = await storage();
    report(file);
  }
}

function report(file: File) {
  const table = steps.map((s) => `| ${s.name} | ${s.seconds?.toFixed(2) ?? "–"} | ${s.detail.replace(/<[^>]+>/g, "")} |`);
  const network = [...$("network").querySelectorAll("tr")].map((tr) => `| ${[...tr.children].map((c) => c.textContent).join(" | ")} |`);
  $("report").textContent = [
    `**${file.name}** · ${lines.join(" · ")}`,
    "",
    "| Step | Seconds | Detail |", "|---|---|---|", ...table,
    "",
    "| Host | Requests | MB over network | MB body |", "|---|---|---|---|", ...network,
    "",
    "```", $("storage").textContent ?? "", "```",
  ].join("\n");
  ($("copy") as HTMLButtonElement).disabled = false;
}

$("file").addEventListener("change", (e) => {
  const file = (e.target as HTMLInputElement).files?.[0];
  if (file) process(file).catch(console.error);
});
/** A file this page serves, e.g. `?src=/long.m4a` for the 60-minute loop of the sample. */
async function processServed(path: string) {
  const blob = await fetch(path).then((r) => r.blob());
  await process(new File([blob], path.split("/").pop()!, { type: blob.type || "audio/mp4" }));
}
$("sample").addEventListener("click", () => processServed("/sample.m4a").catch(console.error));
// `?src=/ten.m4a&ep=wasm&who=auto` runs without clicks, for scripted comparisons.
const params = new URLSearchParams(location.search);
for (const [param, id] of [["ep", "ep"], ["who", "accelerator"]]) {
  const value = params.get(param);
  if (value) ($(id) as HTMLSelectElement).value = value;
}
const src = params.get("src");
if (src?.startsWith("/")) processServed(src).catch(console.error);
$("copy").addEventListener("click", () => navigator.clipboard.writeText($("report").textContent ?? ""));

describeEnvironment();
