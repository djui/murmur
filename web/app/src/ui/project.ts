// The project window: controls, timeline, transcript and the inspector (video, language, speakers,
// marks, redaction). As the Mac app's MainView, laid out per DESIGN.md.
import { decode, RATE } from "../audio";
import * as Editing from "../core/editing";
import { indices, paragraphs } from "../core/merge";
import { speakerColor } from "../core/palettes";
import * as Peaks from "../core/peaks";
import { displayTitle, mark as makeMark, nameOf, speakerName, type Paragraph, type Project } from "../core/project";
import { keyName, type ShortcutAction } from "../core/shortcuts";
import * as Timecode from "../core/timecode";
import { openLibrary } from "../main";
import { isDownloaded, models, persist, stopAll } from "../models";
import { Cancelled, findRedactions, languageName, run, steps as pipelineSteps, type Step } from "../pipeline";
import { isDark, onChange, settings, shortcutMap, update } from "../settings";
import { fileFromHandle, loadHandle, loadPeaks, loadProject, saveHandle, savePeaks, saveProject } from "../store";
import { button, confirm, dialog, h, icon, megabytes, menu, toast, type MenuItem } from "./dom";
import { copyMenu, showExport, snapToWords } from "./export";
import { pickFile } from "./library";
import { pendingFiles } from "./session";
import { showSettings, showShortcuts } from "./settings";
import { Timeline, type Range } from "./timeline";
import { Transcript } from "./transcript";

const RATES = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

