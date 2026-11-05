// Recording in the page: the microphone, one browser tab's sound, or both mixed, through MediaRecorder.
// Nothing is uploaded; the recording becomes a project like a dropped file, and its audio is kept in
// this browser (there is no file on disk for the project to point at).
import * as Timecode from "../core/timecode";
import { button, confirm, dialog, h, toast } from "./dom";

export interface Recording {
  file: File;
  duration: number;
}

type Source = "mic" | "tab" | "both";

const TYPES = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4;codecs=mp4a.40.2", "audio/mp4"];

export const canRecord = () => typeof MediaRecorder !== "undefined" && !!navigator.mediaDevices?.getUserMedia;
const canShareTab = () => !!navigator.mediaDevices?.getDisplayMedia;

function recordingName(type: string, at = new Date()) {
  const pad = (n: number) => String(n).padStart(2, "0");
  const ext = type.includes("mp4") ? "m4a" : "webm";
  return `Recording ${at.getFullYear()}-${pad(at.getMonth() + 1)}-${pad(at.getDate())} ${pad(at.getHours())}.${pad(at.getMinutes())}.${ext}`;
}

async function microphone(): Promise<MediaStream> {
  // Echo cancellation keeps a call's far side, playing from the speakers, out of the microphone.
  return navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: false, autoGainControl: true } });
}

async function tabSound(): Promise<MediaStream> {
  // Browsers only share sound along with a picture; the picture is ignored.
  const stream = await navigator.mediaDevices.getDisplayMedia({
    video: true,
    audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false },
    preferCurrentTab: false,
    selfBrowserSurface: "exclude",
    systemAudio: "exclude",
  } as DisplayMediaStreamOptions);
  if (stream.getAudioTracks().length === 0) {
    stream.getTracks().forEach((t) => t.stop());
    throw new Error("no-tab-audio");
  }
  return stream;
}

function describe(error: unknown): string {
  const e = error as Error;
  if (e.message === "no-tab-audio") return "That share has no sound. Choose a tab and turn on “Also share tab audio”.";
  if (e.name === "NotAllowedError") return "Murmur wasn't allowed to record. Allow it in the browser's site settings and try again.";
  if (e.name === "NotFoundError") return "No microphone found.";
  return `Couldn't start recording (${e.message || e.name}).`;
}

