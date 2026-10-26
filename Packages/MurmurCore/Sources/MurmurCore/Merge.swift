import Foundation

/// A stretch of time attributed to one speaker by the diarizer.
public struct SpeakerTurn: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let speaker: Int

    public init(start: Double, end: Double, speaker: Int) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

/// A filler sound (um, uh) found by the filler detector.
public struct FillerSpan: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let label: String

    public init(start: Double, end: Double, label: String = "um") {
        self.start = start
        self.end = end
        self.label = label
    }
}

/// Joining transcriber words, diarizer turns and filler detections into one word list.
public enum Merge {
    /// Gives each word the speaker whose turn overlaps it most (the nearest turn when none does),
    /// then renumbers speakers from `firstId` in order of first appearance.
    public static func assign(_ words: [Word], turns: [SpeakerTurn], firstId: Int = 0) -> [Word] {
        guard !turns.isEmpty else { return words.map { var w = $0; w.speaker = firstId; return w } }
        let sorted = turns.sorted { $0.start < $1.start }
        var raw = words.map { word -> Word in
            var best = -1
            var bestOverlap = 0.0
            var nearest = sorted[0].speaker
            var nearestDistance = Double.infinity
            for turn in sorted {
                if turn.start > word.end + 30 { break }
                let overlap = min(word.end, turn.end) - max(word.start, turn.start)
                if overlap > bestOverlap {
                    bestOverlap = overlap
                    best = turn.speaker
                }
                let distance = word.mid < turn.start ? turn.start - word.mid
                    : word.mid > turn.end ? word.mid - turn.end : 0
                if distance < nearestDistance {
                    nearestDistance = distance
                    nearest = turn.speaker
                }
            }
            var w = word
            w.speaker = best >= 0 ? best : nearest
            return w
        }
        var order: [Int: Int] = [:]
        for w in raw where order[w.speaker] == nil { order[w.speaker] = firstId + order.count }
        for i in raw.indices { raw[i].speaker = order[raw[i].speaker] ?? firstId }
        return raw
    }

    /// Groups words into paragraphs: a new one starts at a speaker change, a pause longer than
    /// `maxGap`, or at a sentence end once a paragraph runs longer than `maxLength` seconds.
    public static func paragraphs(_ words: [Word], maxGap: Double = 1.5, maxLength: Double = 45) -> [Paragraph] {
        guard !words.isEmpty else { return [] }
        var out: [Paragraph] = []
        var startIndex = 0
        func close(_ end: Int) {
            guard end > startIndex else { return }
            out.append(Paragraph(speaker: words[startIndex].speaker, range: startIndex..<end,
                                 start: words[startIndex].start, end: words[end - 1].end))
            startIndex = end
        }
        for i in 1..<words.count {
            let prev = words[i - 1], cur = words[i]
            let long = prev.end - words[startIndex].start > maxLength && endsSentence(prev.text)
            if cur.speaker != prev.speaker || cur.start - prev.end > maxGap || long { close(i) }
        }
        close(words.count)
        return out
    }

    /// Drops microphone words that are the remote side leaking into an open mic: the same word
    /// heard on the system track within `tolerance` seconds.
    public static func removeEcho(mic: [Word], system: [Word], tolerance: Double = 0.6) -> [Word] {
        guard !system.isEmpty else { return mic }
        let sys = system.sorted { $0.start < $1.start }
        var j = 0
        return mic.filter { word in
            while j < sys.count && sys[j].start < word.start - tolerance { j += 1 }
            var k = j
            let key = normalized(word.text)
            while k < sys.count && sys[k].start <= word.start + tolerance {
                if normalized(sys[k].text) == key { return false }
                k += 1
            }
            return true
        }
    }

    /// Marks words that are mostly inside a filler, and inserts a filler word where the
    /// transcriber left the sound out.
    public static func markFillers(_ words: [Word], fillers: [FillerSpan]) -> [Word] {
        var out = words
        var inserted: [Word] = []
        for filler in fillers {
            let length = max(0.001, filler.end - filler.start)
            var covered = false
            for i in out.indices where out[i].end > filler.start && out[i].start < filler.end {
                let overlap = min(out[i].end, filler.end) - max(out[i].start, filler.start)
                let wordLength = max(0.001, out[i].end - out[i].start)
                if overlap / wordLength > 0.5 {
                    out[i].isFiller = true
                    covered = true
                } else if overlap / length > 0.2 {
                    covered = true
                }
            }
            if !covered {
                let speaker = nearest(to: (filler.start + filler.end) / 2, in: out)?.speaker ?? 0
                inserted.append(Word(text: filler.label, start: filler.start, end: filler.end,
                                     speaker: speaker, isFiller: true))
            }
        }
        // Insert fillers by time without reordering the transcript itself.
        for filler in inserted.sorted(by: { $0.start < $1.start }) {
            let index = out.firstIndex { $0.start > filler.start } ?? out.endIndex
            out.insert(filler, at: index)
        }
        return out
    }

    /// Joins words with spaces, except between characters of scripts written without them
    /// (Chinese, Japanese, Thai).
    public static func join(_ texts: [String]) -> String {
        var out = ""
        for text in texts where !text.isEmpty {
            if let last = out.last, let first = text.first, !(isUnspaced(last) && isUnspaced(first)) { out += " " }
            out += text
        }
        return out
    }

    public static func join(_ words: some Sequence<Word>) -> String { join(words.map(\.text)) }

    public static func isUnspaced(_ c: Character) -> Bool {
        guard let v = c.unicodeScalars.first?.value else { return false }
        return (0x3000...0x30FF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x4E00...0x9FFF).contains(v)
            || (0xFF00...0xFFEF).contains(v) || (0x0E00...0x0E7F).contains(v)
    }

    /// Keeps word starts in transcript order after re-timing, so nothing swaps places.
    public static func monotonic(_ words: [Word]) -> [Word] {
        var out = words
        for i in out.indices.dropFirst() where out[i].start < out[i - 1].start {
            out[i].start = out[i - 1].start
            out[i].end = max(out[i].end, out[i].start)
        }
        return out
    }

    public static func nearest(to time: Double, in words: [Word]) -> Word? {
        words.min { abs($0.mid - time) < abs($1.mid - time) }
    }

    /// Lowercased with punctuation removed, for comparing words.
    public static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".?!…".contains(last)
    }

    /// Words whose midpoint lies inside `start...end`: cuts snap to whole words.
    public static func indices(of words: [Word], from start: Double, to end: Double) -> Range<Int> {
        let lo = words.firstIndex { $0.mid >= start } ?? words.count
        let hi = words.lastIndex { $0.mid <= end }.map { $0 + 1 } ?? lo
        return lo..<max(lo, hi)
    }
}
