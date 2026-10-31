// The timeline, drawn on a canvas: overview (when zoomed), marks, waveform, one lane per speaker and a
// ruler, with the playhead and the selection across all of them. Time runs left to right, or top to
// bottom when the timeline is vertical. As the Mac app's TimelineView, in DESIGN.md's terms.
import { markRowCount, markRows } from "../core/layout";
import { paragraphs } from "../core/merge";
import * as Peaks from "../core/peaks";
import { isHatched, speakerColor } from "../core/palettes";
import { nameOf, type Project } from "../core/project";
import * as Timecode from "../core/timecode";
import { isDark, settings } from "../settings";

export interface Range { start: number; end: number }

export interface TimelineEvents {
  seek(t: number): void;
  select(range: Range | null): void;
  /** The visible span changed (zoom). */
  zoomed?(): void;
}

const LABEL = 104;
const ROW = { overview: 26, marks: 18, wave: 110, lane: 22, ruler: 20 };
const BAR = 3, GAP = 2;
const SNAP = 8;

export class Timeline {
  readonly canvas: HTMLCanvasElement;
  project!: Project;
  peaks?: Float32Array;
  time = 0;
  selection: Range | null = null;
  pendingMark: number | null = null;
  /** Seconds in view; the whole file while `all` is set. */
  span = 0;
  all = true;
  /** Start of the view. */
  t0 = 0;
  vertical = false;
  private paras: ReturnType<typeof paragraphs> = [];
  private drag?: { from: number; moved: boolean; overview: boolean; edge: "start" | "end" | null; playhead: boolean; x: number; y: number };
  private snapTurn: ReturnType<typeof paragraphs>[number] | null = null;

  constructor(private events: TimelineEvents) {
    this.canvas = document.createElement("canvas");
    this.canvas.className = "timeline";
    this.canvas.tabIndex = 0;
    this.canvas.setAttribute("role", "slider");
    this.canvas.setAttribute("aria-label", "Timeline. Click to jump, drag to select.");
    this.canvas.addEventListener("pointerdown", (e) => this.down(e));
    this.canvas.addEventListener("pointermove", (e) => this.move(e));
    this.canvas.addEventListener("pointerup", (e) => this.up(e));
    this.canvas.addEventListener("wheel", (e) => this.wheel(e), { passive: false });
    this.canvas.addEventListener("pointerleave", () => { if (!this.drag) this.setSnap(null); });
    new ResizeObserver(() => this.draw()).observe(this.canvas);
  }

  get duration() { return Math.max(0.001, this.project?.duration || 0); }
  get zoomed() { return this.span < this.duration - 0.01; }

  setProject(p: Project) {
    this.project = p;
    this.paras = paragraphs(p.words);
    if (this.all || this.span > this.duration) this.span = this.duration;
    this.layout();
    this.draw();
  }

  zoom(factor: number, around = this.time) {
    const span = Math.min(this.duration, Math.max(5, this.span * factor));
    const anchor = (around - this.t0) / this.span;
    this.span = span;
    this.all = span >= this.duration - 0.01;
    this.events.zoomed?.();
    this.t0 = this.clampStart(around - anchor * span);
    this.draw();
  }

  /** Keeps the playhead in view while playing. */
  follow() {
    if (this.time < this.t0 || this.time > this.t0 + this.span) this.t0 = this.clampStart(this.time - this.span * 0.1);
  }

  private clampStart(t: number) { return Math.max(0, Math.min(this.duration - this.span, t)); }

  private rows() {
    const lanes = this.project?.speakers.length ?? 0;
    const crossAvailable = this.vertical ? 280 : Infinity;
    const fixed = (this.zoomed ? ROW.overview : 0) + ROW.marks * this.markRowsCount() + ROW.wave + ROW.ruler;
    const lane = this.vertical ? Math.max(10, Math.min(ROW.lane, (crossAvailable - fixed - 8) / Math.max(1, lanes))) : ROW.lane;
    const out: { id: string; size: number; label: string; speaker?: number }[] = [];
    if (this.zoomed) out.push({ id: "overview", size: ROW.overview, label: "Overview" });
    out.push({ id: "marks", size: ROW.marks * this.markRowsCount(), label: "Marks" });
    out.push({ id: "wave", size: this.vertical ? 90 : ROW.wave, label: "Waveform" });
    for (const s of this.project?.speakers ?? []) out.push({ id: `lane-${s.id}`, size: lane, label: nameOf(this.project, s.id), speaker: s.id });
    out.push({ id: "ruler", size: ROW.ruler, label: "" });
    return out;
  }

