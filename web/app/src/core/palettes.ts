// Speaker color schemes as [light, dark] sRGB hex pairs. All but Vivid are MurmurCore's
// SpeakerPalettes, whose tests check contrast (≥3:1) and that speakers stay apart (OKLab). Vivid is
// the Mac app's set of system colors.

export type SchemeId = "vivid" | "ink" | "carbon" | "tableau" | "slate" | "calm" | "colorBlind" | "highContrast" | "earth";

export const palettes: Record<Exclude<SchemeId, "vivid">, [string, string][]> = {
  ink: [["1F3A5F", "8FB0DA"], ["4A6FA5", "6F9BD8"], ["2A7F7F", "5CC2BE"], ["7A2E3B", "E08A97"], ["5B5F66", "B7BCC4"], ["8A6A2A", "D9B66A"]],
  carbon: [["6929C4", "A56EFF"], ["1180C8", "33B1FF"], ["005D5D", "08BDBA"], ["9F1853", "FF7EB6"], ["A2191F", "FA4D56"], ["198038", "6FDC8C"]],
  tableau: [["4E79A7", "7EA6D6"], ["C56A12", "F28E2B"], ["C63D40", "FF7B7E"], ["3F8737", "7FC36F"], ["8F5A84", "D6A0C8"], ["2F8C88", "8FD0CB"]],
  slate: [["0B3C5D", "A8CCEA"], ["2A7AB0", "4F9AD8"], ["6F7F8C", "8A9AA8"], ["2B2F33", "E2E6EA"], ["3F8FA0", "62BFD0"], ["5A4E8C", "9A8FD0"]],
  calm: [["3F6FB5", "7FA6E0"], ["4E8F5E", "8CC79A"], ["B07A2E", "E0B070"], ["6E7380", "A9AEBA"], ["7C5DA6", "B79BDA"], ["A65252", "E08A8A"]],
  colorBlind: [["0072B2", "56B4E9"], ["B07800", "E69F00"], ["00876A", "2BC79A"], ["A8508A", "E8A3C8"], ["857A00", "F0E442"], ["C05000", "F07A2A"]],
  highContrast: [["0040E0", "7AA8FF"], ["C40000", "FF6666"], ["006B00", "4CDB4C"], ["1A1A1A", "F2F2F2"], ["7A00B0", "D08CFF"], ["8A5A00", "FFC24A"]],
  earth: [["8A5A3B", "C8916C"], ["5F6E2E", "A3B565"], ["3D6A7A", "76A7B8"], ["8C6C1C", "E0BC5C"], ["7A4B6A", "B984A8"], ["4A463E", "C9C2B2"]],
};

/** macOS system colors: purple, orange, teal, pink, green, brown, indigo, mint, cyan, yellow. */
const vivid: [string, string][] = [
  ["AF52DE", "BF5AF2"], ["FF9500", "FF9F0A"], ["30B0C7", "40C8E0"], ["FF2D55", "FF375F"], ["34C759", "30D158"],
  ["A2845E", "AC8E68"], ["5856D6", "5E5CE6"], ["00C7BE", "63E6E2"], ["32ADE6", "64D2FF"], ["FFCC00", "FFD60A"],
];

export const schemes: { id: SchemeId; title: string; note: string; hatched: boolean }[] = [
  { id: "vivid", title: "Vivid", note: "Bright system colors", hatched: false },
  { id: "ink", title: "Ink", note: "Navy, steel, teal, burgundy and graphite", hatched: false },
  { id: "carbon", title: "Carbon", note: "IBM Carbon's categorical palette", hatched: false },
  { id: "tableau", title: "Tableau", note: "Tableau 10, the business-chart standard", hatched: false },
  { id: "slate", title: "Slate", note: "Blues and greys, striped lanes for every other speaker", hatched: true },
  { id: "calm", title: "Calm", note: "Muted blues and greens", hatched: false },
  { id: "colorBlind", title: "Color-blind safe", note: "Okabe–Ito, distinct for the common kinds of color blindness", hatched: false },
  { id: "highContrast", title: "High contrast", note: "Strong colors, striped lanes for every other speaker", hatched: true },
  { id: "earth", title: "Earth", note: "Browns, olives and slate", hatched: false },
];

export function colors(id: SchemeId): [string, string][] {
  return id === "vivid" ? vivid : palettes[id];
}

/** The color of speaker `index` in light or dark mode, as `#rrggbb`. */
export function speakerColor(id: SchemeId, index: number, dark: boolean): string {
  const c = colors(id);
  return "#" + c[((index % c.length) + c.length) % c.length][dark ? 1 : 0];
}

/** Speakers past the first round of colors reuse them; those get striped lanes. */
export function isHatched(id: SchemeId, index: number): boolean {
  const scheme = schemes.find((s) => s.id === id)!;
  const repeat = Math.floor(index / colors(id).length) % 2 === 1;
  return (scheme.hatched && index % 2 === 1) !== repeat;
}
