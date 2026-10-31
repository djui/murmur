import { decodeProject, displayTitle, newProject, type Project } from "../core/project";
import * as Timecode from "../core/timecode";
import { openProject } from "../main";
import { allProjects, deleteProject, saveHandle, saveProject } from "../store";
import { pendingFiles } from "./session";
import { button, confirm, h, icon, toast } from "./dom";
import { showSettings } from "./settings";

const ACCEPT = "audio/*,video/*,.m4a,.mp3,.wav,.aac,.flac,.ogg,.opus,.webm,.mp4,.mov,.m4v,.caf,.aiff";

/** Starts a project for a file: stores it (and its handle, where there is one) and opens it. */
export async function newProjectFor(file: File, handle?: FileSystemFileHandle) {
  const p: Project = {
    ...newProject(),
    media: { path: file.name, hasVideo: file.type.startsWith("video/") || /\.(mp4|mov|m4v|webm)$/i.test(file.name), fileSize: file.size },
  };
  await saveProject(p);
  if (handle) await saveHandle(p.id, handle).catch(() => {});
  pendingFiles.set(p.id, { file, process: true });
  openProject(p.id);
}

/** A file from the system picker. Chromium returns a handle, so the project can find the file again. */
export async function pickFile(): Promise<{ file: File; handle?: FileSystemFileHandle } | undefined> {
  const picker = (window as { showOpenFilePicker?: (o: object) => Promise<FileSystemFileHandle[]> }).showOpenFilePicker;
  if (picker) {
    try {
      const [handle] = await picker({ types: [{ description: "Audio and video", accept: { "audio/*": [], "video/*": [] } }] });
      return { file: await handle.getFile(), handle };
    } catch (error) {
      if ((error as Error).name === "AbortError") return undefined;
    }
  }
  return new Promise((resolve) => {
    const input = h("input", { type: "file", accept: ACCEPT });
    input.addEventListener("change", () => resolve(input.files?.[0] ? { file: input.files[0] } : undefined));
    input.click();
  });
}