  private markRowsCount() { return Math.min(3, markRowCount(this.project?.marks ?? [], 3)); }

  /** Size of the canvas: the cross axis from the rows, the time axis from the element. */
  layout() {
    const cross = this.rows().reduce((n, r) => n + r.size, 0);
    if (this.vertical) {
      this.canvas.style.width = "100%";
      this.canvas.style.height = "100%";
      this.canvas.style.minHeight = "320px";
    } else {
      this.canvas.style.width = "100%";
      this.canvas.style.height = `${cross}px`;
    }
  }

  // Geometry: `along` is the time axis, `across` the rows.
  private size() {
    const r = this.canvas.getBoundingClientRect();
    return { w: r.width, h: r.height, alongStart: this.vertical ? 24 : LABEL, alongEnd: this.vertical ? r.height - 4 : r.width - 8 };
  }
  private toAlong(t: number) {
    const { alongStart, alongEnd } = this.size();
    return alongStart + ((t - this.t0) / this.span) * (alongEnd - alongStart);
  }
  private toTime(along: number) {
    const { alongStart, alongEnd } = this.size();
    return this.t0 + ((along - alongStart) / (alongEnd - alongStart)) * this.span;
  }
  private rect(ctx: CanvasRenderingContext2D, along: number, across: number, alongSize: number, acrossSize: number, radius = 0) {
    const [x, y, w, h] = this.vertical ? [across, along, acrossSize, alongSize] : [along, across, alongSize, acrossSize];
    ctx.beginPath();
    if (radius > 0 && "roundRect" in ctx) ctx.roundRect(x, y, w, h, Math.min(radius, Math.abs(w) / 2, Math.abs(h) / 2));
    else ctx.rect(x, y, w, h);
  }

