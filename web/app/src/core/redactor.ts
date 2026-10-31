import { isUnspaced } from "./merge";
import { mid, type RedactedSpan, type Word } from "./project";

export type RedactionStyle = "labels" | "bars" | "initials";

export const redactionStyles: { id: RedactionStyle; title: string }[] = [
  { id: "labels", title: "Labels, like [name]" },
  { id: "bars", title: "Black bars" },
  { id: "initials", title: "Initials for names" },
];

/** The hidden span a word falls in, if any. */
export function spanFor(word: Word, spans: RedactedSpan[]): RedactedSpan | undefined {
  const m = mid(word);
  return spans.find((s) => !s.revealed && m >= s.start && m <= s.end);
}

export function replacement(span: RedactedSpan, style: RedactionStyle): string {
  switch (style) {
    case "labels":
      return `[${span.category}]`;
    case "bars":
      return "█".repeat(Math.max(3, Math.min(12, [...span.original].length)));
    case "initials":
      if (span.category !== "name") return `[${span.category}]`;
      return span.original.split(" ").filter(Boolean).map((p) => `${[...p][0]}.`).join(" ");
  }
}

/** Words with each hidden span collapsed into one replacement word. */
export function apply(words: Word[], spans: RedactedSpan[], style: RedactionStyle): Word[] {
  if (!spans.some((s) => !s.revealed)) return words;
  const out: Word[] = [];
  let current: RedactedSpan | undefined;
  for (const word of words) {
    const span = spanFor(word, spans);
    if (span) {
      // Keep the punctuation that followed the hidden words.
      const tail = /[.,;:!?]*$/.exec(word.text)![0];
      const last = out.at(-1);
      if (span === current && last) {
        last.end = word.end;
        last.text = replacement(span, style) + tail;
      } else {
        out.push({ text: replacement(span, style) + tail, start: word.start, end: word.end, speaker: word.speaker, isFiller: false, edited: true });
      }
      current = span;
    } else {
      out.push(word);
      current = undefined;
    }
  }
  return out;
}

/** The text the model reads for a run of words, and each word's character range `[lo, hi)` in it. */
export function textOf(words: Word[]): { text: string; ranges: [number, number][] } {
  let text = "";
  let length = 0;
  let last: string | undefined;
  const ranges: [number, number][] = [];
  for (const word of words) {
    if (!word.text) continue;
    const chars = [...word.text];
    if (last != null && !(isUnspaced(last) && isUnspaced(chars[0]))) {
      text += " ";
      length += 1;
    }
    ranges.push([length, length + chars.length]);
    text += word.text;
    length += chars.length;
    last = chars.at(-1);
  }
  return { text, ranges };
}

/** Turns a character range found in `textOf` back into a time span over the words it covers. */
export function spanOver(words: Word[], ranges: [number, number][], from: number, to: number, category: string, original: string): RedactedSpan | undefined {
  const hit = ranges.map((r, i) => (r[0] < to && from < r[1] ? i : -1)).filter((i) => i >= 0);
  if (hit.length === 0) return undefined;
  return { start: words[hit[0]].start, end: words[hit.at(-1)!].end, category, original, revealed: false };
}
