import Foundation

/// Places overlapping marks on separate rows so their labels never sit on top of each other.
public enum MarkLayout {
    /// The row for each mark: the first row whose previous mark has ended. Marks beyond
    /// `maxRows` get no row (count them as overflow).
    public static func rows(_ marks: [Mark], maxRows: Int = 4) -> [UUID: Int] {
        var rowEnds: [Double] = []
        var out: [UUID: Int] = [:]
        for mark in marks.sorted(by: { ($0.start, $0.end) < ($1.start, $1.end) }) {
            if let row = rowEnds.firstIndex(where: { $0 <= mark.start }) {
                rowEnds[row] = mark.end
                out[mark.id] = row
            } else if rowEnds.count < maxRows {
                rowEnds.append(mark.end)
                out[mark.id] = rowEnds.count - 1
            }
        }
        return out
    }

    public static func rowCount(_ marks: [Mark], maxRows: Int = 4) -> Int {
        max(1, (rows(marks, maxRows: maxRows).values.max() ?? 0) + 1)
    }
}