  draw() {
    if (!this.project) return;
    const ctx = this.canvas.getContext("2d")!;
    const { w, h } = this.size();
    if (w === 0 || h === 0) return;
    const dpr = devicePixelRatio || 1;
    if (this.canvas.width !== Math.round(w * dpr) || this.canvas.height !== Math.round(h * dpr)) {
      this.canvas.width = Math.round(w * dpr);
      this.canvas.height = Math.round(h * dpr);
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);
    const css = getComputedStyle(document.documentElement);
    const v = (name: string) => css.getPropertyValue(name).trim();
    const dark = isDark(), scheme = settings().scheme;
    const color = (speaker: number) => speakerColor(scheme, this.project.speakers.findIndex((s) => s.id === speaker), dark);
    const { alongStart, alongEnd } = this.size();
    ctx.font = `11px ${v("--sans")}`;
    ctx.textBaseline = "middle";

    let across = this.vertical ? 4 : 0;
    const rows = this.rows();
    for (const row of rows) {
      const mid = across + row.size / 2;
      // Row label: left column, or above the column when vertical.
      if (!this.vertical && row.label) {
        ctx.fillStyle = row.speaker != null ? color(row.speaker) : v("--ink-2");
        ctx.font = `${row.speaker != null ? "600 " : ""}11px ${v("--sans")}`;
        ctx.fillText(ellipsize(ctx, row.label, LABEL - 18), 10, mid);
      } else if (this.vertical && row.speaker != null) {
        // A short name over each lane, so a voice is never told apart by its color alone.
        const short = /^Speaker \d+$/.test(row.label) ? String(row.speaker + 1) : [...row.label][0] ?? "";
        ctx.fillStyle = color(row.speaker);
        ctx.font = `600 10px ${v("--sans")}`;
        ctx.textAlign = "center";
        ctx.fillText(short, mid, 12);
        ctx.textAlign = "start";
      }
      switch (row.id) {
        case "overview": this.drawOverview(ctx, across, row.size, v, color); break;
        case "marks": this.drawMarks(ctx, across, v); break;
        case "wave": this.drawWave(ctx, across, row.size, v, color); break;
        case "ruler": this.drawRuler(ctx, across, row.size, v); break;
        default: this.drawLane(ctx, across, row.size, row.speaker!, v, color);
      }
      across += row.size;
    }
    const tracksStart = rows[0]?.id === "overview" ? (this.vertical ? 4 : 0) + ROW.overview : this.vertical ? 4 : 0;

    // Selection, or the pending mark.
    const sel = this.pendingMark != null ? { start: Math.min(this.pendingMark, this.time), end: Math.max(this.pendingMark, this.time) } : this.selection;
    if (sel) {
      const tint = this.pendingMark != null ? v("--mark") : v("--accent");
      const a = Math.max(alongStart, this.toAlong(sel.start)), b = Math.min(alongEnd, this.toAlong(sel.end));
      if (b > a) {
        ctx.fillStyle = withAlpha(tint, 0.12);
        this.rect(ctx, a, tracksStart, b - a, across - tracksStart);
        ctx.fill();
        ctx.fillStyle = tint;
        for (const edge of [a, b - 2]) { this.rect(ctx, edge, tracksStart, 2, across - tracksStart); ctx.fill(); }
        // Grab handles on both edges, to drag them.
        const mid = tracksStart + (across - tracksStart) / 2;
        for (const edge of [a, b]) { this.rect(ctx, edge - 3, mid - 9, 6, 18, 3); ctx.fill(); }
      }
    }

    // The magnet: the speaker turn the pointer snaps to, in that speaker's colour, with who and when.
    const snap = this.snapTurn;
    if (snap && snap.start >= this.t0 && snap.start <= this.t0 + this.span) {
      const s = this.toAlong(snap.start);
      const c = color(snap.speaker);
      ctx.fillStyle = c;
      this.rect(ctx, s - 1, tracksStart, 2, across - tracksStart);
      ctx.fill();
      const label = `${nameOf(this.project, snap.speaker)} · ${Timecode.short(snap.start)}`;
      ctx.font = `600 10px ${v("--sans")}`;
      const w = ctx.measureText(label).width + 12;
      const marksEnd = tracksStart + ROW.marks * this.markRowsCount();
      const [x, y] = this.vertical
        ? [Math.min(marksEnd + 3, this.size().w - w - 2), s + 4 + 16 > this.size().h ? s - 20 : s + 4]
        : [s + 4 + w > this.size().w ? s - 4 - w : s + 4, marksEnd + 3];
      ctx.beginPath();
      ctx.roundRect(x, y, w, 16, 8);
      ctx.fill();
      ctx.fillStyle = "#fff";
      ctx.fillText(label, x + 6, y + 8.5);
    }

    // Playhead: a 2 px line with a knob on the ruler end.
    const p = this.toAlong(this.time);
    if (p >= alongStart - 1 && p <= alongEnd + 1) {
      ctx.fillStyle = v("--ink");
      this.rect(ctx, p - 1, tracksStart, 2, across - tracksStart);
      ctx.fill();
      ctx.beginPath();
      const [x, y] = this.vertical ? [across - 5, p] : [p, across - 5];
      ctx.arc(x, y, 5, 0, Math.PI * 2);
      ctx.fill();
    }
    this.canvas.setAttribute("aria-valuemin", "0");
    this.canvas.setAttribute("aria-valuemax", String(Math.round(this.duration)));
    this.canvas.setAttribute("aria-valuenow", String(Math.round(this.time)));
    this.canvas.setAttribute("aria-valuetext", `${Timecode.short(this.time)} of ${Timecode.short(this.duration)}`);
  }

  private drawOverview(ctx: CanvasRenderingContext2D, across: number, size: number, v: (n: string) => string, color: (s: number) => string) {
    const { alongStart, alongEnd } = this.size();
    ctx.fillStyle = v("--well");
    this.rect(ctx, alongStart, across + 4, alongEnd - alongStart, size - 8, 4);
    ctx.fill();
    const length = alongEnd - alongStart;
    for (const p of this.paras) {
      ctx.fillStyle = withAlpha(color(p.speaker), 0.55);
      this.rect(ctx, alongStart + (p.start / this.duration) * length, across + 8, Math.max(1, ((p.end - p.start) / this.duration) * length), size - 16, 1);
      ctx.fill();
    }
    ctx.strokeStyle = v("--accent");
    ctx.lineWidth = 1.5;
    this.rect(ctx, alongStart + (this.t0 / this.duration) * length, across + 3, (this.span / this.duration) * length, size - 6, 4);
    ctx.stroke();
  }

