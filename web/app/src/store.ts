// Projects live in this browser's IndexedDB: the project itself (the Mac app's project.json), its
// waveform peaks, and, where the browser offers one (Chromium), a handle to the media file so it can be
// opened again without asking. The media itself is never copied.
import { decodeProject, encodeProject, type Project } from "./core/project";

const DB = "murmur";
const STORES = ["projects", "peaks", "handles"] as const;
type Store = (typeof STORES)[number];

let db: Promise<IDBDatabase> | undefined;

function open(): Promise<IDBDatabase> {
  db ??= new Promise((resolve, reject) => {
    const request = indexedDB.open(DB, 1);
    request.onupgradeneeded = () => {
      for (const name of STORES) if (!request.result.objectStoreNames.contains(name)) request.result.createObjectStore(name);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  return db;
}

async function run<T>(store: Store, mode: IDBTransactionMode, body: (s: IDBObjectStore) => IDBRequest<T>): Promise<T> {
  const d = await open();
  return new Promise((resolve, reject) => {
    const request = body(d.transaction(store, mode).objectStore(store));
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
}

export async function saveProject(project: Project): Promise<void> {
  await run("projects", "readwrite", (s) => s.put(encodeProject(project), project.id));
}

export async function loadProject(id: string): Promise<Project | undefined> {
  const json = await run<string | undefined>("projects", "readonly", (s) => s.get(id));
  return json ? decodeProject(json) : undefined;
}

export async function allProjects(): Promise<Project[]> {
  const all = await run<string[]>("projects", "readonly", (s) => s.getAll());
  return all.map((json) => decodeProject(json)).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
}

export async function deleteProject(id: string): Promise<void> {
  for (const store of STORES) await run(store, "readwrite", (s) => s.delete(id));
}

export async function savePeaks(id: string, peaks: Float32Array): Promise<void> {
  await run("peaks", "readwrite", (s) => s.put(peaks, id));
}

export async function loadPeaks(id: string): Promise<Float32Array | undefined> {
  return run("peaks", "readonly", (s) => s.get(id));
}

export async function saveHandle(id: string, handle: FileSystemFileHandle): Promise<void> {
  await run("handles", "readwrite", (s) => s.put(handle, id));
}

export async function loadHandle(id: string): Promise<FileSystemFileHandle | undefined> {
  return run("handles", "readonly", (s) => s.get(id));
}

/** The media file behind a stored handle, asking for permission again if the browser wants that. */
export async function fileFromHandle(handle: FileSystemFileHandle, ask: boolean): Promise<File | undefined> {
  const h = handle as FileSystemFileHandle & {
    queryPermission?(o: object): Promise<PermissionState>;
    requestPermission?(o: object): Promise<PermissionState>;
  };
  try {
    let state = (await h.queryPermission?.({ mode: "read" })) ?? "granted";
    if (state === "prompt" && ask) state = (await h.requestPermission?.({ mode: "read" })) ?? "denied";
    return state === "granted" ? await handle.getFile() : undefined;
  } catch {
    return undefined;
  }
}
