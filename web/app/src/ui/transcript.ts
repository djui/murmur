// The transcript: one row per paragraph, the speaker and time in the gutter, the words to the right.
// While playing, the current word is lit and the words still to come are secondary.
import { speakerColor } from "../core/palettes";
import { paragraphs } from "../core/merge";
import { nameOf, type Paragraph, type Project, type Word } from "../core/project";
import { apply } from "../core/redactor";
import * as Timecode from "../core/timecode";
import { isDark, settings } from "../settings";
import { h } from "./dom";

export interface TranscriptEvents {
  seek(t: number): void;
  /** Words `[lower, upper)` were selected; `at` is where to show a menu. */
  selectWords(lower: number, upper: number, at: { x: number; y: number }): void;
  speakerMenu(paragraph: Paragraph, at: HTMLElement): void;
  editParagraph(paragraph: Paragraph, text: string): void;
}

export class Transcript {
  readonly el = h("div", { class: "transcript", role: "list", "aria-label": "Transcript" });
  private project!: Project;
  private paras: Paragraph[] = [];
  private rows: HTMLElement[] = [];
  private wordEls: (HTMLElement | undefined)[] = [];
  private current = -1;
  private currentPara = -1;
  editing = false;
  query = "";

  constructor(private events: TranscriptEvents) {
    this.el.addEventListener("click", (e) => {
      if (this.editing) return;
      const w = (e.target as HTMLElement).closest<HTMLElement>("[data-i]");
      const sel = getSelection();
      if (w && (!sel || sel.isCollapsed)) this.events.seek(this.project.words[Number(w.dataset.i)].start);
    });
    this.el.addEventListener("mouseup", (e) => {
      if (this.editing) return;
      const range = this.selectedWords();
      if (range) this.events.selectWords(range[0], range[1], { x: e.clientX, y: e.clientY });
    });
    this.el.addEventListener("contextmenu", (e) => {
      if (this.editing) return;
      let range = this.selectedWords();
      if (!range) {
        const w = (e.target as HTMLElement).closest<HTMLElement>("[data-i]");
        if (!w) return;
        const i = Number(w.dataset.i);
        range = [i, i + 1];
      }
      e.preventDefault();
      this.events.selectWords(range[0], range[1], { x: e.clientX, y: e.clientY });
    });
  }

  /** Word indices `[lower, upper)` the text selection touches, if it touches any. */
  private selectedWords(): [number, number] | null {
    const sel = getSelection();
    if (!sel || sel.isCollapsed || !this.el.contains(sel.anchorNode)) return null;
    const indices = [...this.el.querySelectorAll<HTMLElement>("[data-i]")]
      .filter((el) => sel.containsNode(el, true))
      .map((el) => Number(el.dataset.i));
    if (indices.length === 0) return null;
    const last = this.wordEls.length ? Math.max(...indices) : 0;
    // A redacted span stands for several words; take them all.
    let upper = last + 1;
    const lastEl = this.el.querySelector<HTMLElement>(`[data-i="${last}"]`);
    if (lastEl?.dataset.upto) upper = Number(lastEl.dataset.upto);
    return [Math.min(...indices), upper];
  }

