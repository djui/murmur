const pad = (n: number, width = 2) => String(n).padStart(width, "0");

/** `mm:ss`, or `h:mm:ss` past an hour. */
export function short(t: number): string {
  const s = Math.floor(Math.max(0, t));
  const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${pad(m)}:${pad(sec)}`;
}

/** `mm:ss.t`, or `h:mm:ss.t` past an hour. */
export function precise(t: number): string {
  const tenths = Math.floor(Math.max(0, t) * 10);
  const s = Math.floor(tenths / 10);
  const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}.${tenths % 10}` : `${pad(m)}:${pad(sec)}.${tenths % 10}`;
}

export const srt = (t: number) => clock(t, ",");
export const vtt = (t: number) => clock(t, ".");

function clock(t: number, separator: string): string {
  const ms = Math.round(Math.max(0, t) * 1000);
  const h = Math.floor(ms / 3_600_000), m = Math.floor(ms / 60_000) % 60, s = Math.floor(ms / 1000) % 60;
  return `${pad(h)}:${pad(m)}:${pad(s)}${separator}${pad(ms % 1000, 3)}`;
}