/** Asks what to record, records it, and resolves with the recording, or undefined when cancelled. */
export function showRecorder(): Promise<Recording | undefined> {
  let source: Source = "mic";
  const body = h("div", { style: { display: "grid", gap: "14px" } });
  const foot = h("div", { style: { display: "flex", gap: "8px", justifyContent: "flex-end", width: "100%" } });

  return dialog<Recording>("New recording", (done) => {
    // Choosing

    const choose = () => {
      const option = (value: Source, label: string, detail: string) =>
        h("label", { class: "option source" },
          h("input", { type: "radio", name: "source", value, checked: source === value, on: { change: () => (source = value) } }),
          h("span", {}, h("strong", {}, label), h("span", { class: "secondary" }, detail)));
      body.replaceChildren(...[
        option("mic", "Microphone", "A conversation in the room, a voice memo."),
        canShareTab() ? option("tab", "A browser tab's sound", "A call or video playing in another tab. Other apps can't be recorded from a browser.") : null,
        canShareTab() ? option("both", "Microphone and a tab", "A call in the browser: your voice and the others, mixed.") : null,
        h("p", { class: "note", style: { margin: 0 } }, "The recording stays in this browser. Keep this tab open while recording."),
      ].filter((x) => x != null) as Node[]);
      foot.replaceChildren(button("Cancel", () => done()), button("Start recording", () => start(), { class: "primary", icon: "record" }));
    };

    // Recording

    let streams: MediaStream[] = [];
    let context: AudioContext | undefined;
    let recorder: MediaRecorder | undefined;
    let raf = 0;
    const chunks: Blob[] = [];
    let elapsed = 0, since = 0;
    const seconds = () => elapsed + (recorder?.state === "recording" ? (performance.now() - since) / 1000 : 0);

    const release = () => {
      cancelAnimationFrame(raf);
      removeEventListener("beforeunload", warn);
      streams.forEach((s) => s.getTracks().forEach((t) => t.stop()));
      streams = [];
      context?.close().catch(() => {});
      context = undefined;
    };
    const warn = (e: BeforeUnloadEvent) => e.preventDefault();

    const start = async () => {
      try {
        // The tab picker first: it's the one people cancel.
        if (source !== "mic") streams.push(await tabSound());
        if (source !== "tab") streams.push(await microphone());
      } catch (error) {
        release();
        if ((error as Error).name !== "NotAllowedError" || source === "mic") toast(describe(error));
        return;
      }
      context = new AudioContext();
      const mix = context.createMediaStreamDestination();
      const analyser = context.createAnalyser();
      analyser.fftSize = 1024;
      for (const s of streams) {
        const node = context.createMediaStreamSource(new MediaStream(s.getAudioTracks()));
        node.connect(mix);
        node.connect(analyser);
      }
      const type = TYPES.find((t) => MediaRecorder.isTypeSupported(t)) ?? "";
      recorder = new MediaRecorder(mix.stream, type ? { mimeType: type, audioBitsPerSecond: 96_000 } : {});
      recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data);
      recorder.start(1000);
      since = performance.now();
      addEventListener("beforeunload", warn);

      // When the shared tab stops, the microphone keeps going; with nothing left, the recording ends.
      for (const s of streams) for (const t of s.getAudioTracks()) t.addEventListener("ended", () => {
        if (streams.every((x) => x.getAudioTracks().every((a) => a.readyState === "ended"))) stop();
        else toast("The tab stopped sharing. Still recording the microphone.");
      });

      const dlg = body.closest("dialog")!;
      dlg.addEventListener("cancel", (e) => e.preventDefault());
      renderRecording(analyser);
    };

    const clock = h("div", { class: "rec-clock mono" }, "0:00");
    const meter = h("div", { class: "rec-meter" }, h("div", { class: "rec-level" }));
    const what = () => (source === "mic" ? "Recording the microphone." : source === "tab" ? "Recording the tab's sound." : "Recording the microphone and the tab.");
    const status = h("p", { class: "note", style: { margin: 0 } });
    let pauseButton = button("Pause", () => togglePause(), { icon: "pause" });

    const renderRecording = (analyser: AnalyserNode) => {
      status.textContent = what();
      body.replaceChildren(
        h("div", { class: "rec" }, h("span", { class: "rec-dot", "aria-hidden": "true" }), clock),
        meter,
        status,
      );
      foot.replaceChildren(button("Discard", () => discard()), h("span", { style: { flex: 1 } }), pauseButton,
        button("Stop and transcribe", () => stop(), { class: "primary", icon: "stop" }));
      const data = new Float32Array(analyser.fftSize);
      const level = meter.firstChild as HTMLElement;
      let shown = "";
      const frame = () => {
        analyser.getFloatTimeDomainData(data);
        let peak = 0;
        for (const v of data) peak = Math.max(peak, Math.abs(v));
        // A dB scale from -60 to 0, so speech moves the bar visibly.
        const db = 20 * Math.log10(Math.max(peak, 1e-4));
        level.style.width = `${recorder?.state === "paused" ? 0 : Math.max(0, Math.min(100, ((db + 60) / 60) * 100))}%`;
        const text = Timecode.short(seconds());
        if (text !== shown) clock.textContent = shown = text;
        raf = requestAnimationFrame(frame);
      };
      frame();
    };

    const togglePause = () => {
      if (!recorder) return;
      if (recorder.state === "recording") {
        elapsed = seconds();
        recorder.pause();
      } else {
        since = performance.now();
        recorder.resume();
      }
      const paused = recorder.state === "paused";
      const next = button(paused ? "Resume" : "Pause", () => togglePause(), { icon: paused ? "record" : "pause" });
      pauseButton.replaceWith(next);
      pauseButton = next;
      body.querySelector(".rec")?.classList.toggle("paused", paused);
      status.textContent = paused ? "Paused." : what();
    };

    const stop = () => {
      const r = recorder;
      if (!r || r.state === "inactive") return;
      const duration = seconds();
      r.addEventListener("stop", () => {
        release();
        const type = (r.mimeType || chunks[0]?.type || "audio/webm").split(";")[0];
        const blob = new Blob(chunks, { type });
        if (blob.size === 0) {
          toast("Nothing was recorded.");
          return done();
        }
        done({ file: new File([blob], recordingName(type), { type }), duration });
      }, { once: true });
      r.stop();
    };

    const discard = async () => {
      if (seconds() > 10 && !(await confirm("Discard the recording?", `${Timecode.short(seconds())} of audio is thrown away.`, "Discard", true))) return;
      recorder?.stop();
      release();
      done();
    };

    choose();
    return { body: [body], foot: [foot] };
  });
}
