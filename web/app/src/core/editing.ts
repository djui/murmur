import { isUnspaced, normalized } from "./merge";
import type { Paragraph, Project, Word } from "./project";

/** Replaces `words[lower..<upper]` with `newText`. Words that survive keep their timing; new words
 *  share the time of what they replaced. Returns the new list and the range the text now occupies. */
export function replace(words: Word[], lower: number, upper: number, newText: string): { words: Word[]; lower: number; upper: number } {
  if (upper <= lower) return { words, lower, upper };
  const speaker = words[lower].speaker;
  const replaced = retime(words.slice(lower, upper), newText, speaker);
  const out = [...words.slice(0, lower), ...replaced, ...words.slice(upper)];
  return { words: out, lower, upper: lower + replaced.length };
}

/** Lines new text up against the old words (longest common subsequence on normalized text). */
export function retime(old: Word[], newText: string, speaker: number): Word[] {
  const tokens = newText.split(/\s+/).filter(Boolean);
  if (tokens.length === 0 || old.length === 0) return [];
  const a = old.map((w) => normalized(w.text));
  const b = tokens.map(normalized);
  const pairs = lcs(a, b);

  const out: Word[] = [];
  let oi = 0, ti = 0;
  for (const [pi, pj] of [...pairs, [old.length, tokens.length] as [number, number]]) {
    // New tokens tokens[ti..<pj] replace old words old[oi..<pi].
    if (ti < pj) {
      const spanStart = oi < pi ? old[oi].start : oi > 0 ? old[oi - 1].end : old[0].start;
      const spanEnd = oi < pi ? old[pi - 1].end : pi < old.length ? old[pi].start : old[old.length - 1].end;
      const count = pj - ti;
      const length = Math.max(0.12 * count, spanEnd - spanStart);
      const start = spanEnd - spanStart >= length ? spanStart : Math.max(0, (spanStart + spanEnd) / 2 - length / 2);
      for (let k = 0; k < count; k++) {
        const s = start + (length * k) / count;
        out.push({ text: tokens[ti + k], start: s, end: Math.max(s, s + length / count), speaker, isFiller: false, edited: true });
      }
    }
    if (pi < old.length && pj < tokens.length) {
      const o = old[pi];
      out.push({ text: tokens[pj], start: o.start, end: o.end, speaker, isFiller: o.isFiller, edited: o.edited || tokens[pj] !== o.text });
    }
    oi = pi + 1;
    ti = pj + 1;
  }
  return out;
}

/** Index pairs of a longest common subsequence. */
export function lcs(a: string[], b: string[]): [number, number][] {
  const n = a.length, m = b.length;
  const dp = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
  }
  const out: [number, number][] = [];
  let i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) { out.push([i, j]); i++; j++; }
    else if (dp[i + 1][j] >= dp[i][j + 1]) i++;
    else j++;
  }
  return out;
}

/** Moves `words[lower..<upper]` to another speaker. */
export function reassign(words: Word[], lower: number, upper: number, speaker: number): Word[] {
  return words.map((w, i) => (i >= lower && i < upper ? { ...w, speaker } : w));
}

/** Folds speaker `from` into `into` and drops `from` from the speaker list. */
export function mergeSpeaker(project: Project, from: number, into: number): Project {
  if (from === into) return project;
  return {
    ...project,
    words: project.words.map((w) => (w.speaker === from ? { ...w, speaker: into } : w)),
    speakers: project.speakers.filter((s) => s.id !== from),
  };
}

/** Moves `words[lower..<upper]` to a new speaker. */
export function toNewSpeaker(project: Project, lower: number, upper: number): Project {
  const newId = Math.max(-1, ...project.speakers.map((s) => s.id)) + 1;
  return {
    ...project,
    speakers: [...project.speakers, { id: newId, name: "", isMe: false }],
    words: reassign(project.words, lower, upper, newId),
  };
}

/** The words a text selection touches, where `[from, to)` are character offsets into `join(words)`.
 *  `[lower, upper)` relative to `words`; null when the selection covers no word. */
export function wordsTouching(words: Word[], from: number, to: number): [number, number] | null {
  if (to <= from) return null;
  let offset = 0, first: number | null = null, last: number | null = null;
  let previous: string | undefined;
  words.forEach((word, i) => {
    if (!word.text) return;
    const chars = [...word.text];
    if (previous != null && !(isUnspaced(previous) && isUnspaced(chars[0]))) offset += 1;
    const lo = offset, hi = offset + chars.length;
    if (lo < to && from < hi) {
      if (first == null) first = i;
      last = i;
    }
    offset = hi;
    previous = chars.at(-1);
  });
  return first == null || last == null ? null : [first, last + 1];
}

/** Who to offer first for words taken from a paragraph: the speaker of the line before when the words
 *  start the paragraph, the line after when they end it, when that's someone else. */
export function suggestedSpeakers(lower: number, upper: number, paragraph: Paragraph, before?: number, after?: number): number[] {
  const out: number[] = [];
  if (lower <= paragraph.lower && before != null && before !== paragraph.speaker) out.push(before);
  if (upper >= paragraph.upper && after != null && after !== paragraph.speaker && !out.includes(after)) out.push(after);
  return out;
}