  render(project: Project) {
    this.project = project;
    this.paras = paragraphs(project.words);
    const dark = isDark(), scheme = settings().scheme;
    const redact = project.settings.redact === true;
    const q = this.query.toLowerCase();
    this.wordEls = new Array(project.words.length);
    this.rows = this.paras.map((p) => {
      const index = project.speakers.findIndex((s) => s.id === p.speaker);
      const words = project.words.slice(p.lower, p.upper);
      const shown: (Word & { i: number; upto?: number; hidden?: boolean })[] = redact
        ? redactedWithIndex(words, p.lower, project, settings().redactionStyle)
        : words.map((w, k) => ({ ...w, i: p.lower + k }));
      const wordsEl = h("div", { class: "words", lang: project.language },
        shown.flatMap((w, k) => {
          const span = h("span", {
            class: `w${w.isFiller ? " filler" : ""}${w.hidden ? " redacted" : ""}${q && w.text.toLowerCase().includes(q) ? " hit" : ""}`,
            dataset: { i: String(w.i), ...(w.upto ? { upto: String(w.upto) } : {}) },
          }, w.text);
          for (let i = w.i; i < (w.upto ?? w.i + 1); i++) this.wordEls[i] = span;
          return k === 0 ? [span] : [" ", span];
        }));
      const commit = () => {
        if (!this.editing || wordsEl.contentEditable !== "true") return;
        const text = wordsEl.textContent ?? "";
        if (text.trim() !== words.map((w) => w.text).join(" ").trim()) this.events.editParagraph(p, text);
      };
      wordsEl.addEventListener("blur", commit);
      wordsEl.addEventListener("keydown", (e) => {
        if (e.key === "Enter" && !e.shiftKey) {
          e.preventDefault();
          wordsEl.blur();
        }
        if (e.key === "Escape") {
          wordsEl.textContent = words.map((w) => w.text).join(" ");
          wordsEl.blur();
        }
        e.stopPropagation();
      });
      if (this.editing && !redact) {
        wordsEl.contentEditable = "true";
        wordsEl.spellcheck = true;
        wordsEl.textContent = words.map((w) => w.text).join(" ");
      }
      const who = h("button", {
        class: "who", style: { color: speakerColor(scheme, index, dark), background: "none", border: "0", padding: "0", textAlign: "left" },
        title: "Rename or reassign", on: { click: (e: MouseEvent) => this.events.speakerMenu(p, e.currentTarget as HTMLElement) },
      }, nameOf(project, p.speaker));
      return h("div", { class: "para", role: "listitem" },
        h("div", {}, who, h("div", { class: "when", on: { click: () => this.events.seek(p.start) } }, Timecode.short(p.start))),
        wordsEl);
    });
    this.el.replaceChildren(...(this.rows.length ? this.rows : [h("div", { class: "empty" }, project.status === "ready" ? "No speech was found in this recording." : "")]));
    this.current = -1;
    this.currentPara = -1;
  }

  /** Lights the word at `t`; keeps it in view while following. */
  update(t: number, playing: boolean, follow: boolean) {
    const words = this.project?.words;
    if (!words?.length) return;
    let lo = 0, hi = words.length - 1, found = -1;
    while (lo <= hi) {
      const m = (lo + hi) >> 1;
      if (words[m].start <= t) { found = m; lo = m + 1; } else hi = m - 1;
    }
    if (found >= 0 && t > words[found].end + 0.6) found = -1;
    if (found === this.current) return;
    this.wordEls[this.current]?.classList.remove("now");
    this.current = found;
    const para = found >= 0 ? this.paras.findIndex((p) => found >= p.lower && found < p.upper) : -1;
    if (para !== this.currentPara) {
      const old = this.rows[this.currentPara];
      old?.classList.remove("playing");
      old?.querySelectorAll(".future").forEach((e) => e.classList.remove("future"));
      this.currentPara = para;
      this.rows[para]?.classList.add("playing");
    }
    if (found < 0) return;
    const el = this.wordEls[found];
    el?.classList.add("now");
    if (playing && para >= 0) {
      const p = this.paras[para];
      for (let i = p.lower; i < p.upper; i++) this.wordEls[i]?.classList.toggle("future", i > found);
    }
    if (follow && el && !this.editing) {
      const r = el.getBoundingClientRect(), box = this.el.getBoundingClientRect();
      if (r.top < box.top + 40 || r.bottom > box.bottom - 40) el.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    }
  }

  /** The paragraph after (or before) the one at `t`, for the next/previous line keys. */
  paragraphStart(t: number, direction: 1 | -1): number | undefined {
    if (direction === 1) return this.paras.find((p) => p.start > t + 0.05)?.start;
    const before = this.paras.filter((p) => p.start < t - 0.8);
    return before.at(-1)?.start ?? 0;
  }

  /** The next search hit after the current word. */
  nextHit(): number | undefined {
    const q = this.query.toLowerCase();
    if (!q) return undefined;
    const words = this.project.words;
    for (let k = 1; k <= words.length; k++) {
      const i = (Math.max(0, this.current) + k) % words.length;
      if (words[i].text.toLowerCase().includes(q)) return words[i].start;
    }
    return undefined;
  }
}

/** Redacted words collapse into one, which keeps the index of the first and where the span ends. */
function redactedWithIndex(words: Word[], offset: number, project: Project, style: Parameters<typeof apply>[2]) {
  const out = apply(words, project.redactions ?? [], style);
  const result: (Word & { i: number; upto?: number; hidden?: boolean })[] = [];
  let k = 0;
  for (const w of out) {
    const i = offset + k;
    if (w.edited && w !== words[k]) {
      // Count the source words this replacement covers.
      let n = 0;
      while (k + n < words.length && words[k + n].start < w.end - 1e-6) n++;
      result.push({ ...w, i, upto: offset + k + Math.max(1, n), hidden: true });
      k += Math.max(1, n);
    } else {
      result.push({ ...w, i });
      k++;
    }
  }
  return result;
}