export async function showLibrary(root: HTMLElement): Promise<() => void> {
  const projects = await allProjects();
  const list = h("div", { class: "list" });

  const render = (items: Project[]) => {
    list.replaceChildren(...(items.length === 0 ? [h("div", { class: "empty" }, "Projects you open appear here. They stay in this browser.")] : items.map((p) =>
      h("div", { class: "row", tabindex: 0, role: "link", on: { click: () => openProject(p.id), keydown: (e: KeyboardEvent) => e.key === "Enter" && openProject(p.id) } },
        h("div", {},
          h("div", { class: "name" }, displayTitle(p)),
          h("div", { class: "meta" }, [p.media?.path, p.duration ? Timecode.short(p.duration) : null, p.speakers.length ? `${p.speakers.length} speakers` : null,
            p.status === "ready" ? null : p.status === "processing" ? "Not finished" : p.status].filter(Boolean).join(" · ")),
        ),
        h("div", { class: "meta mono" }, new Date(p.createdAt).toLocaleDateString()),
        button("Delete", async (e) => {
          e.stopPropagation();
          if (await confirm(`Delete “${displayTitle(p)}”?`, "The transcript, speakers and marks are removed from this browser. The media file is not touched.", "Delete", true)) {
            await deleteProject(p.id);
            render((await allProjects()));
          }
        }, { icon: "trash", iconOnly: true }),
      ),
    )));
  };
  render(projects);

  const search = h("input", { type: "search", placeholder: "Search titles and transcripts", "aria-label": "Search titles and transcripts",
    on: { input: () => {
      const q = search.value.trim().toLowerCase();
      render(q ? projects.filter((p) => displayTitle(p).toLowerCase().includes(q) || p.words.some((w) => w.text.toLowerCase().includes(q))) : projects);
    } } });

  const open = async () => {
    const picked = await pickFile();
    if (picked) newProjectFor(picked.file, picked.handle);
  };
  /** A project file downloaded from Murmur in the browser (the Mac app's project.json); the media is located on opening. */
  const importProject = () => {
    const input = h("input", { type: "file", accept: ".json,application/json" });
    input.addEventListener("change", async () => {
      const f = input.files?.[0];
      if (!f) return;
      try {
        const p = decodeProject(await f.text());
        if (!Array.isArray(p.words) || !p.id) throw new Error("not a project");
        await saveProject(p);
        openProject(p.id);
      } catch {
        toast("That file isn't a Murmur project.");
      }
    });
    input.click();
  };
  const sample = async () => {
    const blob = await fetch(new URL("sample.m4a", document.baseURI)).then((r) => r.blob());
    newProjectFor(new File([blob], "Field Notes sample.m4a", { type: "audio/mp4" }));
  };

  const drop = h("div", { class: "drop" },
    h("h2", {}, "Who said what, when."),
    h("p", {}, "Open an interview, a podcast or a call. Murmur writes down every word, tells the voices apart and lays them out on a timeline. Everything happens in this browser: the file is never uploaded."),
    h("div", { class: "actions" },
      button("Open a recording…", open, { class: "primary", icon: "file" }),
      button("Try a 40-second sample", sample),
      button("Open a project file…", importProject),
    ),
    h("p", { class: "note" }, "Or drop a file here. The first time, the speech models (about 340 MB) download from Hugging Face and stay in this browser."),
  );
  const onDrag = (e: DragEvent) => {
    e.preventDefault();
    drop.classList.toggle("over", e.type === "dragover");
  };
  const onDrop = async (e: DragEvent) => {
    e.preventDefault();
    drop.classList.remove("over");
    const item = [...(e.dataTransfer?.items ?? [])].find((i) => i.kind === "file");
    if (!item) return;
    const getHandle = (item as DataTransferItem & { getAsFileSystemHandle?: () => Promise<FileSystemHandle | null> }).getAsFileSystemHandle;
    const handlePromise = getHandle?.call(item);
    const file = item.getAsFile();
    const handle = (await handlePromise?.catch(() => null)) as FileSystemFileHandle | null | undefined;
    if (file) newProjectFor(file, handle?.kind === "file" ? handle : undefined);
  };
  root.addEventListener("dragover", onDrag);
  root.addEventListener("dragleave", onDrag);
  root.addEventListener("drop", onDrop);

  root.append(
    h("header", { class: "bar" },
      h("a", { class: "brand", href: "#" }, h("img", { src: "icon.png", alt: "" }), "Murmur"),
      h("div", { class: "grow" }),
      search,
      button("Settings", () => showSettings(), { icon: "gear", iconOnly: true }),
    ),
    h("main", { class: "library" }, h("div", { class: "library-inner" },
      drop,
      h("section", {}, h("h2", { class: "section-title" }, "Projects"), list),
      h("footer", { class: "note" },
        h("p", {}, icon("eye"), " Nothing you open leaves this browser: the page may only talk to Hugging Face (model weights) and Desert Ant Labs (an anonymous license check when a model loads). Open your browser's network panel to see for yourself."),
        h("p", {}, "Speech models by ", h("a", { href: "https://desertant.com", rel: "noopener" }, "Desert Ant Labs"), " under the ", h("a", { href: "https://license.desertant.com/1.0", rel: "noopener" }, "Desert Ant Labs Source-Available License"),
          ". Voz weights based on NVIDIA Parakeet TDT 0.6B v3, ", h("a", { href: "https://creativecommons.org/licenses/by/4.0/", rel: "noopener" }, "CC BY 4.0"),
          ". On a Mac, the ", h("a", { href: "https://djui.github.io/murmur/", rel: "noopener" }, "Murmur app"), " is faster and also records calls."),
      ),
    )),
  );

  return () => {
    root.removeEventListener("dragover", onDrag);
    root.removeEventListener("dragleave", onDrag);
    root.removeEventListener("drop", onDrop);
  };
}