  private drawMarks(ctx: CanvasRenderingContext2D, across: number, v: (n: string) => string) {
    const marks = this.project.marks;
    const rows = markRows(marks, 3);
    const { alongStart, alongEnd } = this.size();
    let hidden = 0;
    for (const m of marks) {
      const row = rows.get(m.id);
      if (row == null) { hidden++; continue; }
      const a = Math.max(alongStart, this.toAlong(m.start)), b = Math.min(alongEnd, this.toAlong(m.end));
      if (b <= a) continue;
      const top = across + row * ROW.marks + 1;
      ctx.fillStyle = withAlpha(v("--mark"), 0.18);
      ctx.strokeStyle = v("--mark");
      ctx.lineWidth = 1;
      this.rect(ctx, a, top, Math.max(4, b - a), ROW.marks - 2, 4);
      ctx.fill();
      ctx.stroke();
      if (!this.vertical && b - a > 24) {
        ctx.fillStyle = v("--mark-ink");
        ctx.font = `600 10px ${v("--sans")}`;
        ctx.fillText(ellipsize(ctx, m.name, b - a - 8), a + 5, top + (ROW.marks - 2) / 2);
      }
    }
    if (hidden && !this.vertical) {
      ctx.fillStyle = v("--ink-2");
      ctx.font = `10px ${v("--sans")}`;
      ctx.fillText(`+${hidden} more`, 10, across + ROW.marks * this.markRowsCount() - 7);
    }
  }

  private speakerAt(t: number): number | null {
    let lo = 0, hi = this.paras.length - 1;
    while (lo <= hi) {
      const m = (lo + hi) >> 1, p = this.paras[m];
      if (t < p.start) hi = m - 1;
      else if (t > p.end) lo = m + 1;
      else return p.speaker;
    }
    return null;
  }

  private drawWave(ctx: CanvasRenderingContext2D, across: number, size: number, v: (n: string) => string, color: (s: number) => string) {
    const { alongStart, alongEnd } = this.size();
    const step = BAR + GAP;
    const secondsPerBar = (this.span * step) / (alongEnd - alongStart);
    const centre = across + size / 2;
    const silence = v("--ink-3");
    for (let a = alongStart; a < alongEnd; a += step) {
      const t = this.toTime(a);
      const peak = this.peaks ? Peaks.peakIn(this.peaks, t, t + secondsPerBar) : 0;
      const height = Math.max(2, Peaks.loudness(peak) * (size - 12));
      const speaker = this.speakerAt(t + secondsPerBar / 2);
      ctx.globalAlpha = t + secondsPerBar / 2 <= this.time ? 1 : 0.4;
      ctx.fillStyle = speaker == null ? silence : color(speaker);
      if (speaker == null && peak < 0.02) {
        this.rect(ctx, a, centre - 1, BAR, 2, 1);
      } else {
        this.rect(ctx, a, centre - height / 2, BAR, height, 1.5);
      }
      ctx.fill();
    }
    ctx.globalAlpha = 1;
  }

  private drawLane(ctx: CanvasRenderingContext2D, across: number, size: number, speaker: number, v: (n: string) => string, color: (s: number) => string) {
    const { alongStart, alongEnd } = this.size();
    const index = this.project.speakers.findIndex((s) => s.id === speaker);
    ctx.fillStyle = v("--well");
    this.rect(ctx, alongStart, across + 3, alongEnd - alongStart, size - 6, 3);
    ctx.fill();
    const hatched = isHatched(settings().scheme, index);
    const c = color(speaker);
    for (const p of this.paras) {
      if (p.speaker !== speaker || p.end < this.t0 || p.start > this.t0 + this.span) continue;
      const a = Math.max(alongStart, this.toAlong(p.start)), b = Math.min(alongEnd, this.toAlong(p.end));
      ctx.fillStyle = hatched ? hatch(ctx, c) : c;
      this.rect(ctx, a, across + 4, Math.max(2, b - a), size - 8, 3);
      ctx.fill();
    }
  }

