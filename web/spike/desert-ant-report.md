# Draft: report to Desert Ant Labs

Filed as https://github.com/Desert-Ant-Labs/desert-ant-core/issues/250 on 2026-11-01.

---

**Title:** Browser: `Who.load()` never settles in a module Web Worker; Align needs a second session

SDK 4.2.3 (`@desert-ant-labs/who` 4.2.3, `@litertjs/core` 2.6.0), Chromium 152 and Safari 27, macOS 27.

**1. Who in a Web Worker.** The README says `Who.load()` runs "in a browser or Web Worker". The package
uses top-level `await`, so it needs a module worker (`new Worker(url, { type: "module" })`). LiteRT.js
loads its runtime with `importScripts` when `typeof importScripts === "function"`, which is true in a
module worker, but module workers throw on `importScripts`. The error does not reach the caller:
`Who.load()` never settles. A classic worker can't load the package because of the top-level await.

Workaround we use: before importing Who, replace `importScripts` with a synchronous XHR plus indirect
`eval`, and rewrite `_scriptName = self.location.href` to the script's real URL so the Emscripten loader
finds its `.wasm`. It works in both browsers, but it needs `eval`. Possible fixes: load the runtime with
`import()` (an ES module build of the loader), or let the caller pass the factory in.

**2. Threads.** With the page cross-origin isolated and `loadLiteRt(dir, { threads: true })` passed
through the `litert` option, `Who.load()` again never settles in a worker, and on the main thread the
first `diarize` freezes the tab. Single-threaded, Who runs at about 6× real time in the browser (an hour
in ~10 min), which is the slowest step of our pipeline; a working threaded path would help most.

**3. Align in the browser.** `Sources/Align/Web/main.swift` throws "align needs two sessions; the wasm
host holds one". A session handle on `DalModelHost` (`createSession` returning an id, `run(id, inputs)`)
would let Align, and any other cascade, run in the browser.

**4. Minor.** `docs/models/who.md` lists Who's platforms without Web, while the README table and the
npm package support the browser.

Measurements and the test page: https://github.com/djui/murmur/tree/main/web/spike
