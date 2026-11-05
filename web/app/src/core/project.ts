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
  /** Stays in the paragraph before, despite a pause or the length limit: the user merged the two. */
  joinsPrevious?: boolean;
}

export interface Mark {
  id: string;
  name: string;
  start: number;
  end: number;
}

/** A note written at a moment, while recording or while listening back. */
export interface Note {
  id: string;
  text: string;
  time: number;
}

/** The part of a recording that counts: the start and end the user trimmed it to. The media is never
 *  cut; the words and marks outside are kept here so the trim can be taken off again. */
export interface Trim {
  start: number;
  end: number;
  /** Words outside `start...end`, by their midpoint. */
  words: Word[];
  /** Marks wholly outside `start...end`. */
  marks: Mark[];
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
  /** Notes written while recording or listening, each at a moment. */
  notes?: Note[];
  /** The start and end the recording is trimmed to; absent for the whole file. */
  trim?: Trim;
  redactions?: RedactedSpan[];
  /** Mac recordings: microphone words taken out as the speakers' echo. Kept as they are. */
  echo?: unknown[];
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

export function note(text: string, time: number, id = uuid()): Note {
  return { id, text, time: Math.max(0, time) };
}

/** The stretch that plays, shows and exports: the trim, or the whole file. */
export function span(project: Project): [number, number] {
  if (project.trim) return [project.trim.start, Math.max(project.trim.start, project.trim.end)];
  return [0, Math.max(0, project.duration)];
}

/** Notes inside the trim, in time order. */
export function notesOf(project: Project): Note[] {
  const [lo, hi] = span(project);
  return (project.notes ?? []).filter((n) => n.time >= lo && n.time <= hi).sort((a, b) => a.time - b.time);
}

/** Trims to `[start, end]` (clamped to the file), taking any earlier trim off first. Words whose middle
 *  falls outside and marks wholly outside move into the trim; marks across an edge are cut at it. */
export function trimTo(project: Project, start: number, end: number): Project {
  const p = removeTrim(project);
  const lo = Math.max(0, start), hi = p.duration > 0 ? Math.min(p.duration, end) : end;
  if (!(hi > lo)) return p;
  const trim: Trim = { start: lo, end: hi, words: [], marks: [] };
  const words: Word[] = [];
  for (const w of p.words) (mid(w) < lo || mid(w) > hi ? trim.words : words).push(w);
  const marks: Mark[] = [];
  for (const m of p.marks) {
    if (m.end <= lo || m.start >= hi) trim.marks.push(m);
    else marks.push({ ...m, start: Math.max(m.start, lo), end: Math.min(m.end, hi) });
  }
  return { ...p, words, marks, trim };
}

/** Takes the trim off: the whole file again, with the words and marks that were outside put back. */
export function removeTrim(project: Project): Project {
  const trim = project.trim;
  if (!trim) return project;
  const words = [...project.words, ...trim.words].map((w, i) => [w, i] as const)
    .sort((a, b) => (a[0].start === b[0].start ? a[1] - b[1] : a[0].start - b[0].start)).map(([w]) => w);
  const marks = [...project.marks, ...trim.marks].sort((a, b) => a.start - b.start);
  const { trim: _, ...rest } = project;
  return { ...rest, words, marks };
}

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
