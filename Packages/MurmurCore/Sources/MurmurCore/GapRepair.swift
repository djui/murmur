import Foundation

/// Words the transcriber skipped, found again. When Voz is unsure of a word it emits nothing, so a soft
/// word at the end of a phrase ("es fällt dir gar nicht auf", with a piano under it) leaves a gap that
/// still holds speech-level sound. Read again with a few seconds of the phrase before it, the word comes
/// back; read from inside the gap, it does not. So each such gap is re-read with that context, and only
/// the new words inside the gap are kept, and only when the context the second reading heard ends on
/// the same word the transcript does.
public enum GapRepair {
    public struct Gap: Sendable, Equatable {
        /// Index of the word before the gap.
        public let after: Int
        /// Where the gap starts (that word's end) and ends (the next word's start, or the file's end).
        public let start: Double
        public let end: Double
        /// What to read again: a few seconds of the phrase before the gap, then the gap.
        public let windowStart: Double
        public let windowEnd: Double
    }

    /// Shorter pauses are breaths and commas.
    public static let minimumGap = 1.0
    /// How loud a gap must be, against the transcript's typical word, to hold speech worth reading again.
    public static let minimumLevel: Float = 0.35
    /// Context read before the gap. Measured on a sung line: 12, 8 and 5 s of context recovered the word,
    /// none (the read starting inside the gap) did not.
    public static let context = 5.0
    /// Longest stretch read again at once; a long gap is read from its start, where a dropped phrase
    /// ending sits.
    public static let maximumWindow = 14.0

    /// Gaps between words that hold speech-level sound, by `peaks` (from `Peaks.compute`, normalized).
    public static func gaps(in words: [Word], duration: Double, peaks: [Float],
                            binsPerSecond: Int = Peaks.binsPerSecond) -> [Gap] {
        guard !words.isEmpty, !peaks.isEmpty else { return [] }
        let levels = words.map { level(peaks, from: $0.start, to: $0.end, binsPerSecond: binsPerSecond) }.sorted()
        let typical = levels[levels.count / 2]
        guard typical > 0 else { return [] }
        var out: [Gap] = []
        for i in words.indices {
            let start = words[i].end
            let end = i + 1 < words.count ? words[i + 1].start : duration
            guard end - start >= minimumGap,
                  level(peaks, from: start + 0.05, to: end - 0.05, binsPerSecond: binsPerSecond) >= minimumLevel * typical
            else { continue }
            // The window starts on a word, so the context is whole words.
            let first = words[...i].firstIndex { $0.start >= start - context } ?? i
            let windowStart = max(0, words[first].start - 0.15)
            let windowEnd = min(duration, end + 0.3, windowStart + maximumWindow)
            out.append(Gap(after: i, start: start, end: end, windowStart: windowStart, windowEnd: windowEnd))
        }
        return out
    }

    /// The loudness of a stretch: the 75th percentile of its peaks, so one short word in a pause counts.
    static func level(_ peaks: [Float], from start: Double, to end: Double, binsPerSecond: Int) -> Float {
        let lo = max(0, Int(start * Double(binsPerSecond)))
        let hi = min(peaks.count, Int((end * Double(binsPerSecond)).rounded(.up)))
        guard lo < hi else { return 0 }
        let sorted = peaks[lo..<hi].sorted()
        return sorted[min(sorted.count - 1, sorted.count * 3 / 4)]
    }

    /// `words` with what a second reading of `gap` heard inside it, or nil when it heard nothing new
    /// there, or its context doesn't end on the word before the gap. `heard` is in file time.
    public static func splice(_ words: [Word], gap: Gap, heard: [Word]) -> [Word]? {
        guard words.indices.contains(gap.after) else { return nil }
        let before = Merge.normalized(words[gap.after].text)
        guard !before.isEmpty,
              let anchor = heard.lastIndex(where: { Merge.normalized($0.text) == before && $0.mid <= gap.start + 0.5 })
        else { return nil }
        let speaker = words[gap.after].speaker
        let new = heard[(anchor + 1)...]
            .filter { $0.mid > gap.start && $0.mid < gap.end - 0.05 && !Merge.normalized($0.text).isEmpty }
            .map { Word(text: $0.text, start: max($0.start, gap.start), end: min($0.end, gap.end), speaker: speaker) }
        guard !new.isEmpty else { return nil }
        var out = words
        out.insert(contentsOf: new, at: gap.after + 1)
        return out
    }
}