  private drawRuler(ctx: CanvasRenderingContext2D, across: number, size: number, v: (n: string) => string) {
    const { alongStart, alongEnd } = this.size();
    const length = alongEnd - alongStart;
    const steps = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1800, 3600];
    const step = steps.find((s) => (s / this.span) * length >= 70) ?? 3600;
    ctx.fillStyle = v("--ink-2");
    ctx.font = `10px ${v("--mono")}`;
    for (let t = Math.ceil(this.t0 / step) * step; t <= this.t0 + this.span; t += step) {
      const a = this.toAlong(t);
      ctx.fillStyle = v("--line");
      this.rect(ctx, a, across, 1, 5);
      ctx.fill();
      ctx.fillStyle = v("--ink-2");
      const [x, y] = this.vertical ? [across + 6, a] : [a + 3, across + size / 2 + 2];
      ctx.fillText(Timecode.short(t), x, y);
    }
  }

  // Interaction

  private along(e: PointerEvent) {
    const r = this.canvas.getBoundingClientRect();
    return this.vertical ? e.clientY - r.top : e.clientX - r.left;
  }
  private acrossOf(e: PointerEvent) {
    const r = this.canvas.getBoundingClientRect();
    return this.vertical ? e.clientX - r.left - 4 : e.clientY - r.top;
  }

  /** The speaker turn starting within 8 px of `along`, unless Option is held: the magnet. */
  private turnNear(along: number, alt: boolean) {
    if (alt) return null;
    const { alongStart, alongEnd } = this.size();
    const reach = (SNAP / (alongEnd - alongStart)) * this.span;
    const t = this.toTime(along);
    let best: (typeof this.paras)[number] | null = null;
    for (const p of this.paras) if (Math.abs(p.start - t) <= reach && (!best || Math.abs(p.start - t) < Math.abs(best.start - t))) best = p;
    return best;
  }

  private snappedTime(along: number, alt: boolean) {
    const t = this.turnNear(along, alt)?.start ?? this.toTime(along);
    return Math.max(0, Math.min(this.duration, t));
  }

  private setSnap(turn: (typeof this.paras)[number] | null) {
    if (turn === this.snapTurn) return;
    this.snapTurn = turn;
    this.draw();
  }

  /** Which selection edge, if any, is under `along`. */
  private edgeAt(along: number): "start" | "end" | null {
    if (!this.selection) return null;
    if (Math.abs(this.toAlong(this.selection.start) - along) <= 6) return "start";
    if (Math.abs(this.toAlong(this.selection.end) - along) <= 6) return "end";
    return null;
  }

  private onPlayhead(along: number) {
    return Math.abs(this.toAlong(this.time) - along) <= 6;
  }

  private down(e: PointerEvent) {
    if (!this.project || e.button !== 0) return;
    const a = this.along(e);
    if (a < this.size().alongStart) return;
    this.canvas.setPointerCapture(e.pointerId);
    const overview = this.zoomed && this.acrossOf(e) < ROW.overview;
    const edge = overview ? null : this.edgeAt(a);
    const playhead = !overview && !edge && this.onPlayhead(a);
    this.drag = { from: this.snappedTime(a, e.altKey), moved: false, overview, edge, playhead, x: e.clientX, y: e.clientY };
    if (overview) this.moveOverview(e);
  }

  private moveOverview(e: PointerEvent) {
    const { alongStart, alongEnd } = this.size();
    const t = ((this.along(e) - alongStart) / (alongEnd - alongStart)) * this.duration;
    this.t0 = this.clampStart(t - this.span / 2);
    this.draw();
  }

  private move(e: PointerEvent) {
    const a = this.along(e);
    const d = this.drag;
    if (!d) {
      // Hovering: grab cursors over the playhead and the selection's edges, the magnet elsewhere.
      if (a < this.size().alongStart || (this.zoomed && this.acrossOf(e) < ROW.overview)) {
        this.canvas.style.cursor = "default";
        return this.setSnap(null);
      }
      if (this.edgeAt(a) || this.onPlayhead(a)) {
        this.canvas.style.cursor = this.vertical ? "row-resize" : "col-resize";
        return this.setSnap(null);
      }
      const turn = this.turnNear(a, e.altKey);
      this.canvas.style.cursor = turn ? "pointer" : this.vertical ? "vertical-text" : "text";
      return this.setSnap(turn);
    }
    if (d.overview) return this.moveOverview(e);
    if (!d.moved && Math.hypot(e.clientX - d.x, e.clientY - d.y) < 4) return;
    d.moved = true;
    this.setSnap(d.playhead ? null : this.turnNear(a, e.altKey));
    const t = this.snappedTime(a, e.altKey || d.playhead);
    if (d.playhead) {
      this.events.seek(t);
      return;
    }
    if (d.edge && this.selection) {
      const other = d.edge === "start" ? this.selection.end : this.selection.start;
      this.selection = { start: Math.min(t, other), end: Math.max(t, other) };
      d.edge = t <= other ? "start" : "end";
    } else {
      this.selection = { start: Math.min(d.from, t), end: Math.max(d.from, t) };
    }
    this.events.select(this.selection);
    this.draw();
  }

  private up(e: PointerEvent) {
    const d = this.drag;
    this.drag = undefined;
    if (!d || d.overview) return;
    if (!d.moved) {
      this.selection = null;
      this.events.select(null);
      this.events.seek(this.snappedTime(this.along(e), e.altKey));
    }
  }

  /** A swipe or wheel turn along the time axis scrubs the playhead, a point of scroll per point of
   *  waveform, as in the Mac app; a pinch (ctrl + wheel in browsers) zooms. Handled here, so the
   *  browser never takes a sideways swipe for Back or Forward. */
  private wheel(e: WheelEvent) {
    if (!this.project) return;
    if (e.ctrlKey || e.metaKey) {
      e.preventDefault();
      const r = this.canvas.getBoundingClientRect();
      this.zoom(Math.exp(e.deltaY * 0.01), this.toTime(this.vertical ? e.clientY - r.top : e.clientX - r.left));
      return;
    }
    const lines = e.deltaMode === WheelEvent.DOM_DELTA_LINE ? 16 : e.deltaMode === WheelEvent.DOM_DELTA_PAGE ? 400 : 1;
    const along = (this.vertical ? e.deltaY : e.deltaX) * lines, across = (this.vertical ? e.deltaX : e.deltaY) * lines;
    // A trackpad reports small, fractional steps; a mouse wheel whole notches of about 100.
    const precise = e.deltaMode === WheelEvent.DOM_DELTA_PIXEL && Math.abs(e.deltaY) < 50 && Math.abs(e.deltaX) < 50;
    let delta: number;
    if (Math.abs(along) >= Math.abs(across)) delta = along;
    else if (!precise) delta = across * 0.6;
    else return; // a trackpad scroll across the time axis scrolls the speaker lanes
    e.preventDefault();
    if (delta === 0) return;
    const { alongStart, alongEnd } = this.size();
    this.events.seek(Math.max(0, Math.min(this.duration, this.time + (delta / (alongEnd - alongStart)) * this.span)));
  }
}

