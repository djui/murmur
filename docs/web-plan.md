# Murmur in the browser — plan

Nothing implemented yet. Written against `main` at 0638e39 (v0.1.17 plus the vertical timeline and model
revision stamping) and Desert Ant SDK 4.2.3, the version `project.yml` pins.

## 1. Goal

A page at `djui.github.io/murmur/app/` that does what the Mac app does for an existing file: transcript,
speakers on a timeline, marks, editing, redaction and export. The file never leaves the browser tab. No
server of ours, no account.

It keeps the product principles in `PRODUCT.md`: nothing about the recording leaves the device ("the Mac"
becomes "this computer"), and every word stays tied to its moment and its speaker. It gives up some of
principle 3 (precision), because Align does not run in a browser yet; section 3 says where.

## 2. Decisions

| Topic | Decision |
|---|---|
| Hosting | Static files on the existing GitHub Pages site. The landing page in `site/` stays build-free; the app is built from `web/` into `site/app/` by `pages.yml`. |
| Models | Downloaded by the browser straight from Hugging Face (the SDK default). We host no weights. |
| Stack | TypeScript, Vite, no UI framework at first (the site's demo timeline is vanilla JS and a starting point). Models run in a Web Worker. |
| Browsers | Needs WebGPU: Chromium 135+ and Safari 26+ (the browsers Voz is tested on). Others get a clear "this browser can't run Murmur" screen. Firefox: check during the spike. |
| Formats | Whatever the browser decodes (Web Audio / `<video>`): mp3, m4a, aac, wav, flac, mp4, mov in Safari and Chromium; WebM and Ogg in Chromium too. |
| Projects | Kept in the browser (IndexedDB). "Download project" and "Open project" for moving them; format is `project.json`, the same `Project` schema as the Mac app. |
| Media | Referenced, not copied. In Chromium the file handle is kept, so a project reopens without asking (permission prompt only). In Safari the user picks the file again ("Locate file…", as the Mac app does when media moves). |
| Design | `DESIGN.md` tokens and type; light and dark follow the system and the Appearance setting. Keyboard first, same default shortcuts as `Shortcuts.swift`. |
| Telemetry | None of ours. The only requests are model downloads and Desert Ant's license request (install id, model id, page origin; never audio). |

## 3. What changes from the Mac app

| Mac app | Browser | Note |
|---|---|---|
| Voz transcript | Same model on WebGPU | `@desert-ant-labs/voz` + `onnxruntime-web`. WER level with Core ML (SDK docs). ~38× real time on an M1 in Chromium, ~35× in Safari. |
| Who speakers | Same model, CPU (try WebGPU with `accelerator: "auto"`) | `@desert-ant-labs/who` + `@litertjs/core`. |
| Ear + Tongue language check | Same | `@desert-ant-labs/ear`, `@desert-ant-labs/tongue`. |
| Redact | Same | `@desert-ant-labs/redact`. |
| Clear | Same, optional | `@desert-ant-labs/clear`. |
| **Align** word timing | **Dropped**: Voz's own word timestamps | SDK: "the wasm host holds one model per module and the cascade is two". Edited words keep the old word's span split by character count instead of being re-timed. |
| **Uhm** fillers | **Dropped** in v1 | No npm package; `uhm-web-fp16.onnx` exists, so a later version can run it with `onnxruntime-web` (positions only, no um/uh/hmm types). |
| **Apple Intelligence** name + summary | **Dropped** | Project is named after the file. Optional later: Chrome's on-device Summarizer API, Chromium only. |
| **Apple transcriber** fallback | **Dropped** | A language Voz lacks gets "Murmur can't transcribe <language> in the browser" and the choice to transcribe with Voz anyway. |
| Meeting recording | **Dropped** in v1 | Later: microphone, or one tab's sound via `getDisplayMedia`. No other apps, no hidden-from-sharing window, no global ⌥⌘M. |
| Audio clip export | Kept, as WAV | Mixed and bleeped in the page (`OfflineAudioContext` + a WAV writer). |
| Video clip export | **Dropped** in v1 | Later: WebCodecs + an MP4 muxer. |
| Library window, Sparkle, Trash | Library page; no updates to install; delete is a confirmation | |

## 4. Models: where they go

- **Source:** Hugging Face, `desert-ant-labs/<model>` at the revision the npm package pins.
- **Voz (≈467 MB):** the package caches its bundle in the Cache API itself (`cache: true`).
- **Who, Ear, Redact, Clear (LiteRT):** the SDK keeps these in memory and leaves re-fetching to the HTTP
  cache. A service worker of ours caches the Hugging Face responses in the Cache API, keyed by URL (which
  holds the revision), so they persist and the app works offline after the first visit.
- **Persistence:** call `navigator.storage.persist()` after the first download; without it the browser may
  evict under disk pressure (Safari most readily).
- **Settings → Models:** size of each model (`navigator.storage.estimate()` plus cache entry sizes),
  Remove per model, Download again.
- **New weights:** like the Mac app's revision stamping (0638e39), a cached file from another revision is
  deleted when the SDK version changes.
- **Memory:** Voz needs about 1.2 GB while loaded (2.4–2.7 GB peak for the whole browser per the SDK).
  The browser runs Voz, then releases it, then Who, instead of both at once as the Mac app does.

## 5. Privacy guarantee, made checkable

- A Content-Security-Policy `<meta>` on the app page: `default-src 'self'`, `connect-src 'self'` plus the
  Hugging Face hosts and `events.desertant.com`, `script-src 'self' 'wasm-unsafe-eval'`, `worker-src 'self'`.
  The exact Hugging Face download hosts (redirect targets) are found in the spike.
- The app page loads no third-party scripts; onnxruntime-web and LiteRT.js `.wasm` files are served from
  `site/app/` (`wasmDir` / `litertWasmDir`).
- The privacy section of the landing page says how to check: open the browser's network panel.
- Attribution: Desert Ant Labs (license), Voz weights CC BY 4.0.

## 6. Architecture

```
web/
  src/core/       TypeScript port of MurmurCore (Project, Editing, Merge, Formats, Redactor,
                  MarkLayout, TimeFormat, Peaks, SpeakerPalettes, Shortcuts)
  src/pipeline/   worker: decode → Ear (+ Voz sample, Tongue) → Voz → Who → merge → Redact
  src/models/     load, cache, remove, sizes, revision check
  src/ui/         library, onboarding/models, project (timeline, transcript, sidebar), export, settings
  src/store/      IndexedDB projects, file handles
  sw.ts           service worker: model cache
```

- **Decode:** `decodeAudioData` in an `OfflineAudioContext` at 16 kHz, then mono. Two hours of stereo is
  about 0.9 GB of floats at that rate; if that is too much, decode in chunks with WebCodecs (spike decides).
- **Playback:** `<audio>`/`<video>` on an object URL of the user's file.
- **Core parity:** the Swift tests in `MurmurCoreTests` export their cases as JSON fixtures; the TypeScript
  tests (Vitest) run the same fixtures, so both ports stay identical. Fixtures live in
  `Packages/MurmurCore/Tests/Fixtures/` and are shared.
- **Pages:** `pages.yml` gains `npm ci && npm run build` in `web/` writing to `site/app/`; the path filter
  adds `web/**`.

## 7. Phases

1. **Spike (go/no-go).** One page: pick a file, Voz then Who in a worker, print the turns. Measure a
   60-minute file in Chromium and Safari: time, peak memory, decode memory. Confirm CSP hosts, the service
   worker cache across reloads, and the license request from a `github.io` origin.
   Code and Chromium results: [web/spike](../web/spike/README.md).
2. **Core port** with the shared fixtures, and the fixture export on the Swift side.
3. **Pipeline and models:** worker, progress, model screen, cache, Settings → Models.
4. **Project view:** timeline (horizontal and vertical, zoom, scrub, lanes, playhead), transcript with the
   current word, playback, marks, keyboard shortcuts, colour schemes.
5. **Editing and output:** fix words, rename/merge/reassign speakers, undo, redaction toggle and per-item
   reveal, all text exports, WAV clips.
6. **Library and release:** IndexedDB projects, download/open project, "Try in your browser" on the
   landing page, CSP, requirements screen, Pages build.

Later, in order of value: Uhm via ONNX, microphone/tab recording, video clips, Chrome summary, and Align
as soon as the SDK's browser host holds more than one model.

## 8. Open questions

- Should the Mac app open a project downloaded from the browser (and the reverse)? Same `project.json`,
  but the Mac app expects a `.murmur` package and a bookmarked media path.
- Firefox: support it if WebGPU there runs Voz, or show the requirements screen?
- URL: `/murmur/app/` or a separate subdomain?
