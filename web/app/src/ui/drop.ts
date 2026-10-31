// Drop a file anywhere on the page to open it: a recording starts a project, a project file opens
// it. Without this the browser would open a dropped file itself and leave Murmur.
import { h } from "./dom";

export type DropHandler = (file: File, handle?: FileSystemFileHandle) => Promise<void> | void;

/** Gets a dropped file first, before the default; returns true when it took the file. */
let intercept: ((file: File, handle?: FileSystemFileHandle) => Promise<boolean>) | undefined;

/** Lets the open project take a dropped file (the media it's missing) before it becomes a new project. */
export function interceptDrops(f: typeof intercept): () => void {
  intercept = f;
  return () => {
    if (intercept === f) intercept = undefined;
  };
}

export function installDrop(open: DropHandler) {
  const overlay = h("div", { class: "drop-overlay", hidden: true, "aria-hidden": "true" },
    h("div", {}, h("strong", {}, "Drop to open"), h("span", {}, "The file stays on this computer.")));
  document.body.append(overlay);
  let depth = 0;
  const hasFiles = (e: DragEvent) => [...(e.dataTransfer?.types ?? [])].includes("Files");
  const hide = () => {
    depth = 0;
    overlay.hidden = true;
  };

  window.addEventListener("dragenter", (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    depth++;
    overlay.hidden = false;
  });
  window.addEventListener("dragover", (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    if (e.dataTransfer) e.dataTransfer.dropEffect = "copy";
  });
  window.addEventListener("dragleave", (e) => {
    if (!hasFiles(e)) return;
    depth = Math.max(0, depth - 1);
    if (depth === 0) overlay.hidden = true;
  });
  window.addEventListener("drop", async (e) => {
    if (!hasFiles(e)) return;
    e.preventDefault();
    hide();
    const item = [...(e.dataTransfer?.items ?? [])].find((i) => i.kind === "file");
    if (!item) return;
    // Both have to be asked for before the first await: the drop's data is gone after it.
    const getHandle = (item as DataTransferItem & { getAsFileSystemHandle?: () => Promise<FileSystemHandle | null> }).getAsFileSystemHandle;
    const handlePromise = getHandle?.call(item);
    const file = item.getAsFile();
    if (!file) return;
    const handle = (await handlePromise?.catch(() => null)) ?? undefined;
    const fileHandle = handle?.kind === "file" ? (handle as FileSystemFileHandle) : undefined;
    if (await intercept?.(file, fileHandle)) return;
    await open(file, fileHandle);
  });
  window.addEventListener("blur", hide);
}