function ellipsize(ctx: CanvasRenderingContext2D, text: string, width: number) {
  if (ctx.measureText(text).width <= width) return text;
  let s = text;
  while (s.length > 1 && ctx.measureText(s + "…").width > width) s = s.slice(0, -1);
  return s + "…";
}

function withAlpha(color: string, alpha: number) {
  if (color.startsWith("#") && color.length === 7) return color + Math.round(alpha * 255).toString(16).padStart(2, "0");
  return color;
}

const hatches = new Map<string, CanvasPattern>();
function hatch(ctx: CanvasRenderingContext2D, color: string): CanvasPattern | string {
  const key = color;
  if (hatches.has(key)) return hatches.get(key)!;
  const tile = document.createElement("canvas");
  tile.width = tile.height = 6;
  const t = tile.getContext("2d")!;
  t.fillStyle = withAlpha(color, 0.35);
  t.fillRect(0, 0, 6, 6);
  t.strokeStyle = color;
  t.lineWidth = 2;
  t.beginPath();
  t.moveTo(0, 6);
  t.lineTo(6, 0);
  t.moveTo(-1, 1);
  t.lineTo(1, -1);
  t.moveTo(5, 7);
  t.lineTo(7, 5);
  t.stroke();
  const pattern = ctx.createPattern(tile, "repeat");
  if (!pattern) return color;
  hatches.set(key, pattern);
  return pattern;
}
