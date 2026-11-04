// The waveform as one peak per bin. Float32 like MurmurCore's, so both draw the same shape.

export const BINS_PER_SECOND = 100;

export function compute(samples: Float32Array | number[], sampleRate: number, binsPerSecond = BINS_PER_SECOND): Float32Array {
  const size = Math.max(1, Math.floor(sampleRate / binsPerSecond));
  const count = Math.ceil(samples.length / size);
  const out = new Float32Array(count);
  for (let bin = 0; bin < count; bin++) {
    let peak = 0;
    const end = Math.min(samples.length, (bin + 1) * size);
    for (let i = bin * size; i < end; i++) {
      const v = Math.abs(samples[i]);
      if (v > peak) peak = v;
    }
    out[bin] = peak;
  }
  return out;
}

/** Scales so the loudest 0.5 % of bins reach 1, so quiet recordings still draw a shape. */
export function normalize(peaks: Float32Array): Float32Array {
  if (peaks.length === 0) return peaks;
  const sorted = Float32Array.from(peaks).sort();
  const ref = Math.max(Math.fround(0.01), sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.995))]);
  return peaks.map((p) => Math.min(1, Math.fround(p / ref)));
}

/** The highest peak between two times. */
export function peakIn(peaks: Float32Array, start: number, end: number, binsPerSecond = BINS_PER_SECOND): number {
  if (peaks.length === 0) return 0;
  const lo = Math.max(0, Math.floor(start * binsPerSecond));
  const hi = Math.min(peaks.length, Math.max(lo + 1, Math.ceil(end * binsPerSecond)));
  let m = 0;
  for (let i = lo; i < hi; i++) if (peaks[i] > m) m = peaks[i];
  return m;
}

/**
 * How loud a stretch is, for one waveform bar: the mean of its bins' peaks. A bar over a few seconds of
 * talk with pauses stays below a bar of solid talk, and silence stays low. One bin per bar: the peak itself.
 */
export function levelIn(peaks: Float32Array, start: number, end: number, binsPerSecond = BINS_PER_SECOND): number {
  if (peaks.length === 0) return 0;
  const lo = Math.max(0, Math.floor(start * binsPerSecond));
  const hi = Math.min(peaks.length, Math.max(lo + 1, Math.ceil(end * binsPerSecond)));
  if (lo >= hi) return 0;
  let sum = 0;
  for (let i = lo; i < hi; i++) sum += peaks[i];
  return sum / (hi - lo);
}

/**
 * Height (0...1) of the waveform bar for `start..end`. Zoomed in, a 36 dB scale gives quiet syllables shape;
 * zoomed out, the range narrows to 24 dB so solid talk, talk with pauses and silence come apart.
 */
export function barHeight(peaks: Float32Array, start: number, end: number, binsPerSecond = BINS_PER_SECOND): number {
  const bins = Math.max(1, (end - start) * binsPerSecond);
  const range = 36 - 12 * Math.min(1, Math.log10(bins) / 2);
  return loudness(levelIn(peaks, start, end, binsPerSecond), range);
}

/** Bar height for a peak on a loudness (decibel) scale over `range` dB. */
export function loudness(peak: number, range = 36): number {
  if (peak <= 0) return 0;
  const db = Math.fround(20 * Math.fround(Math.log10(Math.min(1, peak))));
  return Math.max(0, Math.min(1, Math.fround((db + range) / range)));
}
