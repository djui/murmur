// Interactive sample: real Murmur output (words, timings, speakers) for the first 40 s of the
// Field Notes test recording, played in sync with the audio.
(() => {
  const WORDS = [["Welcome",0,0.4,0],["back",0.4,0.56,0],["to",0.56,0.72,0],["Field",0.72,1.12,0],["Notes.",1.12,1.38,0],["Today",1.76,2.08,0],["I'm",2.08,2.37,0],["sitting",2.4,2.71,0],["down",2.72,2.88,0],["with",2.88,3.1,0],["Jonas,",3.12,3.54,0],["who",3.92,4.1,0],["spent",4.16,4.48,0],["the",4.48,4.64,0],["last",4.64,4.72,0],["two",4.8,4.88,0],["years",5.04,5.29,0],["recording",5.36,5.84,0],["the",5.84,5.97,0],["sound",6,6.24,0],["of",6.24,6.48,0],["glaciers.",6.48,6.92,0],["Thanks",7.84,8.34,1],["for",8.48,8.72,1],["having",8.72,9.12,1],["me.",9.12,9.38,1],["Glaciers",9.52,10.24,1],["are",10.24,10.4,1],["much",10.4,10.56,1],["louder",10.56,11.04,1],["than",11.04,11.25,1],["people",11.28,11.5,1],["expect.",11.6,11.92,1],["It",12.24,12.4,1],["is",12.4,12.64,1],["not",12.64,12.8,1],["a",12.8,12.9,1],["quiet",12.96,13.44,1],["job",13.44,13.84,1],["at",13.84,14.06,1],["all.",14.16,14.8,1],["So",14.99,15.23,0],["how",15.31,15.63,0],["do",15.63,15.79,0],["you",15.79,15.95,0],["even",15.95,16.2,0],["start",16.27,16.59,0],["a",16.59,16.75,0],["project",16.75,17.23,0],["like",17.23,17.47,0],["that?",17.47,17.67,0],["Where",17.87,18.27,0],["do",18.27,18.43,0],["you",18.43,18.67,0],["put",18.67,18.76,0],["the",18.83,19.07,0],["first",19.07,19.31,0],["microphone?",19.31,20.05,0],["Mostly",20.91,21.55,1],["by",21.55,21.71,1],["asking",21.71,22.19,1],["the",22.19,22.43,1],["people",22.43,22.59,1],["who",22.59,22.83,1],["live",22.83,23.15,1],["there,",23.15,23.38,1],["the",23.55,23.71,1],["fisherman",23.71,24.35,1],["knew",24.35,24.58,1],["exactly",24.59,25.07,1],["which",25.07,25.31,1],["parts",25.31,25.58,1],["of",25.63,25.71,1],["the",25.71,25.87,1],["bay",25.87,26.11,1],["were",26.11,26.27,1],["noisy",26.27,26.75,1],["and",26.75,27.02,1],["when.",27.07,27.21,1],["Sorry",28.11,28.59,2],["to",28.59,28.83,2],["jump",28.83,29.13,2],["in,",29.15,29.47,2],["we",29.47,29.53,2],["are",29.63,29.71,2],["getting",30.16,30.56,2],["a",30.56,30.72,2],["bit",30.72,30.8,2],["of",30.88,31.12,2],["wind",31.12,31.44,2],["on",31.44,31.6,2],["the",31.6,31.76,2],["microphone.",31.76,32.46,2],["Could",32.96,33.21,2],["you",33.28,33.52,2],["move",33.52,33.84,2],["a",33.84,34.08,2],["little",34.08,34.26,2],["closer?",34.32,34.89,2],["Like",35.36,35.92,1],["this,",35.92,36.2,1],["is",36.4,36.72,1],["that",36.72,36.99,1],["better?",37.04,37.26,1],["Perfect.",38.08,38.65,2],["Thank",39.12,39.6,2],["you.",39.6,39.8,2]]; // [text, start, end, speaker]
  const PEAKS = [0.86, 0.67, 0.86, 0.67, 0.86, 0.99, 0.48, 0.01, 0.71, 0.84, 0.74, 0.76, 0.84, 0.82, 0.88, 0.83, 0.04, 0.75, 0.69, 0.75, 0.99, 0.71, 0.75, 0.88, 0.85, 0.93, 0.82, 0.88, 0.86, 0.82, 0.79, 0.41, 0.0, 0.0, 0.0, 0.0, 0.73, 0.65, 0.65, 0.84, 0.8, 0.39, 0.11, 0.83, 0.82, 0.93, 1, 0.85, 0.99, 0.8, 0.76, 0.69, 0.5, 0.49, 0.04, 0.84, 0.63, 0.87, 1, 1, 0.89, 0.93, 0.72, 0.14, 0.0, 0.0, 0.0, 0.01, 0.88, 0.92, 0.78, 0.78, 0.78, 1, 0.94, 0.96, 0.76, 1, 0.82, 0.79, 0.01, 0.94, 0.75, 0.79, 0.77, 0.79, 0.93, 0.95, 0.91, 0.93, 0.43, 0.0, 0.0, 0.0, 0.18, 0.73, 0.64, 1, 0.95, 0.76, 0.73, 0.62, 0.73, 0.73, 0.61, 0.29, 0.69, 0.61, 0.63, 0.69, 0.71, 0.87, 0.76, 0.72, 0.9, 0.77, 0.68, 0.87, 0.73, 0.77, 0.62, 0.63, 0.07, 0.0, 0.0, 0.0, 0.0, 0.52, 0.5, 0.41, 0.41, 0.47, 0.37, 0.02, 0.47, 0.46, 0.49, 0.4, 0.49, 0.48, 0.47, 0.43, 0.44, 0.5, 0.39, 0.41, 0.15, 0.0, 0.01, 0.42, 0.42, 0.41, 0.46, 0.45, 0.49, 0.48, 0.44, 0.26, 0.0, 0.01, 0.96, 0.49, 0.29, 0.02, 0.83, 0.84, 0.83, 0.45, 0.0, 0.0, 0.0, 0.0, 0.46, 0.42, 0.05, 0.01, 0.52, 0.44, 0.38, 0.25];
  const NAMES = ["Maya", "Jonas", "Producer"];
  const COLORS = ["var(--s0)", "var(--s1)", "var(--s2)"];
  const DURATION = 40;

  const $ = (id) => document.getElementById(id);
  const wave = $("wave"), lanes = $("lanes"), lines = $("lines"), clock = $("clock"), play = $("play");
  if (!wave) return;

  const audio = new Audio("assets/sample.m4a");
  audio.preload = "metadata";
  let fakeStart = null, fakeOffset = 0; // fallback clock if audio can't play

  // Paragraphs: speaker changes or pauses over 1.5 s.
  const paras = [];
  WORDS.forEach((w, i) => {
    const prev = WORDS[i - 1];
    if (!prev || prev[3] !== w[3] || w[1] - prev[2] > 1.5) paras.push({ speaker: w[3], start: w[1], end: w[2], words: [] });
    const p = paras[paras.length - 1];
    p.words.push(i);
    p.end = w[2];
  });

  const speakerAt = (t) => {
    for (const p of paras) if (t >= p.start - 0.1 && t <= p.end + 0.1) return p.speaker;
    return -1;
  };

  // Waveform bars, coloured by speaker.
  const bars = PEAKS.map((v, i) => {
    const t = (i + 0.5) / PEAKS.length * DURATION;
    const s = speakerAt(t);
    const el = document.createElement("span");
    el.style.height = Math.max(4, v * 100) + "%";
    el.style.background = s < 0 ? "var(--line)" : COLORS[s];
    el.dataset.t = t;
    wave.appendChild(el);
    return el;
  });
  const head = document.createElement("div");
  head.className = "head";
  wave.appendChild(head);

  // Speaker lanes.
  NAMES.forEach((_, s) => {
    const lane = document.createElement("div");
    lane.className = "lane";
    paras.filter((p) => p.speaker === s).forEach((p) => {
      const b = document.createElement("i");
      b.style.left = (p.start / DURATION * 100) + "%";
      b.style.width = ((Math.min(p.end, DURATION) - p.start) / DURATION * 100) + "%";
      b.style.background = COLORS[s];
      lane.appendChild(b);
    });
    lanes.appendChild(lane);
  });
  const laneHead = document.createElement("div");
  laneHead.className = "head";
  lanes.appendChild(laneHead);

  // Transcript lines.
  const inner = document.createElement("div");
  inner.className = "lines-inner";
  lines.appendChild(inner);
  const fmt = (t) => {
    const s = Math.max(0, Math.floor(t));
    return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
  };
  const lineEls = paras.map((p) => {
    const row = document.createElement("div");
    row.className = "line";
    const who = document.createElement("div");
    who.className = "who";
    who.style.color = COLORS[p.speaker];
    who.textContent = NAMES[p.speaker];
    const small = document.createElement("small");
    small.textContent = fmt(p.start);
    who.appendChild(small);
    const text = document.createElement("div");
    text.className = "text";
    p.spans = p.words.map((i, k) => {
      const sp = document.createElement("span");
      sp.textContent = WORDS[i][0];
      text.appendChild(sp);
      if (k < p.words.length - 1) text.appendChild(document.createTextNode(" "));
      return sp;
    });
    row.append(who, text);
    row.addEventListener("click", () => seek(p.start + 0.01));
    inner.appendChild(row);
    return row;
  });

  const now = () => {
    if (fakeStart !== null) return Math.min(DURATION, fakeOffset + (performance.now() - fakeStart) / 1000);
    return audio.currentTime || fakeOffset;
  };
  const playing = () => fakeStart !== null || !audio.paused;

  let lastActive = -1;
  function render() {
    const t = now();
    const pct = (t / DURATION * 100) + "%";
    head.style.left = pct;
    laneHead.style.left = pct;
    bars.forEach((b) => b.classList.toggle("on", b.dataset.t <= t));
    clock.textContent = fmt(t);
    wave.setAttribute("aria-valuenow", Math.round(t));
    let active = paras.findIndex((p) => t >= p.start - 0.05 && t < p.end + 0.4);
    if (active < 0) active = lastActive;
    paras.forEach((p, i) => {
      lineEls[i].classList.toggle("active", i === active);
      p.spans.forEach((sp, k) => {
        const w = WORDS[p.words[k]];
        sp.className = i !== active ? "" : t >= w[2] ? "past" : t >= w[1] ? "now" : "";
      });
    });
    if (active !== lastActive && active >= 0) {
      lastActive = active;
      const top = lineEls[active].offsetTop - 40;
      inner.style.transform = `translateY(${-Math.max(0, top)}px)`;
    }
    if (fakeStart !== null && t >= DURATION) stop();
    if (playing()) requestAnimationFrame(render);
  }

  function setIcon() {
    play.innerHTML = `<svg width="16" height="16" aria-hidden="true"><use href="#i-${playing() ? "pause" : "play"}"/></svg>`;
    play.setAttribute("aria-label", playing() ? "Pause the sample" : "Play the sample");
  }

  function start() {
    if (now() >= DURATION - 0.1) seek(0);
    audio.play().then(() => { setIcon(); render(); }).catch(() => {
      // No audio (blocked or unsupported): run the clock silently.
      fakeStart = performance.now();
      setIcon();
      render();
    });
  }

  function stop() {
    if (fakeStart !== null) { fakeOffset = now(); fakeStart = null; }
    audio.pause();
    setIcon();
    render();
  }

  function seek(t) {
    t = Math.max(0, Math.min(DURATION, t));
    fakeOffset = t;
    if (fakeStart !== null) fakeStart = performance.now();
    try { audio.currentTime = t; } catch (e) { /* metadata not loaded yet */ }
    render();
  }

  play.addEventListener("click", () => (playing() ? stop() : start()));
  audio.addEventListener("ended", () => { setIcon(); render(); });
  audio.addEventListener("seeked", render);

  const seekFromEvent = (e) => {
    const r = wave.getBoundingClientRect();
    seek((e.clientX - r.left) / r.width * DURATION);
  };
  let dragging = false;
  wave.addEventListener("pointerdown", (e) => { dragging = true; wave.setPointerCapture(e.pointerId); seekFromEvent(e); });
  wave.addEventListener("pointermove", (e) => { if (dragging) seekFromEvent(e); });
  wave.addEventListener("pointerup", () => { dragging = false; });
  wave.addEventListener("keydown", (e) => {
    if (e.key === "ArrowRight") { seek(now() + 2); e.preventDefault(); }
    if (e.key === "ArrowLeft") { seek(now() - 2); e.preventDefault(); }
    if (e.key === " ") { playing() ? stop() : start(); e.preventDefault(); }
  });

  render();
})();

// Point the download buttons at the latest DMG and show its version.
(async () => {
  try {
    const res = await fetch("https://api.github.com/repos/djui/murmur/releases/latest");
    if (!res.ok) return;
    const release = await res.json();
    const dmg = (release.assets || []).find((a) => a.name.endsWith(".dmg"));
    if (!dmg) return;
    for (const id of ["download", "download-2"]) {
      const a = document.getElementById(id);
      if (a) a.href = dmg.browser_download_url;
    }
    const mb = Math.max(1, Math.round(dmg.size / 1e6));
    const v = document.getElementById("version");
    if (v) v.textContent = `Version ${release.tag_name.replace(/^v/, "")} · ${mb} MB, plus a one-time 515 MB model download`;
  } catch (e) {
    /* keep the release-page link */
  }
})();
