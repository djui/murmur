import Foundation

/// The part of a recording that counts: the start and end the user trimmed it to. The media is never cut;
/// the words and marks outside are kept here so the trim can be taken off again.
public struct Trim: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    /// Words outside `start...end`, by their midpoint.
    public var words: [Word]
    /// Marks wholly outside `start...end`.
    public var marks: [Mark]

    public init(start: Double, end: Double, words: [Word] = [], marks: [Mark] = []) {
        self.start = start
        self.end = end
        self.words = words
        self.marks = marks
    }
}

extension Project {
    /// The stretch that plays, shows and exports: the trim, or the whole file.
    public var span: ClosedRange<Double> {
        if let trim { return trim.start...max(trim.start, trim.end) }
        return 0...max(0, duration)
    }

    /// Trims to `range` (clamped to the file), taking any earlier trim off first. Words whose middle falls
    /// outside and marks wholly outside move into the trim; marks across an edge are cut at it.
    public mutating func trim(to range: ClosedRange<Double>) {
        removeTrim()
        let lo = max(0, range.lowerBound), hi = duration > 0 ? min(duration, range.upperBound) : range.upperBound
        guard hi > lo else { return }
        var trim = Trim(start: lo, end: hi)
        var kept: [Word] = []
        for word in words {
            if word.mid < lo || word.mid > hi { trim.words.append(word) } else { kept.append(word) }
        }
        var keptMarks: [Mark] = []
        for var mark in marks {
            if mark.end <= lo || mark.start >= hi {
                trim.marks.append(mark)
            } else {
                mark.start = max(mark.start, lo)
                mark.end = min(mark.end, hi)
                keptMarks.append(mark)
            }
        }
        words = kept
        marks = keptMarks
        self.trim = trim
    }

    /// Takes the trim off: the whole file again, with the words and marks that were outside put back.
    public mutating func removeTrim() {
        guard let trim else { return }
        words = (words + trim.words).enumerated()
            .sorted { $0.element.start == $1.element.start ? $0.offset < $1.offset : $0.element.start < $1.element.start }
            .map(\.element)
        marks = (marks + trim.marks).sorted { $0.start < $1.start }
        self.trim = nil
    }
}
