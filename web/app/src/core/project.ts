// TypeScript port of MurmurCore (Packages/MurmurCore). The same cases run against both through
// Packages/MurmurCore/Tests/Fixtures/core.json, so keep the two in step.
//
// A project here is the same `project.json` the Mac app writes: same keys, same values.

export type Status = "new" | "processing" | "ready" | "failed";

export interface MediaRef {
  /** The file's name. The browser never sees a full path. */
  path: string;
  hasVideo: boolean;
  fileSize?: number;
  micStem?: string;
  systemStem?: string;
}

export interface ProjectSettings {
  enhance: boolean;
  showFillers: boolean;
  showVideo: boolean;
  redact?: boolean;
}

export interface Speaker {
  id: number;
  name: string;
  isMe: boolean;
}

export interface Word {
  text: string;
  start: number;
  end: number;
  speaker: number;
  isFiller: boolean;
  /** Typed by the user rather than heard by the transcriber. */
  edited: boolean;
}

export interface Mark {
  id: string;
  name: string;
  start: number;
  end: number;
}

export interface RedactedSpan {
  start: number;
  end: number;
  category: string;
  original: string;
  revealed: boolean;
}

export interface Project {
  formatVersion: number;
  id: string;
  status: Status;
  media?: MediaRef;
  duration: number;
  language?: string;
  languageConfidence?: number;
  languageWarning?: string;
  transcriber?: string;
  title?: string;
  summary?: string;
  titleIsGenerated: boolean;
  speakers: Speaker[];
  words: Word[];
  marks: Mark[];
  redactions?: RedactedSpan[];
  settings: ProjectSettings;
  /** ISO 8601, as the Mac app writes it. */
  createdAt: string;
  processedAt?: string;
  failure?: string;
}

/** A run of words by one speaker: `words[lower..<upper]`. */
export interface Paragraph {
  speaker: number;
  lower: number;
  upper: number;
  start: number;
  end: number;
}

export function uuid(): string {
  return crypto.randomUUID().toUpperCase();
}

export function newProject(): Project {
  return {
    formatVersion: 1,
    id: uuid(),
    status: "new",
    duration: 0,
    titleIsGenerated: false,
    speakers: [],
    words: [],
    marks: [],
    settings: { enhance: false, showFillers: true, showVideo: true },
    createdAt: new Date().toISOString(),
  };
}

export function word(text: string, start: number, end: number, speaker = 0, isFiller = false, edited = false): Word {
  return { text, start, end: Math.max(start, end), speaker, isFiller, edited };
}

export function mark(name: string, start: number, end: number, id = uuid()): Mark {
  return { id, name, start: Math.min(start, end), end: Math.max(start, end) };
}

export const mid = (w: Word) => (w.start + w.end) / 2;

export function speakerName(s: Speaker): string {
  if (s.name.trim()) return s.name;
  return s.isMe ? "Me" : `Speaker ${s.id + 1}`;
}

export function nameOf(project: Project, id: number): string {
  const s = project.speakers.find((x) => x.id === id);
  return s ? speakerName(s) : `Speaker ${id + 1}`;
}

export function displayTitle(project: Project): string {
  if (project.title) return project.title;
  return project.media ? project.media.path.replace(/\.[^.]+$/, "") : "Untitled";
}

/** Reads a `project.json`, filling what older files leave out. */
export function decodeProject(json: string | object): Project {
  const raw = (typeof json === "string" ? JSON.parse(json) : json) as Partial<Project>;
  const base = newProject();
  return {
    ...base,
    ...raw,
    settings: { ...base.settings, ...raw.settings },
    speakers: raw.speakers ?? [],
    words: (raw.words ?? []).map((w) => ({ ...w, isFiller: w.isFiller ?? false, edited: w.edited ?? false })),
    marks: raw.marks ?? [],
  } as Project;
}

/** `project.json` with sorted keys, as the Mac app writes it. */
export function encodeProject(project: Project): string {
  return JSON.stringify(sortKeys(project));
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(value).sort()) {
      const v = (value as Record<string, unknown>)[key];
      if (v !== undefined) out[key] = sortKeys(v);
    }
    return out;
  }
  return value;
}
