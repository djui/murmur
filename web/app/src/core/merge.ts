import { mid, type Paragraph, type Word } from "./project";

/** A stretch of time attributed to one speaker by the diarizer. */
export interface SpeakerTurn {
  start: number;
  end: number;
  speaker: number;
}

/** Gives each word the speaker whose turn overlaps it most (the nearest turn when none does), then
 *  renumbers speakers from `firstId` in order of first appearance. */
export function assign(words: Word[], turns: SpeakerTurn[], firstId = 0): Word[] {
  if (turns.length === 0) return words.map((w) => ({ ...w, speaker: firstId }));
  const sorted = [...turns].sort((a, b) => a.start - b.start);
  const raw = words.map((word) => {
    let best = -1;
    let bestOverlap = 0;
    let nearest = sorted[0].speaker;
    let nearestDistance = Infinity;
    for (const turn of sorted) {
      if (turn.start > word.end + 30) break;
      const overlap = Math.min(word.end, turn.end) - Math.max(word.start, turn.start);
      if (overlap > bestOverlap) {
        bestOverlap = overlap;
        best = turn.speaker;
      }
      const m = mid(word);
      const distance = m < turn.start ? turn.start - m : m > turn.end ? m - turn.end : 0;
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = turn.speaker;
      }
    }
    return { ...word, speaker: best >= 0 ? best : nearest };
  });
  const order = new Map<number, number>();
  for (const w of raw) if (!order.has(w.speaker)) order.set(w.speaker, firstId + order.size);
  return raw.map((w) => ({ ...w, speaker: order.get(w.speaker) ?? firstId }));
}

/** Groups words into paragraphs: a new one starts at a speaker change, a pause longer than `maxGap`,
 *  or at a sentence end once a paragraph runs longer than `maxLength` seconds. */
export function paragraphs(words: Word[], maxGap = 1.5, maxLength = 45): Paragraph[] {
  if (words.length === 0) return [];
  const out: Paragraph[] = [];
  let startIndex = 0;
  const close = (end: number) => {
    if (end <= startIndex) return;
    out.push({ speaker: words[startIndex].speaker, lower: startIndex, upper: end, start: words[startIndex].start, end: words[end - 1].end });
    startIndex = end;
  };
  for (let i = 1; i < words.length; i++) {
    const prev = words[i - 1], cur = words[i];
    const long = prev.end - words[startIndex].start > maxLength && endsSentence(prev.text);
    if (cur.speaker !== prev.speaker || cur.start - prev.end > maxGap || long) close(i);
  }
  close(words.length);
  return out;
}

/** Characters of scripts written without spaces (Chinese, Japanese, Thai). */
export function isUnspaced(c: string | undefined): boolean {
  const v = c?.codePointAt(0);
  if (v == null) return false;
  return (v >= 0x3000 && v <= 0x30ff) || (v >= 0x3400 && v <= 0x4dbf) || (v >= 0x4e00 && v <= 0x9fff)
    || (v >= 0xff00 && v <= 0xffef) || (v >= 0x0e00 && v <= 0x0e7f);
}

const lastChar = (s: string) => [...s].at(-1);

/** Joins words with spaces, except between characters of scripts written without them. */
export function join(texts: (string | Word)[]): string {
  let out = "";
  for (const item of texts) {
    const text = typeof item === "string" ? item : item.text;
    if (!text) continue;
    if (out && !(isUnspaced(lastChar(out)) && isUnspaced(text[0]))) out += " ";
    out += text;
  }
  return out;
}

/** Keeps word starts in transcript order after re-timing, so nothing swaps places. */
export function monotonic(words: Word[]): Word[] {
  const out = words.map((w) => ({ ...w }));
  for (let i = 1; i < out.length; i++) {
    if (out[i].start < out[i - 1].start) {
      out[i].start = out[i - 1].start;
      out[i].end = Math.max(out[i].end, out[i].start);
    }
  }
  return out;
}

export function nearest(time: number, words: Word[]): Word | undefined {
  let best: Word | undefined;
  for (const w of words) if (!best || Math.abs(mid(w) - time) < Math.abs(mid(best) - time)) best = w;
  return best;
}

/** Lowercased with punctuation removed, for comparing words. */
export function normalized(text: string): string {
  return text.toLowerCase().replace(/[^\p{L}\p{M}\p{N}]/gu, "");
}

export function endsSentence(text: string): boolean {
  const last = lastChar(text);
  return last != null && ".?!…".includes(last);
}

/** Words whose midpoint lies inside `start...end`: cuts snap to whole words. `[lower, upper)`. */
export function indices(words: Word[], start: number, end: number): [number, number] {
  let lo = words.findIndex((w) => mid(w) >= start);
  if (lo < 0) lo = words.length;
  let hi = lo;
  for (let i = words.length - 1; i >= 0; i--) if (mid(words[i]) <= end) { hi = i + 1; break; }
  return [lo, Math.max(lo, hi)];
}
