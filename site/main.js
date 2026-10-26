// Murmur's site. The demo is a small working copy of the app's timeline: real Murmur output for the
// first 40 s of a test recording (synthetic voices), played in sync with the audio, with the app's keys.
(() => {
  "use strict";

  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const $ = (id) => document.getElementById(id);

  // ——— Navigation material once the page scrolls under it ———
  const nav = $("nav");
  const onScroll = () => nav.classList.toggle("scrolled", scrollY > 8);
  addEventListener("scroll", onScroll, { passive: true });
  onScroll();

  // ——— Latest release: version, date and the DMG itself ———
  fetch("https://api.github.com/repos/djui/murmur/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
    .then((r) => (r.ok ? r.json() : Promise.reject()))
    .then((rel) => {
      const version = String(rel.tag_name || "").replace(/^v/, "");
      if (!version) return;
      document.querySelectorAll("[data-version]").forEach((el) => (el.textContent = "Version " + version));
      document.querySelectorAll("[data-version-title]").forEach((el) => (el.textContent = "Murmur " + version));
      const date = rel.published_at && new Date(rel.published_at).toLocaleDateString("en", { day: "numeric", month: "long", year: "numeric" });
      document.querySelectorAll("[data-released]").forEach((el) => (el.textContent = date ? "Released " + date + "." : ""));
      const dmg = (rel.assets || []).find((a) => /\.dmg$/i.test(a.name));
      if (dmg) document.querySelectorAll("[data-download]").forEach((a) => (a.href = dmg.browser_download_url));
    })
    .catch(() => {});

  // ——— Pipeline replays its timing when it comes into view ———
  const pipeline = $("pipeline");
  if (pipeline && !reduceMotion && "IntersectionObserver" in window) {
    let at = 0;
    pipeline.querySelectorAll("li").forEach((li, i) => {
      const s = parseFloat(li.style.getPropertyValue("--s"));
      li.style.setProperty("--d", (at * 0.22).toFixed(2) + "s");
      li.style.setProperty("--i", i);
      at += s;
    });
    pipeline.classList.add("armed");
    new IntersectionObserver((entries, io) => {
      if (entries.some((e) => e.isIntersecting)) { pipeline.classList.add("run"); io.disconnect(); }
    }, { threshold: 0.6 }).observe(pipeline);
  } else if (pipeline) {
    pipeline.querySelectorAll("li").forEach((li, i) => li.style.setProperty("--i", i));
  }

  // ——— Demo ———
  const demo = $("demo");
  if (!demo) return;

  /* [text, start, end, speaker] */
  const WORDS = [["Welcome",0,0.4,0],["back",0.4,0.56,0],["to",0.56,0.72,0],["Field",0.72,1.12,0],["Notes.",1.12,1.38,0],["Today",1.76,2.08,0],["I'm",2.08,2.37,0],["sitting",2.4,2.71,0],["down",2.72,2.88,0],["with",2.88,3.1,0],["Jonas,",3.12,3.54,0],["who",3.92,4.1,0],["spent",4.16,4.48,0],["the",4.48,4.64,0],["last",4.64,4.72,0],["two",4.8,4.88,0],["years",5.04,5.29,0],["recording",5.36,5.84,0],["the",5.84,5.97,0],["sound",6,6.24,0],["of",6.24,6.48,0],["glaciers.",6.48,6.92,0],["Thanks",7.84,8.34,1],["for",8.48,8.72,1],["having",8.72,9.12,1],["me.",9.12,9.38,1],["Glaciers",9.52,10.24,1],["are",10.24,10.4,1],["much",10.4,10.56,1],["louder",10.56,11.04,1],["than",11.04,11.25,1],["people",11.28,11.5,1],["expect.",11.6,11.92,1],["It",12.24,12.4,1],["is",12.4,12.64,1],["not",12.64,12.8,1],["a",12.8,12.9,1],["quiet",12.96,13.44,1],["job",13.44,13.84,1],["at",13.84,14.06,1],["all.",14.16,14.8,1],["So",14.99,15.23,0],["how",15.31,15.63,0],["do",15.63,15.79,0],["you",15.79,15.95,0],["even",15.95,16.2,0],["start",16.27,16.59,0],["a",16.59,16.75,0],["project",16.75,17.23,0],["like",17.23,17.47,0],["that?",17.47,17.67,0],["Where",17.87,18.27,0],["do",18.27,18.43,0],["you",18.43,18.67,0],["put",18.67,18.76,0],["the",18.83,19.07,0],["first",19.07,19.31,0],["microphone?",19.31,20.05,0],["Mostly",20.91,21.55,1],["by",21.55,21.71,1],["asking",21.71,22.19,1],["the",22.19,22.43,1],["people",22.43,22.59,1],["who",22.59,22.83,1],["live",22.83,23.15,1],["there,",23.15,23.38,1],["the",23.55,23.71,1],["fisherman",23.71,24.35,1],["knew",24.35,24.58,1],["exactly",24.59,25.07,1],["which",25.07,25.31,1],["parts",25.31,25.58,1],["of",25.63,25.71,1],["the",25.71,25.87,1],["bay",25.87,26.11,1],["were",26.11,26.27,1],["noisy",26.27,26.75,1],["and",26.75,27.02,1],["when.",27.07,27.21,1],["Sorry",28.11,28.59,2],["to",28.59,28.83,2],["jump",28.83,29.13,2],["in,",29.15,29.47,2],["we",29.47,29.53,2],["are",29.63,29.71,2],["getting",30.16,30.56,2],["a",30.56,30.72,2],["bit",30.72,30.8,2],["of",30.88,31.12,2],["wind",31.12,31.44,2],["on",31.44,31.6,2],["the",31.6,31.76,2],["microphone.",31.76,32.46,2],["Could",32.96,33.21,2],["you",33.28,33.52,2],["move",33.52,33.84,2],["a",33.84,34.08,2],["little",34.08,34.26,2],["closer?",34.32,34.89,2],["Like",35.36,35.92,1],["this,",35.92,36.2,1],["is",36.4,36.72,1],["that",36.72,36.99,1],["better?",37.04,37.26,1],["Perfect.",38.08,38.65,2],["Thank",39.12,39.6,2],["you.",39.6,39.8,2]];
  const PEAKS = [0.86, 0.67, 0.86, 0.67, 0.86, 0.99, 0.48, 0.01, 0.71, 0.84, 0.74, 0.76, 0.84, 0.82, 0.88, 0.83, 0.04, 0.75, 0.69, 0.75, 0.99, 0.71, 0.75, 0.88, 0.85, 0.93, 0.82, 0.88, 0.86, 0.82, 0.79, 0.41, 0.0, 0.0, 0.0, 0.0, 0.73, 0.65, 0.65, 0.84, 0.8, 0.39, 0.11, 0.83, 0.82, 0.93, 1, 0.85, 0.99, 0.8, 0.76, 0.69, 0.5, 0.49, 0.04, 0.84, 0.63, 0.87, 1, 1, 0.89, 0.93, 0.72, 0.14, 0.0, 0.0, 0.0, 0.01, 0.88, 0.92, 0.78, 0.78, 0.78, 1, 0.94, 0.96, 0.76, 1, 0.82, 0.79, 0.01, 0.94, 0.75, 0.79, 0.77, 0.79, 0.93, 0.95, 0.91, 0.93, 0.43, 0.0, 0.0, 0.0, 0.18, 0.73, 0.64, 1, 0.95, 0.76, 0.73, 0.62, 0.73, 0.73, 0.61, 0.29, 0.69, 0.61, 0.63, 0.69, 0.71, 0.87, 0.76, 0.72, 0.9, 0.77, 0.68, 0.87, 0.73, 0.77, 0.62, 0.63, 0.07, 0.0, 0.0, 0.0, 0.0, 0.52, 0.5, 0.41, 0.41, 0.47, 0.37, 0.02, 0.47, 0.46, 0.49, 0.4, 0.49, 0.48, 0.47, 0.43, 0.44, 0.5, 0.39, 0.41, 0.15, 0.0, 0.01, 0.42, 0.42, 0.41, 0.46, 0.45, 0.49, 0.48, 0.44, 0.26, 0.0, 0.01, 0.96, 0.49, 0.29, 0.02, 0.83, 0.84, 0.83, 0.45, 0.0, 0.0, 0.0, 0.0, 0.46, 0.42, 0.05, 0.01, 0.52, 0.44, 0.38, 0.25];
  const NAMES = ["Maya", "Jonas", "Producer"];
  const COLORS = ["var(--s0)", "var(--s1)", "var(--s2)"];
  const TEXT_COLORS = ["var(--s0-text)", "var(--s1-text)", "var(--s2-text)"];
  const DURATION = 40;
  // Found by Murmur's redaction model in this recording.
  const REDACTIONS = [{ from: 10, to: 10, label: "name" }];

  const words = WORDS.map(([text, start, end, speaker], i) => ({ i, text, start, end, speaker, mid: (start + end) / 2 }));

  // Paragraphs as in MurmurCore's Merge.paragraphs: a new speaker or a pause over 1.5 s starts one.
  const paragraphs = (list) => {
    const out = [];
    list.forEach((w, k) => {
      const prev = list[k - 1];
      if (!prev || prev.speaker !== w.speaker || w.start - prev.end > 1.5) out.push({ speaker: w.speaker, start: w.start, end: w.end, words: [] });
      const p = out[out.length - 1];
      p.words.push(w);
      p.end = w.end;
    });
    return out;
  };
  const paras = paragraphs(words);

  const short = (t) => {
    const s = Math.max(0, Math.floor(t));
    return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
  };
  const precise = (t) => {
    const tenths = Math.max(0, Math.floor(t * 10));
    return short(tenths / 10) + "." + (tenths % 10);
  };
  const clock = (t, sep) => {
    const ms = Math.round(Math.max(0, t) * 1000);
    const p = (n, l = 2) => String(n).padStart(l, "0");
    return p(Math.floor(ms / 3600000)) + ":" + p(Math.floor(ms / 60000) % 60) + ":" + p(Math.floor(ms / 1000) % 60) + sep + p(ms % 1000, 3);
  };
  const pct = (t) => (t / DURATION * 100) + "%";

  const play = $("play"), clockEl = $("clock"), track = $("track"), playhead = $("playhead");
  const marksRow = $("t-marks"), waveEl = $("t-wave"), lanesEl = $("t-lanes"), ruler = $("t-ruler");
  const script = $("script"), markBtn = $("mark"), markLabel = $("mark-label"), redactBox = $("redact");
  const marksList = $("marks"), output = $("output"), copyBtn = $("copy"), formats = $("formats");

  // Waveform, coloured by who is speaking.
  const speakerAt = (t) => {
    for (const p of paras) if (t >= p.start - 0.1 && t <= p.end + 0.1) return p.speaker;
    return -1;
  };
  // Narrow screens get half as many bars, each the louder of a pair.
  const peaks = track.clientWidth < 520 ? PEAKS.filter((_, i) => i % 2 === 0).map((v, i) => Math.max(v, PEAKS[i * 2 + 1] ?? 0)) : PEAKS;
  const bars = peaks.map((v, i) => {
    const t = (i + 0.5) / peaks.length * DURATION;
    const s = speakerAt(t);
    const el = document.createElement("span");
    el.style.height = Math.max(3, v * 100) + "%";
    if (s >= 0) el.style.setProperty("--c", COLORS[s]);
    el.dataset.t = t;
    waveEl.appendChild(el);
    return el;
  });

  // One lane per speaker.
  NAMES.forEach((_, s) => {
    const lane = document.createElement("div");
    lane.className = "lane";
    paras.filter((p) => p.speaker === s).forEach((p) => {
      const b = document.createElement("i");
      b.style.left = pct(p.start);
      b.style.width = pct(Math.min(p.end, DURATION) - p.start);
      b.style.setProperty("--c", COLORS[s]);
      lane.appendChild(b);
    });
    lanesEl.appendChild(lane);
  });

  for (let t = 0; t < DURATION; t += 5) {
    const tick = document.createElement("span");
    tick.style.left = pct(t);
    tick.textContent = short(t);
    if (t % 10) tick.className = "minor";
    ruler.appendChild(tick);
  }

  // Transcript.
  const wordEls = [];
  const paraEls = paras.map((p) => {
    const row = document.createElement("div");
    row.className = "para";
    const who = document.createElement("div");
    who.className = "who";
    who.style.color = TEXT_COLORS[p.speaker];
    who.textContent = NAMES[p.speaker];
    const small = document.createElement("small");
    small.textContent = short(p.start);
    who.appendChild(small);
    const body = document.createElement("div");
    body.className = "words";
    p.words.forEach((w, k) => {
      const span = document.createElement("span");
      span.className = "w";
      span.textContent = w.text;
      span.dataset.i = w.i;
      wordEls[w.i] = span;
      body.appendChild(span);
      if (k < p.words.length - 1) body.appendChild(document.createTextNode(" "));
    });
    row.append(who, body);
    script.appendChild(row);
    return row;
  });

  // ——— Playback ———
  const audio = new Audio("assets/sample.m4a");
  audio.preload = "none";
  let t = 0, playing = false, stopAt = null, fallbackStart = 0, useFallback = false, raf = 0;

  const setPlaying = (on) => {
    playing = on;
    demo.classList.toggle("playing", on);
    play.setAttribute("aria-label", on ? "Pause" : "Play");
    if (on) tick(); else cancelAnimationFrame(raf);
  };
  const start = () => {
    if (t >= DURATION - 0.05) seek(0);
    const go = () => { useFallback = false; setPlaying(true); };
    // play() stays inside the click; the position can only be set once the file's length is known.
    const from = t;
    if (audio.readyState >= 1) audio.currentTime = from;
    else audio.addEventListener("loadedmetadata", () => { audio.currentTime = from; }, { once: true });
    const p = audio.play();
    if (p && p.then) p.then(go).catch(() => { useFallback = true; fallbackStart = performance.now() - t * 1000; setPlaying(true); });
    else go();
  };
  const pause = () => { audio.pause(); stopAt = null; setPlaying(false); };
  const toggle = () => (playing ? pause() : start());
  const seek = (to) => {
    t = Math.min(DURATION, Math.max(0, to));
    if (!useFallback) { try { audio.currentTime = t; } catch (_) {} }
    fallbackStart = performance.now() - t * 1000;
    render(true);
  };
  audio.addEventListener("ended", () => { t = DURATION; pause(); render(); });

  function tick() {
    if (useFallback) t = (performance.now() - fallbackStart) / 1000;
    else if (audio.readyState >= 1 && !audio.seeking) t = audio.currentTime;
    if (stopAt != null && t >= stopAt) { t = stopAt; pause(); }
    if (t >= DURATION) { t = DURATION; pause(); }
    render();
    if (playing) raf = requestAnimationFrame(tick);
  }

  // ——— Drawing the current moment ———
  let lastWord = -1, lastPara = -1, lastBar = -1;
  const currentWord = () => {
    for (const w of words) if (t >= w.start - 0.02 && t < w.end + 0.15) return w.i;
    return -1;
  };
  function render(jumped) {
    clockEl.textContent = precise(t);
    playhead.style.transform = `translateX(${track.clientWidth * t / DURATION}px)`;
    track.setAttribute("aria-valuenow", t.toFixed(1));
    track.setAttribute("aria-valuetext", Math.round(t) + " seconds");

    const bar = Math.floor(t / DURATION * bars.length);
    if (bar !== lastBar) {
      bars.forEach((b, i) => b.classList.toggle("past", i < bar));
      lastBar = bar;
    }

    const wi = currentWord();
    if (wi !== lastWord) {
      if (lastWord >= 0) wordEls[lastWord].classList.remove("cur");
      if (wi >= 0) wordEls[wi].classList.add("cur");
      lastWord = wi;
    }
    let pi = paras.findIndex((p) => t >= p.start - 0.3 && t <= p.end + 0.6);
    if (pi < 0) pi = paras.findIndex((p) => p.start > t) - 1;
    if (pi !== lastPara || jumped) {
      if (lastPara >= 0) paraEls[lastPara].classList.remove("now");
      if (pi >= 0) {
        paraEls[pi].classList.add("now");
        const row = paraEls[pi];
        const top = row.offsetTop - script.offsetTop - 10;
        if (top < script.scrollTop || top + row.offsetHeight > script.scrollTop + script.clientHeight - 10) {
          script.scrollTo({ top, behavior: reduceMotion || jumped ? "auto" : "smooth" });
        }
      }
      lastPara = pi;
    }
    if (pi >= 0) {
      paras[pi].words.forEach((w) => wordEls[w.i].classList.toggle("later", w.start > t + 0.05));
    }
    if (pendingStart != null) drawMarks();
  }

  // ——— Marks: M at the start, M again at the end (ProjectSession.toggleMarkSection) ———
  let marks = [{ name: "Finding the first microphone spot", start: 13.01, end: 27 }];
  let selected = 0, pendingStart = null, format = "timestamps";

  const toggleMark = () => {
    if (pendingStart == null) {
      pendingStart = t;
    } else {
      const lo = Math.min(pendingStart, t), hi = Math.max(pendingStart, t);
      pendingStart = null;
      if (hi - lo >= 0.3) {
        marks.push({ name: "Mark " + (marks.length + 1), start: lo, end: hi });
        selected = marks.length - 1;
        renderMarks();
      }
    }
    demo.classList.toggle("pending", pendingStart != null);
    markLabel.textContent = pendingStart != null ? "End section" : "Mark section";
    drawMarks();
  };
  const cancelMark = () => {
    pendingStart = null;
    demo.classList.remove("pending");
    markLabel.textContent = "Mark section";
    drawMarks();
  };

  function drawMarks() {
    marksRow.textContent = "";
    const add = (m, cls) => {
      const el = document.createElement("span");
      el.className = "m" + (cls ? " " + cls : "");
      el.style.left = pct(m.start);
      el.style.width = pct(Math.max(0.4, m.end - m.start));
      el.textContent = m.name;
      marksRow.appendChild(el);
    };
    marks.forEach((m) => add(m));
    if (pendingStart != null) add({ name: "", start: Math.min(pendingStart, t), end: Math.max(pendingStart, t) }, "pending");
  }

  function renderMarks() {
    marksList.textContent = "";
    if (!marks.length) {
      const li = document.createElement("li");
      li.className = "empty";
      li.textContent = "No marks. Press M at the start of a part and again at its end.";
      marksList.appendChild(li);
    }
    marks.forEach((m, i) => {
      const li = document.createElement("li");
      li.setAttribute("aria-current", i === selected ? "true" : "false");
      const sw = document.createElement("span");
      sw.className = "swatch";
      const name = document.createElement("input");
      name.value = m.name;
      name.setAttribute("aria-label", "Mark name");
      name.addEventListener("input", () => { m.name = name.value; drawMarks(); renderOutput(); });
      name.addEventListener("focus", () => select(i));
      const range = document.createElement("span");
      range.className = "range";
      range.textContent = `${short(m.start)} – ${short(m.end)} · ${short(m.end - m.start)}`;
      const acts = document.createElement("span");
      acts.className = "acts";
      const playBtn = iconButton("Play " + (m.name || "mark"), '<path d="M7 4.6v14.8a1 1 0 0 0 1.5.86l12.4-7.4a1 1 0 0 0 0-1.72L8.5 3.74A1 1 0 0 0 7 4.6z" fill="currentColor"/>');
      playBtn.addEventListener("click", (e) => { e.stopPropagation(); select(i); seek(m.start); stopAt = m.end; start(); });
      const del = iconButton("Remove " + (m.name || "mark"), '<path d="M6 6l12 12M18 6 6 18" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>');
      del.addEventListener("click", (e) => {
        e.stopPropagation();
        marks.splice(i, 1);
        selected = Math.min(selected, marks.length - 1);
        renderMarks();
        drawMarks();
      });
      acts.append(playBtn, del);
      li.append(sw, name, acts, range);
      li.addEventListener("click", () => select(i));
      marksList.appendChild(li);
    });
    renderOutput();
  }
  function iconButton(label, path) {
    const b = document.createElement("button");
    b.type = "button";
    b.setAttribute("aria-label", label);
    b.innerHTML = `<svg width="13" height="13" viewBox="0 0 24 24" aria-hidden="true">${path}</svg>`;
    return b;
  }
  function select(i) {
    if (selected === i) return;
    selected = i;
    marksList.querySelectorAll("li").forEach((li, k) => li.setAttribute("aria-current", k === i ? "true" : "false"));
    renderOutput();
  }

  // ——— Copy, as MurmurCore's Renderer would write it ———
  const redacted = () => redactBox.checked;
  const visibleWords = (from, to) => {
    let list = words.filter((w) => w.mid >= from && w.mid <= to);
    if (redacted()) {
      const out = [];
      for (const w of list) {
        const r = REDACTIONS.find((r) => w.i >= r.from && w.i <= r.to);
        if (!r) out.push(w);
        else if (w.i === r.from) out.push({ ...w, text: "[" + r.label + "]", end: words[r.to].end });
      }
      list = out;
    }
    return list;
  };
  const join = (list) => list.map((w) => w.text).join(" ");
  const cueChunks = (list) => {
    const out = [];
    let cur = [], chars = 0;
    for (const w of list) {
      if (cur.length && (w.end - cur[0].start > 6 || chars + w.text.length > 80)) { out.push(cur); cur = []; chars = 0; }
      cur.push(w);
      chars += w.text.length + 1;
    }
    if (cur.length) out.push(cur);
    return out;
  };
  function renderOutput() {
    const m = marks[selected];
    if (!m) { output.textContent = ""; copyBtn.disabled = true; return; }
    copyBtn.disabled = false;
    const ps = paragraphs(visibleWords(m.start, m.end));
    let text;
    if (format === "srt") {
      let n = 0;
      text = ps.flatMap((p) => cueChunks(p.words).map((c) => `${++n}\n${clock(c[0].start, ",")} --> ${clock(c[c.length - 1].end, ",")}\n${NAMES[p.speaker]}: ${join(c)}`)).join("\n\n");
    } else {
      const blocks = ps.map((p) => {
        const who = NAMES[p.speaker], time = short(p.words[0].start), body = join(p.words);
        if (format === "markdown") return `**${who}** · ${time}\n${body}`;
        if (format === "timestamps") return `[${time}] ${who}: ${body}`;
        return `${who}: ${body}`;
      });
      if (format === "markdown" && m.name) blocks.unshift(`## ${m.name} (${short(m.start)} – ${short(m.end)})`);
      text = blocks.join("\n\n");
    }
    output.textContent = text + "\n";
  }

  formats.addEventListener("click", (e) => {
    const b = e.target.closest("button[data-format]");
    if (!b) return;
    format = b.dataset.format;
    formats.querySelectorAll("button").forEach((x) => x.setAttribute("aria-checked", x === b ? "true" : "false"));
    renderOutput();
  });
  formats.addEventListener("keydown", (e) => {
    if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return;
    const all = [...formats.querySelectorAll("button")];
    const i = all.findIndex((b) => b.getAttribute("aria-checked") === "true");
    const next = all[(i + (e.key === "ArrowRight" ? 1 : all.length - 1)) % all.length];
    next.click();
    next.focus();
    e.preventDefault();
    e.stopPropagation();
  });
  copyBtn.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(output.textContent);
      copyBtn.textContent = "Copied";
    } catch (_) {
      getSelection().selectAllChildren(output);
      copyBtn.textContent = "Selected";
    }
    copyBtn.classList.add("done");
    setTimeout(() => { copyBtn.textContent = "Copy"; copyBtn.classList.remove("done"); }, 1400);
  });

  redactBox.addEventListener("change", () => {
    REDACTIONS.forEach((r) => {
      for (let i = r.from; i <= r.to; i++) {
        const el = wordEls[i];
        el.classList.toggle("hidden", redacted());
        el.textContent = redacted() ? (i === r.from ? r.label : "") : WORDS[i][0];
      }
    });
    renderOutput();
  });

  // ——— Input ———
  play.addEventListener("click", toggle);
  markBtn.addEventListener("click", toggleMark);
  script.addEventListener("click", (e) => {
    const w = e.target.closest(".w");
    if (w) seek(words[+w.dataset.i].start);
  });

  const timeAt = (x) => {
    const r = track.getBoundingClientRect();
    return (x - r.left) / r.width * DURATION;
  };
  let dragging = false;
  track.addEventListener("pointerdown", (e) => {
    dragging = true;
    track.setPointerCapture(e.pointerId);
    stopAt = null;
    seek(timeAt(e.clientX));
  });
  track.addEventListener("pointermove", (e) => { if (dragging) seek(timeAt(e.clientX)); });
  track.addEventListener("pointerup", () => (dragging = false));
  track.addEventListener("pointercancel", () => (dragging = false));

  // The app's keys. They work while focus is in the demo, or while the demo is on screen and
  // nothing else has focus, so Space never fights with page scrolling elsewhere.
  let onScreen = false;
  if ("IntersectionObserver" in window) {
    new IntersectionObserver(([e]) => (onScreen = e.intersectionRatio >= 0.5), { threshold: [0, 0.5, 1] }).observe(demo);
  }
  addEventListener("keydown", (e) => {
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const a = document.activeElement;
    const typing = a && (a.tagName === "INPUT" && a.type === "text" || a.tagName === "TEXTAREA" || a.isContentEditable);
    if (typing) return;
    const inside = demo.contains(a) || a === track;
    const idle = !a || a === document.body || a === demo;
    if (!inside && !(idle && onScreen)) return;
    if (a && a.tagName === "BUTTON" && (e.key === " " || e.key === "Enter")) return;
    switch (e.key) {
      case " ": toggle(); break;
      case "ArrowLeft": stopAt = null; seek(t - (e.shiftKey ? 1 : 5)); break;
      case "ArrowRight": stopAt = null; seek(t + (e.shiftKey ? 1 : 5)); break;
      case "Escape": cancelMark(); break;
      case "m": case "M": toggleMark(); break;
      case "Home": seek(0); break;
      default: return;
    }
    e.preventDefault();
  });

  addEventListener("resize", () => render());
  drawMarks();
  renderMarks();
  render(true);
})();
