import type { Mark } from "./project";

/** Places overlapping marks on separate rows so their labels never sit on top of each other. The row
 *  for each mark id: the first row whose previous mark has ended. Marks beyond `maxRows` get none. */
export function markRows(marks: Mark[], maxRows = 4): Map<string, number> {
  const rowEnds: number[] = [];
  const out = new Map<string, number>();
  const sorted = [...marks].sort((a, b) => a.start - b.start || a.end - b.end);
  for (const mark of sorted) {
    const row = rowEnds.findIndex((end) => end <= mark.start);
    if (row >= 0) {
      rowEnds[row] = mark.end;
      out.set(mark.id, row);
    } else if (rowEnds.length < maxRows) {
      rowEnds.push(mark.end);
      out.set(mark.id, rowEnds.length - 1);
    }
  }
  return out;
}

export function markRowCount(marks: Mark[], maxRows = 4): number {
  return Math.max(1, Math.max(-1, ...markRows(marks, maxRows).values()) + 1);
}
