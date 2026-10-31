// The TypeScript core against MurmurCore: every case in Fixtures/core.json, which the Swift test
// FixtureTests writes and checks, must come out the same here.
import { readFileSync } from "node:fs";
import { describe, expect, test } from "vitest";
import * as Editing from "../core/editing";
import { render, type TextFormat } from "../core/formats";
import { markRowCount, markRows } from "../core/layout";
import * as Merge from "../core/merge";
import { palettes } from "../core/palettes";
import * as Peaks from "../core/peaks";
import { decodeProject, encodeProject, type Project, type Word } from "../core/project";
import { apply, textOf, type RedactionStyle } from "../core/redactor";
import { actions, ShortcutMap } from "../core/shortcuts";
import * as Timecode from "../core/timecode";

const fixtures = JSON.parse(readFileSync(new URL("../../../../Packages/MurmurCore/Tests/Fixtures/core.json", import.meta.url), "utf8"));
const words: Word[] = fixtures.words;
const close = (a: ArrayLike<number>, b: ArrayLike<number>) => {
  expect(a.length).toBe(b.length);
  for (let i = 0; i < a.length; i++) expect(a[i]).toBeCloseTo(b[i], 6);
};

describe("matches MurmurCore", () => {
  test("timecode", () => {
    for (const c of fixtures.timecode) {
      expect([Timecode.short(c.t), Timecode.precise(c.t), Timecode.srt(c.t), Timecode.vtt(c.t)]).toEqual([c.short, c.precise, c.srt, c.vtt]);
    }
  });

  test("merge", () => {
    expect(Merge.assign(words.map((w) => ({ ...w, speaker: 0 })), fixtures.assign.turns)).toEqual(fixtures.assign.result);
    expect(Merge.paragraphs(words)).toEqual(fixtures.paragraphs);
    for (const c of fixtures.join) expect(Merge.join(c.in)).toBe(c.out);
    for (const c of fixtures.normalized) expect(Merge.normalized(c.in)).toBe(c.out);
    for (const c of fixtures.indices) expect(Merge.indices(words, c.from, c.to)).toEqual([c.lower, c.upper]);
    expect(Merge.monotonic(fixtures.monotonic.in)).toEqual(fixtures.monotonic.out);
  });

  test("editing", () => {
    for (const c of fixtures.retime) expect(Editing.retime(words.slice(10, 13), c.text, 0)).toEqual(c.out);
    const r = Editing.replace(words, 10, 13, "Sure thing, will do.");
    expect([r.words, r.lower, r.upper]).toEqual([fixtures.replace.words, fixtures.replace.lower, fixtures.replace.upper]);
    for (const c of fixtures.touching) expect(Editing.wordsTouching(words, c.lower, c.upper)).toEqual(c.range);
  });

  test("redaction", () => {
    const spans = fixtures.project.redactions;
    for (const c of fixtures.redact) expect(apply(words, spans, c.style as RedactionStyle)).toEqual(c.out);
    expect(textOf(words)).toEqual({ text: fixtures.redactText.text, ranges: fixtures.redactText.ranges });
  });

  test("mark rows", () => {
    const marks = fixtures.markRows.marks.map((m: { id: string; start: number; end: number }) => ({ ...m, name: "" }));
    const rows = markRows(marks, 2);
    expect(marks.map((m: { id: string }) => rows.get(m.id) ?? null)).toEqual(fixtures.markRows.rows);
    expect(markRowCount(marks, 2)).toBe(fixtures.markRows.rowCount);
  });

  test("peaks", () => {
    const p = fixtures.peaks;
    const computed = Peaks.compute(Float32Array.from(p.samples), 1000, 50);
    close(computed, p.compute);
    close(Peaks.normalize(computed), p.normalize);
    expect(Peaks.peakIn(computed, 0.1, 0.35, 50)).toBeCloseTo(p.peak, 6);
    close([0, 0.001, 0.05, 0.5, 1].map((v) => Peaks.loudness(v)), p.loudness);
  });

  test("render", () => {
    const base = decodeProject({ ...fixtures.project, settings: { ...fixtures.project.settings, redact: false } });
    const redacted = decodeProject(fixtures.project);
    const sections = [{ name: "Greeting", start: 0, end: 1.5 }, { name: "Reply", start: 1.5, end: 8 }];
    const cases: Record<string, [Project, typeof sections | undefined, object]> = {
      all: [base, undefined, {}],
      fillers: [base, undefined, { hideFillers: false }],
      noNames: [base, undefined, { speakerNames: false }],
      sections: [base, sections, { relativeTimes: true }],
      redacted: [redacted, undefined, { redactionStyle: "initials" }],
    };
    for (const c of fixtures.render) {
      const [project, parts, options] = cases[c.case];
      expect(render(project, c.format as TextFormat, parts, options), `${c.format} ${c.case}`).toBe(c.out);
    }
  });

  test("project.json round trip", () => {
    expect(JSON.parse(encodeProject(decodeProject(fixtures.project)))).toEqual(fixtures.project);
  });

  test("shortcuts", () => {
    expect(actions.map((a) => ({ [a.id]: a.defaults }))).toEqual(fixtures.shortcuts.defaults);
    const map = new ShortcutMap();
    expect(map.add("m", "playPause")).toEqual({ kind: "moved", from: "markSection" });
    expect(map.add("?", "back")).toEqual({ kind: "reserved" });
    expect(map.stored).toEqual(fixtures.shortcuts.afterAddingMToPlay);
  });

  test("palettes", () => {
    expect(palettes).toEqual(fixtures.palettes);
  });
});
