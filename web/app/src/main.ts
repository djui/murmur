import "./style.css";
import { hasWebGPU, isDownloaded, preloadVoz, registerServiceWorker } from "./models";
import { applyAppearance } from "./settings";
import { button, h } from "./ui/dom";
import { installDrop } from "./ui/drop";
import { openFile, showLibrary } from "./ui/library";
import { showProject } from "./ui/project";

const app = document.getElementById("app")!;
let leave: (() => void) | undefined;

/** `#p=<id>` is a project; anything else is the library. */
async function route() {
  leave?.();
  leave = undefined;
  app.replaceChildren();
  const id = new URLSearchParams(location.hash.slice(1)).get("p");
  leave = id ? await showProject(app, id) : await showLibrary(app);
}

export function openProject(id: string) {
  location.hash = `p=${id}`;
}

export function openLibrary() {
  location.hash = "";
}

function requirements(onContinue: () => void) {
  app.replaceChildren(h("div", { class: "library" }, h("div", { class: "library-inner" },
    h("div", { class: "drop" },
      h("h2", {}, "This browser can't run Murmur's models at speed"),
      h("p", {}, "Murmur transcribes on your graphics processor through WebGPU, which this browser doesn't offer. It works in Chrome, Edge and other Chromium browsers, and in Safari 26 or later."),
      h("p", {}, "Without WebGPU, transcription runs on the processor instead: it works, many times slower."),
      button("Continue anyway", onContinue),
    ),
  )));
}

async function boot() {
  applyAppearance();
  registerServiceWorker();
  const start = () => {
    installDrop(openFile);
    addEventListener("hashchange", route);
    route();
    // Compile Voz in the background when its weights are already here, so the next file starts at once.
    isDownloaded("voz").then((here) => here && requestIdleCallbackShim(() => preloadVoz().catch(() => {})));
  };
  if (await hasWebGPU()) start();
  else requirements(start);
}

const requestIdleCallbackShim = (f: () => void) => ("requestIdleCallback" in window ? requestIdleCallback(f, { timeout: 4000 }) : setTimeout(f, 1500));

boot();
