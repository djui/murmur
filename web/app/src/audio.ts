// Audio in the page: decoding a file to what the models read, and writing WAV clips.
import type { RedactedSpan } from "./core/project";

export const RATE = 16_000;

/** The whole file as mono samples at 16 kHz, decoded by the browser (any format it plays). */
export async function decode(file: Blob, rate = RATE): Promise<Float32Array> {
  const buffer = await new OfflineAudioContext(1, 1, rate).decodeAudioData(await file.arrayBuffer());
  if (buffer.numberOfChannels === 1) return buffer.getChannelData(0).slice();
  const mono = new Float32Array(buffer.length);
  for (let c = 0; c < buffer.numberOfChannels; c++) {
    const channel = buffer.getChannelData(c);
    for (let i = 0; i < mono.length; i++) mono[i] += channel[i] / buffer.numberOfChannels;
  }
  return mono;
}

/** 16-bit mono WAV. */
export function wav(samples: Float32Array, rate: number): Blob {
  const data = new DataView(new ArrayBuffer(44 + samples.length * 2));
  const text = (offset: number, s: string) => [...s].forEach((c, i) => data.setUint8(offset + i, c.charCodeAt(0)));
  text(0, "RIFF");
  data.setUint32(4, 36 + samples.length * 2, true);
  text(8, "WAVE");
  text(12, "fmt ");
  data.setUint32(16, 16, true);
  data.setUint16(20, 1, true);
  data.setUint16(22, 1, true);
  data.setUint32(24, rate, true);
  data.setUint32(28, rate * 2, true);
  data.setUint16(32, 2, true);
  data.setUint16(34, 16, true);
  text(36, "data");
  data.setUint32(40, samples.length * 2, true);
  for (let i = 0; i < samples.length; i++) data.setInt16(44 + i * 2, Math.max(-1, Math.min(1, samples[i])) * 0x7fff, true);
  return new Blob([data.buffer], { type: "audio/wav" });
}

/** `[start, end]` of the samples, with hidden personal details replaced by a 1 kHz tone. */
export function clip(samples: Float32Array, rate: number, start: number, end: number, bleep: RedactedSpan[] = []): Float32Array {
  const lo = Math.max(0, Math.floor(start * rate)), hi = Math.min(samples.length, Math.ceil(end * rate));
  const out = samples.slice(lo, hi);
  for (const span of bleep) {
    if (span.revealed) continue;
    const a = Math.max(lo, Math.floor(span.start * rate)), b = Math.min(hi, Math.ceil(span.end * rate));
    for (let i = a; i < b; i++) out[i - lo] = 0.25 * Math.sin((2 * Math.PI * 1000 * (i - a)) / rate);
  }
  return out;
}

/** Several clips joined with half a second of silence between them. */
export function joinClips(clips: Float32Array[], rate: number): Float32Array {
  const gap = Math.round(rate / 2);
  const out = new Float32Array(clips.reduce((n, c) => n + c.length, 0) + gap * Math.max(0, clips.length - 1));
  let offset = 0;
  clips.forEach((c, i) => {
    out.set(c, offset);
    offset += c.length + (i < clips.length - 1 ? gap : 0);
  });
  return out;
}
