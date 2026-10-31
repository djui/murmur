# Web spike

Phase 1 of [docs/web-plan.md](../../docs/web-plan.md): can a browser run Voz and Who on a long recording,
with nothing uploaded? One page: pick a file, Voz runs in one worker, then Who in another, then the words
go to speakers. Throwaway code; nothing here ships.

```bash
cd web/spike
npm install        # also copies the runtimes' .wasm and the test audio into public/
npm run dev        # http://localhost:5199
```

`?src=/long.m4a` (60 min) or `?src=/ten.m4a` (10 min) runs a served file without clicks; `&ep=wasm`
and `&who=auto` choose where Voz and Who run. Make those files with
`ffmpeg -stream_loop 89 -i public/sample.m4a -c copy public/long.m4a` (14 loops for ten minutes).
"Copy as Markdown" puts a run's numbers on the clipboard, and the dev server also appends each run's
report to `results.md` (for browsers driven from a script, e.g. `open -a Safari "http://localhost:5199/?src=/ten.m4a"`).

## Results

M2 MacBook (8 cores, 16 GB), SDK 4.2.3, WebGPU on Metal, no WebNN in either browser. The test audio is
the site's 40 s sample (three synthetic voices) looped. Times in seconds; Voz and Who as × real time.

| Audio | Browser | Voz load | Voz run | Who run | Total | Tab peak |
|---|---|---|---|---|---|---|
| 40 s | Chromium 152 | 21.8 | 3.6 | 1.1 | 32 | |
| 40 s | Safari 27, first visit | 29.3 (download) | 8.6 | 1.7 | 49 | |
| 10 min | Chromium 152 | 22.0 | 23.1 (26×) | 110 (5.5×) | 161 | |
| 10 min | Safari 27 | 6.6 | 36.3 (17×) | 100 (6×) | 151 | 3.7 GB |
| 60 min | Chromium 152 | 25.9 | 139 (26×) | 570 (6.3×) | 748 | 3.3 GB |
| 60 min | Safari 27 | 5.5 | 203 (18×) | 622 (5.8×) | 840 | 5.2 GB |

Who load is 4–5 s everywhere. Safari keeps Voz's compiled graphs between visits (5–7 s load, against
Chromium's 22 s every time) but runs it slower. Safari's storage quota was 82 GB, the browser pane's 3–4
GB. Every run in both browsers found the same three speakers and the same turns.

### Chromium detail

Chromium 152 is the Claude app's browser pane; the last two rows compare Who on the CPU and with
`accelerator: "auto"` (WebGPU).

| Audio | Voz load | Voz run | Who load | Who run | Total |
|---|---|---|---|---|---|
| 40 s, first visit | 25.3 s (download) | 4.7 s | 4.8 s | 1.1 s | – |
| 40 s, reload | 21.8 s | 3.6 s | 4.7 s | 1.1 s | 32 s |
| 10 min, Who on CPU | 22.0 s | 23.1 s (26×) | 4.0 s | 110 s (5.5×) | 161 s |
| 10 min, Who `auto` (WebGPU) | 22.4 s | 22.3 s (27×) | 4.2 s | 86 s (7×) | 137 s |
| 60 min, Who on CPU | 25.9 s | 139 s (26×) | 4.6 s | 570 s (6.3×) | 748 s |

Every run found the three speakers, numbered the same from the first piece to the last (the 60 min run
is twelve 5-minute pieces joined by voice), and the transcript reads correctly.

**Memory.** The tab's renderer process peaked at 3.3 GB (`footprint`, `phys_footprint_peak`) and sat
at 2.0 GB while Who ran on the hour. Decoding 60 minutes for Who holds 230 MB of samples; Voz streams
the file and holds none.

**Network.** Only `localhost`, `huggingface.co` and `events.desertant.com` (license, 2–4 requests).
Large weights redirect to `us.aws.cdn.hf.co`, so the policy needs `https://*.hf.co`. Resource Timing
in a worker shows cross-origin sizes as 0 (no `Timing-Allow-Origin`), so use the network panel for bytes.

**Caching.** Voz keeps its bundle in the Cache API (`desert-ant-voz-v0.5.0`, 304 MB) and survives a
reload. Who keeps nothing of its own; its 32 MB are fetched again (or come from the HTTP cache). The
browser pane's quota was 3–4 GB and storage was not persisted.

## Findings

1. **Who is the bottleneck.** About 6× real time on one CPU core: 9½ minutes for an hour, against Voz's
   2⅓. WebGPU (`accelerator: "auto"`) saves about a fifth. Options: LiteRT's threaded build (needs
   cross-origin isolation, so COOP/COEP headers, which GitHub Pages cannot send without a service worker
   shim), run Who on chunks in several workers, or show the transcript first and the speakers when ready.
2. **Who cannot run in a worker as published.** The package needs a module worker (top-level await) and
   LiteRT.js loads its runtime with `importScripts`, which module workers refuse; the SDK swallows the
   error and `Who.load()` never settles. The spike stands in for `importScripts` with a synchronous
   fetch and `eval` (see `src/who.worker.ts`), which forces `'unsafe-eval'` into the page's policy.
   Worth reporting to Desert Ant.
3. **Voz costs ~22 s on every page load**, cached or not: compiling the graphs, not downloading. The app
   should load it in the background as soon as the page opens.
4. **Runtimes are large.** The page serves ~130 MB of ONNX Runtime and LiteRT `.wasm` (all variants were
   copied; a build only needs the ones it loads).

5. **Safari needs 5.2 GB for an hour** (the page and its workers share one WebContent process), against
   3.3 GB in Chromium. On an 8 GB Mac that is too much; release the decoded samples and Voz before Who,
   and decode for Who in pieces.

## Verdict

Go, with Who as the first problem to solve. An hour takes 12½ (Chromium) to 14 (Safari) minutes, three
quarters of it Who. The Mac app does the same hour in about a minute.

## Not done yet

- Firefox: whether WebGPU there runs Voz at all.
- The license request from a `github.io` origin (every run here was `localhost`).