export async function showProject(root: HTMLElement, id: string): Promise<() => void> {
  const stored = await loadProject(id);
  if (!stored) {
    openLibrary();
    return () => {};
  }
  let project: Project = stored;
  let file: File | undefined;
  let media: HTMLMediaElement | undefined;
  let mediaUrl: string | undefined;
  let selection: Range | null = null;
  let processing: AbortController | undefined;
  const undo: Project[] = [];
  const redo: Project[] = [];
  let disposed = false;
  let hasHandle = false;

  // Elements
  const title = h("h1", {}, displayTitle(project));
  const subtitle = h("span", {});
  const clock = h("span", { class: "clock", "aria-live": "off" });
  const playButton = h("button", { class: "play", "aria-label": "Play", on: { click: () => togglePlay() } }, icon("play"));
  const rateButton = button("1×", () => menu(RATES.map((r) => ({ label: `${r}×`, checked: (media?.playbackRate ?? 1) === r, action: () => setRate(r) })), rateButton), { title: "Playback speed ([ and ])" });
  const markButton = h("button", { class: "btn", title: "Mark section (M)", on: { click: () => doAction("markSection") } }, icon("mark"), "Mark section ", h("span", { class: "keycap" }, "M"));
  const zoomLabel = h("span", { class: "label mono" });
  const timeline = new Timeline({ seek: (t) => seek(t), select: (r) => { selection = r; renderControls(); } });
  const transcript = new Transcript({
    seek: (t) => seek(t),
    selectWords: (lo, hi, at) => wordsMenu(lo, hi, at),
    give: (lo, hi, to) => change((x) => (to === "new" ? Editing.toNewSpeaker(x, lo, hi) : { ...x, words: Editing.reassign(x.words, lo, hi, to) })),
    speakerMenu: (p, at) => speakerMenu(p, at),
    editParagraph: (p, text) => change((x) => ({ ...x, words: Editing.replace(x.words, p.lower, p.upper, text).words })),
  });
  const status = h("div", {});
  const inspector = h("aside", { class: "inspector", "aria-label": "Inspector" });
  const search = h("input", { type: "search", placeholder: "Find in transcript", "aria-label": "Find in transcript", style: { width: "180px" },
    on: { input: () => { transcript.query = search.value.trim(); transcript.render(project); },
          keydown: (e: KeyboardEvent) => { if (e.key === "Enter") { const t = transcript.nextHit(); if (t != null) seek(t); } e.stopPropagation(); } } });
  const editToggle = button("Edit", () => {
    transcript.editing = !transcript.editing;
    editToggle.classList.toggle("on", transcript.editing);
    editToggle.setAttribute("aria-pressed", String(transcript.editing));
    if (transcript.editing) media?.pause();
    transcript.render(project);
  }, { icon: "edit", title: "Fix words in place" });
  const redactToggle = button("Redact", () => toggleRedaction(), { title: "Hide names, numbers, addresses and IDs" });
  const main = h("div", { class: "main" });
  const timelineWrap = h("div", { class: "timeline-wrap" }, h("div", { class: "timeline-scroll" }, timeline.canvas));

  // Saving and undo

  let saveTimer: number | undefined;
  const save = () => {
    clearTimeout(saveTimer);
    saveTimer = window.setTimeout(() => saveProject(project), 300);
  };

  function change(f: (p: Project) => Project) {
    undo.push(structuredClone(project));
    if (undo.length > 100) undo.shift();
    redo.length = 0;
    project = f(project);
    save();
    renderAll();
  }

  function undoRedo(back: boolean) {
    const from = back ? undo : redo, to = back ? redo : undo;
    const next = from.pop();
    if (!next) return;
    to.push(structuredClone(project));
    project = next;
    save();
    renderAll();
  }

  // Media

  async function attach(f: File) {
    file = f;
    if (mediaUrl) URL.revokeObjectURL(mediaUrl);
    mediaUrl = URL.createObjectURL(f);
    media?.pause();
    media = h(project.media?.hasVideo ? "video" : "audio", { src: mediaUrl, preload: "auto", playsInline: true }) as HTMLMediaElement;
    media.addEventListener("play", tick);
    media.addEventListener("play", renderControls);
    media.addEventListener("pause", renderControls);
    media.addEventListener("ratechange", renderControls);
    media.addEventListener("loadedmetadata", () => {
      if (!project.duration && media) { project = { ...project, duration: media.duration }; save(); }
      renderAll();
    });
    if (!timeline.peaks) {
      const peaks = await loadPeaks(project.id);
      if (peaks) timeline.peaks = peaks;
      else if (project.status === "ready") decode(f).then((s) => {
        timeline.peaks = Peaks.normalize(Peaks.compute(s, RATE));
        savePeaks(project.id, timeline.peaks);
        timeline.draw();
      }).catch(() => {});
    }
    renderAll();
  }

  /** Finds the media again: the file from the library, a kept handle, or nothing (Locate). */
  async function findMedia(ask: boolean) {
    const pending = pendingFiles.get(id);
    if (pending) return attach(pending.file);
    const handle = await loadHandle(id).catch(() => undefined);
    hasHandle = !!handle;
    const f = handle ? await fileFromHandle(handle, ask) : undefined;
    if (f) await attach(f);
    else renderStatus();
  }

  async function locate() {
    const picked = await pickFile();
    if (!picked) return;
    const expected = project.media;
    if (expected && (picked.file.name !== expected.path || (expected.fileSize && picked.file.size !== expected.fileSize))) {
      if (!(await confirm("Use this file?", `This project was made from “${expected.path}”${expected.fileSize ? ` (${megabytes(expected.fileSize)})` : ""}. The file you chose is “${picked.file.name}” (${megabytes(picked.file.size)}).`, "Use it"))) return;
    }
    if (picked.handle) await saveHandle(id, picked.handle).catch(() => {});
    await attach(picked.file);
  }

  // Playback

  const now = () => media?.currentTime ?? timeline.time;
  function seek(t: number) {
    const clamped = Math.max(0, Math.min(project.duration || t, t));
    if (media) media.currentTime = clamped;
    timeline.time = clamped;
    timeline.follow();
    timeline.draw();
    transcript.update(clamped, !!media && !media.paused, true);
    renderClock();
  }
  function togglePlay() {
    if (!media) return toast(file ? "Loading…" : "Locate the media file to play it.");
    if (media.paused) media.play().catch(() => {});
    else media.pause();
  }
  function setRate(r: number) {
    if (media) media.playbackRate = r;
    renderControls();
  }
  function tick() {
    if (disposed || !media) return;
    timeline.time = media.currentTime;
    if (!media.paused) timeline.follow();
    timeline.draw();
    transcript.update(media.currentTime, !media.paused, !media.paused);
    renderClock();
    if (!media.paused) requestAnimationFrame(tick);
  }

  // Marks

  let pendingMark: number | null = null;
  function markSection() {
    if (selection) {
      addMark(snapToWords(project, selection));
      selection = null;
      timeline.selection = null;
    } else if (pendingMark == null) {
      pendingMark = now();
      timeline.pendingMark = pendingMark;
      toast("Mark started. Press M again at its end, Esc to cancel.");
    } else {
      const start = Math.min(pendingMark, now()), end = Math.max(pendingMark, now());
      pendingMark = null;
      timeline.pendingMark = null;
      if (end - start > 0.2) addMark(snapToWords(project, { start, end }));
    }
    timeline.draw();
  }
  function addMark(r: Range) {
    const [lo] = indices(project.words, r.start, r.end);
    const who = project.words[lo] ? nameOf(project, project.words[lo].speaker) : "Mark";
    change((p) => ({ ...p, marks: [...p.marks, makeMark(`${who} at ${Timecode.short(r.start)}`, r.start, r.end)].sort((a, b) => a.start - b.start) }));
    toast("Marked");
  }

  // Speakers and words

  function speakerItems(lo: number, hi: number, current?: number): MenuItem[] {
    return [
      ...project.speakers.filter((s) => s.id !== current).map((s) => ({ label: speakerName(s), action: () => change((p) => ({ ...p, words: Editing.reassign(p.words, lo, hi, s.id) })) })),
      { label: "New speaker", action: () => change((p) => Editing.toNewSpeaker(p, lo, hi)) },
    ];
  }
  function wordsMenu(lo: number, hi: number, at: { x: number; y: number }) {
    const first = project.words[lo], last = project.words[hi - 1];
    if (!first || !last) return;
    const paras = paragraphs(project.words);
    const pi = paras.findIndex((p) => lo >= p.lower && lo < p.upper);
    const p = paras[pi];
    const suggested = p ? Editing.suggestedSpeakers(lo, hi, p, paras[pi - 1]?.speaker, paras[pi + 1]?.speaker) : [];
    menu([
      { label: `${hi - lo} word${hi - lo === 1 ? "" : "s"} · ${Timecode.short(first.start)}`, heading: true },
      ...suggested.map((sid) => ({ label: `Give to ${nameOf(project, sid)}`, action: () => change((x) => ({ ...x, words: Editing.reassign(x.words, lo, hi, sid) })) })),
      { label: "Give to…", heading: true },
      ...speakerItems(lo, hi, p?.speaker),
      { separator: true, label: "" },
      { label: "Mark these words", action: () => addMark({ start: first.start, end: last.end }) },
      { label: "Play from here", action: () => { seek(first.start); media?.play(); } },
    ], at);
  }
  function speakerMenu(p: Paragraph, at: HTMLElement) {
    const paras = paragraphs(project.words);
    const i = paras.findIndex((x) => x.lower === p.lower);
    const joins = Editing.suggestedSpeakers(p.lower, p.upper, p, paras[i - 1]?.speaker, paras[i + 1]?.speaker);
    menu([
      ...joins.map((sid) => ({
        label: `${sid === paras[i - 1]?.speaker ? "↑" : "↓"} Join ${nameOf(project, sid)} on the line ${sid === paras[i - 1]?.speaker ? "before" : "after"}`,
        action: () => change((x) => ({ ...x, words: Editing.reassign(x.words, p.lower, p.upper, sid) })),
      })),
      ...(joins.length ? [{ separator: true, label: "" }] : []),
      { label: "Rename…", action: () => renameSpeaker(p.speaker) },
      { label: "Give this paragraph to", heading: true },
      ...speakerItems(p.lower, p.upper, p.speaker),
    ], at);
  }
  async function renameSpeaker(sid: number) {
    const s = project.speakers.find((x) => x.id === sid);
    if (!s) return;
    const input = h("input", { type: "text", value: s.name, placeholder: speakerName(s), "aria-label": "Name" });
    const name = await dialog<string>("Rename speaker", (done) => {
      input.addEventListener("keydown", (e) => e.key === "Enter" && done(input.value));
      setTimeout(() => input.select(), 0);
      return { body: [input], foot: [button("Cancel", () => done()), button("Rename", () => done(input.value), { class: "primary" })] };
    });
    if (name != null) change((x) => ({ ...x, speakers: x.speakers.map((y) => (y.id === sid ? { ...y, name: name.trim() } : y)) }));
  }

  // Redaction

  async function toggleRedaction() {
    if (project.settings.redact) return change((p) => ({ ...p, settings: { ...p.settings, redact: false } }));
    if (!project.redactions) {
      if (!project.words.length) return;
      redactToggle.disabled = true;
      toast((await isDownloaded("redact")) ? "Finding personal details…" : "Downloading Redact and finding personal details…");
      try {
        const spans = await findRedactions(project);
        change((p) => ({ ...p, redactions: spans, settings: { ...p.settings, redact: true } }));
        toast(spans.length ? `${spans.length} details hidden` : "No personal details found");
      } catch (error) {
        toast(`Redaction failed: ${(error as Error).message}`);
      } finally {
        redactToggle.disabled = false;
      }
      return;
    }
    change((p) => ({ ...p, settings: { ...p.settings, redact: true } }));
  }

  // Processing

  async function process(f: File) {
    const missing: typeof models = [];
    for (const m of models.filter((x) => x.required)) if (!(await isDownloaded(m.id))) missing.push(m);
    let enhance = project.settings.enhance;
    if (missing.length || pendingFiles.get(id)?.process) {
      const ok = await dialog<boolean>(missing.length ? "Download the speech models" : "Transcribe", (done) => ({
        body: [
          missing.length ? h("p", { style: { margin: 0 } }, `Murmur needs ${missing.map((m) => m.engine).join(", ")} to transcribe. They download once from Hugging Face (about 340 MB in all) and stay in this browser; your recording is not sent anywhere.`) : null,
          h("label", { class: "option" }, h("input", { type: "checkbox", checked: enhance, on: { change: (e: Event) => (enhance = (e.target as HTMLInputElement).checked) } }),
            "Enhance the audio first (Clear): denoise and level speech before transcribing"),
        ],
        foot: [button("Cancel", () => done(false)), button(missing.length ? "Download and transcribe" : "Transcribe", () => done(true), { class: "primary" })],
      }));
      pendingFiles.delete(id);
      if (!ok) return renderStatus();
    }
    project = { ...project, settings: { ...project.settings, enhance }, failure: undefined };
    const list = pipelineSteps(enhance);
    processing = new AbortController();
    renderProcessing(list);
    try {
      const result = await run(project, f, {
        step: (sid, c) => {
          Object.assign(list.find((s) => s.id === sid) ?? {}, c);
          renderProcessing(list);
        },
        peaks: (peaks, duration) => {
          timeline.peaks = peaks;
          savePeaks(project.id, peaks);
          project = { ...project, duration };
          renderAll();
        },
        progress: (p) => {
          project = p;
          renderAll(false);
          renderProcessing(list);
        },
        unsupportedLanguage: (lang, confidence) => dialog<boolean>("Transcribe anyway?", (done) => ({
          body: [h("p", { style: { margin: 0 } }, `This sounds like ${languageName(lang)} (${Math.round(confidence * 100)}%), which Voz can't transcribe. Transcribed anyway, the words will be wrong. Voz knows ${[...new Set(["en", "de", "fr", "es", "it", "nl", "pt", "pl"])].map(languageName).join(", ")} and 17 more European languages.`)],
          foot: [button("Cancel", () => done(false)), button("Transcribe anyway", () => done(true), { class: "primary" })],
        })).then(Boolean),
      }, processing.signal);
      project = result;
      await saveProject(project);
      persist();
      processing = undefined;
      renderAll();
      toast("Done");
    } catch (error) {
      stopAll();
      processing = undefined;
      const cancelled = error instanceof Cancelled || (error as Error).message === "Cancelled";
      project = { ...project, status: "failed", failure: cancelled ? "Stopped before it finished." : (error as Error).message };
      await saveProject(project);
      renderAll();
    }
  }

  function renderProcessing(list: Step[]) {
    status.replaceChildren(h("div", { class: "card processing", role: "status", "aria-live": "polite" },
      h("div", { style: { display: "flex", justifyContent: "space-between", alignItems: "center" } },
        h("strong", {}, "Transcribing in this browser"),
        button("Stop", () => { processing?.abort(); stopAll(); })),
      h("div", { class: "steps" }, list.map((s) => h("div", { class: `step ${s.state}` },
        h("span", { class: "state", "aria-hidden": "true" }),
        h("span", {}, s.title, " ", h("span", { class: "tertiary" }, s.detail)),
        h("span", { class: "mono secondary" }, s.state === "running" && s.fraction != null ? `${Math.round(s.fraction * 100)}%` : ""),
        s.state === "running" ? h("div", { class: "bar-track" }, h("div", { class: "bar-fill", style: { width: `${Math.round((s.fraction ?? 0) * 100)}%` } })) : null,
      ))),
      h("p", { class: "note", style: { margin: "6px 0 0" } }, "Keep this tab open. An hour of audio takes about 12 to 15 minutes; the transcript shows up before the speakers do."),
    ));
  }

  function renderStatus() {
    if (processing) return;
    const cards: HTMLElement[] = [];
    if (!file) {
      cards.push(h("div", { class: "card warn" },
        h("strong", {}, "Media not found. "),
        `Choose “${project.media?.path ?? "the file"}” again to play it${project.status === "ready" ? "" : " and transcribe it"}. Projects keep a reference to the file, never a copy.`,
        h("div", { style: { marginTop: "8px", display: "flex", gap: "8px" } },
          button("Locate file…", () => locate(), { class: "primary" }),
          hasHandle ? button("Allow access", () => findMedia(true)) : null),
      ));
    }
    if (project.status !== "ready" && file) {
      cards.push(h("div", { class: "card warn" },
        h("strong", {}, project.status === "failed" ? "Transcription stopped. " : project.status === "processing" ? "Transcription was interrupted. " : "Not transcribed yet. "),
        project.failure ?? "",
        h("div", { style: { marginTop: "8px" } }, button("Transcribe", () => process(file!), { class: "primary" })),
      ));
    }
    if (project.languageWarning && project.status === "ready") {
      cards.push(h("div", { class: "card warn" },
        h("strong", {}, "Check the language. "),
        `The transcript reads like ${languageName(project.languageWarning)}, but the audio was taken for ${languageName(project.language ?? "en")}.`));
    }
    status.replaceChildren(...cards.map((c) => h("div", { style: { margin: "12px 16px 0" } }, c)));
  }

  // Rendering

  function renderClock() {
    clock.textContent = `${Timecode.precise(now())} / ${Timecode.short(project.duration)}`;
  }

  function renderControls() {
    const playing = !!media && !media.paused;
    playButton.replaceChildren(icon(playing ? "pause" : "play"));
    playButton.setAttribute("aria-label", playing ? "Pause" : "Play");
    rateButton.lastChild!.textContent = `${media?.playbackRate ?? 1}×`;
    const span = timeline.span || project.duration;
    zoomLabel.textContent = span >= project.duration - 0.01 ? "All" : Timecode.short(span);
    redactToggle.classList.toggle("on", project.settings.redact === true);
    sidebarButton.classList.toggle("on", settings().inspector);
    sidebarButton.setAttribute("aria-pressed", String(settings().inspector));
    redactToggle.setAttribute("aria-pressed", String(project.settings.redact === true));
    markButton.classList.toggle("on", pendingMark != null);
    renderClock();
  }

  function renderHeader() {
    title.textContent = displayTitle(project);
    document.title = `${displayTitle(project)} – Murmur`;
    subtitle.textContent = [project.media?.path, project.duration ? Timecode.short(project.duration) : null, project.speakers.length ? `${project.speakers.length} speaker${project.speakers.length === 1 ? "" : "s"}` : null].filter(Boolean).join(" · ");
  }

  function renderInspector() {
    inspector.hidden = !settings().inspector;
    const dark = isDark(), scheme = settings().scheme;
    const talk = new Map<number, number>();
    for (const p of paragraphs(project.words)) talk.set(p.speaker, (talk.get(p.speaker) ?? 0) + p.end - p.start);
    const total = Math.max(1, [...talk.values()].reduce((a, b) => a + b, 0));
    const section = (name: string, open: boolean, ...content: (Node | string | null)[]) =>
      h("details", { open, on: { toggle: (e: Event) => sessionStorage.setItem(`murmur.fold.${name}`, String((e.target as HTMLDetailsElement).open)) } },
        h("summary", {}, name), h("div", { class: "content" }, content));
    const isOpen = (name: string) => sessionStorage.getItem(`murmur.fold.${name}`) !== "false";

    const parts: HTMLElement[] = [];
    if (project.media?.hasVideo && media instanceof HTMLVideoElement) parts.push(section("Video", isOpen("Video"), media));
    if (project.language) {
      parts.push(section("Language", isOpen("Language"),
        h("div", {}, languageName(project.language), project.languageConfidence ? h("span", { class: "tertiary" }, ` · Ear ${Math.round(project.languageConfidence * 100)}%`) : null),
        project.languageWarning ? h("div", { class: "note" }, `The text reads like ${languageName(project.languageWarning)}.`) : null));
    }
    parts.push(section("Speakers", isOpen("Speakers"), ...(project.speakers.length ? project.speakers.map((s, i) => {
      const c = speakerColor(scheme, i, dark);
      const field = h("input", { class: "field", value: s.name, placeholder: speakerName(s), "aria-label": `Name of ${speakerName(s)}`,
        on: { change: () => change((p) => ({ ...p, speakers: p.speakers.map((x) => (x.id === s.id ? { ...x, name: field.value.trim() } : x)) })), keydown: (e: KeyboardEvent) => e.stopPropagation() } });
      return h("div", { class: "speaker" },
        h("span", { class: `dot${Math.floor(i / 6) % 2 === 1 && scheme !== "vivid" ? " ring" : ""}`, style: { background: c, color: c } }),
        field,
        project.speakers.length > 1 ? button("Merge…", (e) => menu([{ label: `Merge ${speakerName(s)} into`, heading: true }, ...project.speakers.filter((x) => x.id !== s.id).map((x) => ({
          label: speakerName(x), action: () => change((p) => Editing.mergeSpeaker(p, s.id, x.id)),
        }))], e.currentTarget as HTMLElement), { title: "Merge into another speaker" }) : h("span"),
        h("div", { class: "talk", title: `${Math.round(((talk.get(s.id) ?? 0) / total) * 100)}% of the talking` }, h("div", { style: { width: `${((talk.get(s.id) ?? 0) / total) * 100}%`, background: c } })),
      );
    }) : [h("div", { class: "note" }, "Speakers appear once the recording is transcribed.")])));
    parts.push(section("Marks", isOpen("Marks"), ...(project.marks.length ? project.marks.map((m) => {
      const field = h("input", { class: "field", value: m.name, "aria-label": "Mark name",
        on: { change: () => change((p) => ({ ...p, marks: p.marks.map((x) => (x.id === m.id ? { ...x, name: field.value } : x)) })), keydown: (e: KeyboardEvent) => e.stopPropagation() } });
      return h("div", {},
        h("div", { class: "markrow" }, h("span", { class: "swatch" }), field,
          button("Delete mark", () => change((p) => ({ ...p, marks: p.marks.filter((x) => x.id !== m.id) })), { icon: "trash", iconOnly: true })),
        h("div", { style: { display: "flex", gap: "6px", alignItems: "center", marginLeft: "18px" } },
          h("button", { class: "btn", on: { click: () => { selection = { start: m.start, end: m.end }; timeline.selection = selection; seek(m.start); media?.play(); } } }, icon("play"), h("span", { class: "mono" }, `${Timecode.short(m.start)} – ${Timecode.short(m.end)}`))),
      );
    }) : [h("div", { class: "note" }, "Press M at the start of a section and again at its end, or drag on the timeline and press M.")])));
    if (project.settings.redact && project.redactions) {
      parts.push(section("Redaction", isOpen("Redaction"), ...(project.redactions.length ? project.redactions.map((r, i) =>
        h("div", { class: "redrow" },
          h("span", { class: "tag" }, r.category),
          h("button", { class: "field", style: { textAlign: "left", cursor: "pointer" }, on: { click: () => seek(r.start) } }, r.revealed ? r.original : "Hidden", " ", h("span", { class: "mono tertiary" }, Timecode.short(r.start))),
          button(r.revealed ? "Hide" : "Show", () => change((p) => ({ ...p, redactions: p.redactions!.map((x, k) => (k === i ? { ...x, revealed: !x.revealed } : x)) }))),
        )) : [h("div", { class: "note" }, "No personal details were found.")])));
    }
    inspector.replaceChildren(...parts);
  }

  function renderAll(full = true) {
    renderHeader();
    timeline.vertical = settings().verticalTimeline;
    main.classList.toggle("vertical", timeline.vertical);
    timeline.setProject(project);
    if (full || !transcript.editing) transcript.render(project);
    renderControls();
    renderInspector();
    if (!processing) renderStatus();
  }

  // Keys

  function doAction(action: ShortcutAction) {
    const t = now();
    switch (action) {
      case "playPause": return togglePlay();
      case "back": return seek(t - 5);
      case "forward": return seek(t + 5);
      case "previousLine": return seek(transcript.paragraphStart(t, -1) ?? 0);
      case "nextLine": { const n = transcript.paragraphStart(t, 1); return n != null && seek(n); }
      case "slower": return setRate(RATES[Math.max(0, RATES.indexOf(media?.playbackRate ?? 1) - 1)] ?? 1);
      case "faster": return setRate(RATES[Math.min(RATES.length - 1, RATES.indexOf(media?.playbackRate ?? 1) + 1)] ?? 1);
      case "markSection": markSection(); renderControls(); return;
    }
  }

  const onKey = (e: KeyboardEvent) => {
    const target = e.target instanceof Element ? e.target : document.body;
    if (target.closest("input, textarea, select, [contenteditable='true'], dialog")) return;
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "z") {
      e.preventDefault();
      return undoRedo(!e.shiftKey);
    }
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === "?") { e.preventDefault(); showShortcuts(); return; }
    if (e.key === "Escape") {
      pendingMark = null;
      timeline.pendingMark = null;
      selection = null;
      timeline.selection = null;
      timeline.draw();
      renderControls();
      return;
    }
    const key = keyName(e);
    const action = key ? shortcutMap().action(key) : undefined;
    if (!action) return;
    if (target.closest("button") && key === "space") return;
    e.preventDefault();
    doAction(action);
  };
  addEventListener("keydown", onKey);
  const offSettings = onChange(() => renderAll());

  // Layout

  const transcribeAgain = () => file
    ? confirm("Transcribe again?", "The transcript, speakers and redactions are made new. Marks and speaker names you set are kept only where the speakers come out the same.", "Transcribe").then((ok) => { if (ok) process(file!); })
    : toast("Locate the media file first.");
  const sidebarButton = button("Show or hide the sidebar", () => update({ inspector: !settings().inspector }), { icon: "sidebar", iconOnly: true });

  function downloadProject() {
    const blob = new Blob([JSON.stringify(project, null, 2)], { type: "application/json" });
    const a = h("a", { href: URL.createObjectURL(blob), download: `${displayTitle(project)}.murmur.json` });
    a.click();
  }

  main.append(
    h("div", { class: "controls" },
      button("Back 5 seconds", () => doAction("back"), { icon: "back", iconOnly: true }),
      playButton,
      button("Forward 5 seconds", () => doAction("forward"), { icon: "forward", iconOnly: true }),
      clock, rateButton,
      h("div", { class: "segmented", role: "group", "aria-label": "Zoom" },
        h("button", { "aria-label": "Zoom out", on: { click: () => { timeline.zoom(2); renderControls(); } } }, icon("minus")),
        zoomLabel,
        h("button", { "aria-label": "Zoom in", on: { click: () => { timeline.zoom(0.5); renderControls(); } } }, icon("plus"))),
      h("span", { class: "spacer" }),
      markButton,
    ),
    timelineWrap,
    h("div", { class: "column" },
      status,
      h("div", { class: "transcript-head" }, h("h2", {}, "Transcript"), editToggle, redactToggle, h("span", { class: "spacer", style: { flex: 1 } }), search),
      transcript.el,
    ),
  );
  // In the vertical layout the timeline sits beside the column holding the transcript.
  const column = main.lastElementChild as HTMLElement;
  const controls = main.firstElementChild as HTMLElement;
  const arrange = () => {
    if (settings().verticalTimeline) {
      column.prepend(controls);
      main.prepend(timelineWrap);
    } else {
      main.prepend(controls);
      controls.after(timelineWrap);
    }
    timeline.layout();
    timeline.draw();
  };
  const offArrange = onChange(arrange);

  root.append(
    h("header", { class: "bar" },
      h("button", { class: "btn icon", "aria-label": "All projects", title: "All projects", on: { click: () => openLibrary() } }, h("img", { src: "icon.png", alt: "", style: { width: "18px", height: "18px" } })),
      h("div", { class: "title grow" }, title, subtitle),
      button("Copy", (e) => copyMenu(project, selection, e.currentTarget as HTMLElement), { icon: "copy" }),
      button("Export…", () => showExport(project, file, selection), { icon: "export" }),
      button("Transcribe again…", () => transcribeAgain(), { icon: "refresh", iconOnly: true }),
      button("Download the project file", () => downloadProject(), { icon: "save", iconOnly: true }),
      button("Keyboard shortcuts", () => showShortcuts(), { icon: "keyboard", iconOnly: true }),
      button("Settings", () => showSettings(), { icon: "gear", iconOnly: true }),
      sidebarButton,
    ),
    h("div", { class: "project" }, main, inspector),
  );
  arrange();
  renderAll();
  // The waveform is stored with the project, so it shows even while the media is missing.
  timeline.peaks ??= await loadPeaks(id).catch(() => undefined);
  timeline.draw();

  const pending = pendingFiles.get(id);
  await findMedia(false);
  if (pending?.process && file) process(file);

  return () => {
    disposed = true;
    removeEventListener("keydown", onKey);
    offSettings();
    offArrange();
    media?.pause();
    if (mediaUrl) URL.revokeObjectURL(mediaUrl);
    processing?.abort();
    if (processing) stopAll();
    clearTimeout(saveTimer);
    saveProject(project);
    document.title = "Murmur";
  };
}

