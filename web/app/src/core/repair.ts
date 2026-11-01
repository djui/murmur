// Words the transcriber skipped, found again: MurmurCore's GapRepair. When Voz is unsure of a word it
// emits nothing, so a soft word at the end of a phrase leaves a gap that still holds speech-level
// sound. Read again with a few seconds of the phrase before it, the word comes back; read from inside
// the gap, it does not. Only new words inside the gap are kept, and only when the second reading's
// context ends on the same word the transcript does.
import { normalized } from "./merge";
import { BINS_PER_SECOND } from "./peaks";
import { mid, type Word } from "./project";

export interface Gap {
  /** Index of the word before the gap. */
  after: number;
  start: number;
  end: number;
  /** What to read again: a few seconds of the phrase before the gap, then the gap. */
  windowStart: number;
  windowEnd: number;
}

export const MINIMUM_GAP = 1.0;
export const MINIMUM_LEVEL = 0.35;
export const CONTEXT = 5.0;
export const MAXIMUM_WINDOW = 14.0;

/** The loudness of a stretch: the 75th percentile of its peaks. */
function level(peaks: Float32Array | number[], start: number, end: number, binsPerSecond: number): number {
  const lo = Math.max(0, Math.floor(start * binsPerSecond));
  const hi = Math.min(peaks.length, Math.ceil(end * binsPerSecond));
  if (lo >= hi) return 0;
  const sorted = Float32Array.from(Array.prototype.slice.call(peaks, lo, hi) as number[]).sort();
  return sorted[Math.min(sorted.length - 1, Math.floor((sorted.length * 3) / 4))];
}

/** Gaps between words that hold speech-level sound, by normalized `peaks`. */
export function gaps(words: Word[], duration: number, peaks: Float32Array | number[], binsPerSecond = BINS_PER_SECOND): Gap[] {
  if (words.length === 0 || peaks.length === 0) return [];
  const levels = words.map((w) => level(peaks, w.start, w.end, binsPerSecond)).sort((a, b) => a - b);
  const typical = levels[Math.floor(levels.length / 2)];
  if (!(typical > 0)) return [];
  const out: Gap[] = [];
  for (let i = 0; i < words.length; i++) {
    const start = words[i].end;
    const end = i + 1 < words.length ? words[i + 1].start : duration;
    if (end - start < MINIMUM_GAP || level(peaks, start + 0.05, end - 0.05, binsPerSecond) < Math.fround(MINIMUM_LEVEL * typical)) continue;
    // The window starts on a word, so the context is whole words.
    let first = words.findIndex((w, k) => k <= i && w.start >= start - CONTEXT);
    if (first < 0) first = i;
    const windowStart = Math.max(0, words[first].start - 0.15);
    const windowEnd = Math.min(duration, end + 0.3, windowStart + MAXIMUM_WINDOW);
    out.push({ after: i, start, end, windowStart, windowEnd });
  }
  return out;
}

/** `words` with what a second reading of `gap` heard inside it, or null when it heard nothing new there
 *  or its context doesn't end on the word before the gap. `heard` is in file time. */
export function splice(words: Word[], gap: Gap, heard: Word[]): Word[] | null {
  if (gap.after < 0 || gap.after >= words.length) return null;
  const before = normalized(words[gap.after].text);
  if (!before) return null;
  let anchor = -1;
  for (let k = heard.length - 1; k >= 0; k--) {
    if (normalized(heard[k].text) === before && mid(heard[k]) <= gap.start + 0.5) { anchor = k; break; }
  }
  if (anchor < 0) return null;
  const speaker = words[gap.after].speaker;
  const fresh = heard.slice(anchor + 1)
    .filter((w) => mid(w) > gap.start && mid(w) < gap.end - 0.05 && normalized(w.text) !== "")
    .map((w): Word => {
      const start = Math.max(w.start, gap.start);
      return { text: w.text, start, end: Math.max(start, Math.min(w.end, gap.end)), speaker, isFiller: false, edited: false };
    });
  if (fresh.length === 0) return null;
  return [...words.slice(0, gap.after + 1), ...fresh, ...words.slice(gap.after + 1)];
}
