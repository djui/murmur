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
"Copy as Markdown" puts a run's numbers on the clipboard.

## Results

Chromium 152 (the Claude app's browser pane), Apple Silicon Mac with 8 cores, WebGPU on Metal, no WebNN,
SDK 4.2.3. The test audio is the site's 40 s sample (three synthetic voices) looped.

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

## Not done yet

- Safari 26: run the same three files and paste "Copy as Markdown".
- Firefox: whether WebGPU there runs Voz at all.
