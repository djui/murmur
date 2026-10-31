import { indices, join, paragraphs as groupParagraphs } from "./merge";
import { nameOf, type Project, type Word } from "./project";
import { apply, type RedactionStyle } from "./redactor";
import * as Timecode from "./timecode";

export type TextFormat = "plain" | "timestamps" | "markdown" | "srt" | "vtt" | "json";

export const textFormats: { id: TextFormat; title: string; ext: string }[] = [
  { id: "plain", title: "Plain text", ext: "txt" },
  { id: "timestamps", title: "Text with timestamps", ext: "txt" },
  { id: "markdown", title: "Markdown", ext: "md" },
  { id: "srt", title: "SRT subtitles", ext: "srt" },
  { id: "vtt", title: "WebVTT", ext: "vtt" },
  { id: "json", title: "JSON (words)", ext: "json" },
];

/** The formats offered in the Copy menu. */
export const copyFormats: TextFormat[] = ["plain", "timestamps", "markdown", "srt"];

export interface RenderOptions {
  speakerNames: boolean;
  hideFillers: boolean;
  /** Times count from the start of each section instead of the start of the file. */
  relativeTimes: boolean;
  redactionStyle: RedactionStyle;
}

export const defaultOptions: RenderOptions = { speakerNames: true, hideFillers: true, relativeTimes: false, redactionStyle: "labels" };

/** A named part of the recording to render, such as a mark or the selection. */
export interface TranscriptSection {
  name?: string;
  start: number;
  end: number;
}

const WHOLE = Number.MAX_VALUE;

/** Renders `sections` (the whole file when absent) of `project` as `format`. */
export function render(project: Project, format: TextFormat, sections?: TranscriptSection[], options: Partial<RenderOptions> = {}): string {
  const o = { ...defaultOptions, ...options };
  const parts = sections ?? [{ start: 0, end: WHOLE }];
  const showHeadings = sections != null && parts.length > 1;
  if (format === "json") return json(project, parts, o);
  if (format === "srt" || format === "vtt") return subtitles(project, parts, format, o);
  const blocks: string[] = [];
  if (format === "markdown" && project.title) blocks.push(`# ${project.title}`);
  if (format === "markdown" && project.summary && sections == null) blocks.push(`> ${project.summary}`);
  for (const section of parts) {
    const offset = o.relativeTimes ? section.start : 0;
    if (showHeadings || (format === "markdown" && section.name != null)) {
      const range = `${Timecode.short(section.start)} – ${Timecode.short(section.end)}`;
      const name = section.name ?? "Section";
      blocks.push(format === "markdown" ? `## ${name} (${range})` : `— ${name} (${range}) —`);
    }
    for (const [speaker, words] of sectionParagraphs(project, section, o)) {
      const text = join(words);
      const who = nameOf(project, speaker);
      const time = Timecode.short((words[0]?.start ?? 0) - offset);
      if (format === "markdown") blocks.push(o.speakerNames ? `**${who}** · ${time}\n${text}` : `${time}\n${text}`);
      else if (format === "timestamps") blocks.push(o.speakerNames ? `[${time}] ${who}: ${text}` : `[${time}] ${text}`);
      else blocks.push(o.speakerNames ? `${who}: ${text}` : text);
    }
  }
  return blocks.join("\n\n") + "\n";
}

/** The words of a section grouped into paragraphs, with fillers dropped when asked. */
function sectionParagraphs(project: Project, section: TranscriptSection, o: RenderOptions): [number, Word[]][] {
  const [lo, hi] = indices(project.words, section.start, section.end);
  const words = visibleWords(project, lo, hi, o);
  return groupParagraphs(words).map((p) => [p.speaker, words.slice(p.lower, p.upper)]);
}

/** The words of a range as people should see them: fillers dropped when asked, personal details
 *  replaced while redaction is on. */
export function visibleWords(project: Project, lo: number, hi: number, o: RenderOptions): Word[] {
  let words = project.words.slice(lo, hi);
  if (o.hideFillers) words = words.filter((w) => !w.isFiller);
  if (project.settings.redact === true) words = apply(words, project.redactions ?? [], o.redactionStyle);
  return words;
}

function subtitles(project: Project, sections: TranscriptSection[], format: "srt" | "vtt", o: RenderOptions): string {
  const cues: string[] = [];
  let n = 0;
  for (const section of sections) {
    const offset = o.relativeTimes ? section.start : 0;
    for (const [speaker, words] of sectionParagraphs(project, section, o)) {
      for (const chunk of cueChunks(words)) {
        n += 1;
        const start = chunk[0].start - offset, end = chunk.at(-1)!.end - offset;
        const text = join(chunk);
        const who = nameOf(project, speaker);
        if (format === "srt") cues.push(`${n}\n${Timecode.srt(start)} --> ${Timecode.srt(end)}\n` + (o.speakerNames ? `${who}: ${text}` : text));
        else cues.push(`${Timecode.vtt(start)} --> ${Timecode.vtt(end)}\n` + (o.speakerNames ? `<v ${who}>${text}` : text));
      }
    }
  }
  const body = cues.join("\n\n") + "\n";
  return format === "vtt" ? "WEBVTT\n\n" + body : body;
}

/** Splits a paragraph into subtitle-sized cues: at most ~6 s or ~80 characters. */
function cueChunks(words: Word[]): Word[][] {
  const out: Word[][] = [];
  let cur: Word[] = [];
  let chars = 0;
  for (const w of words) {
    if (cur.length && (w.end - cur[0].start > 6 || chars + [...w.text].length > 80)) {
      out.push(cur);
      cur = [];
      chars = 0;
    }
    cur.push(w);
    chars += [...w.text].length + 1;
  }
  if (cur.length) out.push(cur);
  return out;
}

const round3 = (v: number) => Math.round(v * 1000) / 1000;

function json(project: Project, sections: TranscriptSection[], o: RenderOptions): string {
  const speakers = project.speakers.map((s) => ({ id: s.id, name: nameOf(project, s.id) }));
  const parts = sections.map((section) => {
    const offset = o.relativeTimes ? section.start : 0;
    const [lo, hi] = indices(project.words, section.start, section.end);
    const words = visibleWords(project, lo, hi, o).map((w) => ({
      text: w.text, start: round3(w.start - offset), end: round3(w.end - offset), speaker: w.speaker, filler: w.isFiller,
    }));
    const end = section.end === WHOLE ? project.duration : section.end;
    return { name: section.name, start: section.start, end, words };
  });
  return swiftJSON({ title: project.title, summary: project.summary, language: project.language, duration: project.duration, speakers, sections: parts });
}

/** JSON as Foundation's encoder writes it with pretty printing and sorted keys (`"key" : value`, two
 *  spaces, no key for a missing value), so an export reads the same from either app. */
export function swiftJSON(value: unknown, indent = ""): string {
  const inner = indent + "  ";
  if (Array.isArray(value)) {
    if (value.length === 0) return "[\n\n" + indent + "]";
    return "[\n" + value.map((v) => inner + swiftJSON(v, inner)).join(",\n") + "\n" + indent + "]";
  }
  if (value && typeof value === "object") {
    const keys = Object.keys(value).filter((k) => (value as Record<string, unknown>)[k] !== undefined).sort();
    if (keys.length === 0) return "{\n\n" + indent + "}";
    return "{\n" + keys.map((k) => `${inner}${JSON.stringify(k)} : ${swiftJSON((value as Record<string, unknown>)[k], inner)}`).join(",\n") + "\n" + indent + "}";
  }
  return JSON.stringify(value);
}
