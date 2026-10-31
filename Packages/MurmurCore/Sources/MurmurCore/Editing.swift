import Foundation

/// Transcript edits that keep word timings meaningful.
public enum Editing {
    /// Replaces the words of one paragraph with `newText`. Words that survive keep their timing;
    /// new words share the time of what they replaced. Returns the new word list and the range the
    /// paragraph now occupies, so the caller can re-time just those words.
    public static func replace(in words: [Word], range: Range<Int>, with newText: String) -> (words: [Word], range: Range<Int>) {
        guard !range.isEmpty else { return (words, range) }
        let speaker = words[range.lowerBound].speaker
        let replaced = retime(Array(words[range]), newText: newText, speaker: speaker)
        var out = words
        out.replaceSubrange(range, with: replaced)
        return (out, range.lowerBound..<(range.lowerBound + replaced.count))
    }

    /// Lines new text up against the old words (longest common subsequence on normalized text).
    public static func retime(_ old: [Word], newText: String, speaker: Int) -> [Word] {
        let tokens = newText.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return [] }
        guard !old.isEmpty else { return [] }
        let a = old.map { Merge.normalized($0.text) }
        let b = tokens.map(Merge.normalized)
        let pairs = lcs(a, b)

        var out: [Word] = []
        var oi = 0, ti = 0
        for (pi, pj) in pairs + [(old.count, tokens.count)] {
            // New tokens tokens[ti..<pj] replace old words old[oi..<pi].
            if ti < pj {
                let spanStart = oi < pi ? old[oi].start : (oi > 0 ? old[oi - 1].end : old[0].start)
                let spanEnd = oi < pi ? old[pi - 1].end : (pi < old.count ? old[pi].start : old[old.count - 1].end)
                let count = pj - ti
                let length = max(0.12 * Double(count), spanEnd - spanStart)
                let start = spanEnd - spanStart >= length ? spanStart : max(0, (spanStart + spanEnd) / 2 - length / 2)
                for k in 0..<count {
                    let s = start + length * Double(k) / Double(count)
                    out.append(Word(text: tokens[ti + k], start: s, end: s + length / Double(count),
                                    speaker: speaker, edited: true))
                }
            }
            if pi < old.count, pj < tokens.count {
                let o = old[pi]
                out.append(Word(text: tokens[pj], start: o.start, end: o.end, speaker: speaker,
                                isFiller: o.isFiller, edited: o.edited || tokens[pj] != o.text))
            }
            oi = pi + 1
            ti = pj + 1
        }
        return out
    }

    /// Index pairs of a longest common subsequence.
    static func lcs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        let n = a.count, m = b.count
        var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [(Int, Int)] = []
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] { out.append((i, j)); i += 1; j += 1 }
            else if dp[i + 1][j] >= dp[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return out
    }

    /// Moves a range of words to another speaker.
    public static func reassign(_ words: [Word], range: Range<Int>, to speaker: Int) -> [Word] {
        var out = words
        for i in range where out.indices.contains(i) { out[i].speaker = speaker }
        return out
    }

    /// Folds speaker `from` into `into` and drops `from` from the speaker list.
    public static func mergeSpeaker(_ project: Project, from: Int, into: Int) -> Project {
        guard from != into else { return project }
        var p = project
        for i in p.words.indices where p.words[i].speaker == from { p.words[i].speaker = into }
        p.speakers.removeAll { $0.id == from }
        return p
    }

    /// Splits off the words from `index` onward as a new speaker (until the paragraph ends).
    public static func splitToNewSpeaker(_ project: Project, paragraph: Paragraph, from index: Int) -> Project {
        toNewSpeaker(project, range: index..<paragraph.range.upperBound)
    }

    /// Moves a range of words to a new speaker.
    public static func toNewSpeaker(_ project: Project, range: Range<Int>) -> Project {
        var p = project
        let newId = (p.speakers.map(\.id).max() ?? -1) + 1
        p.speakers.append(Speaker(id: newId))
        p.words = reassign(p.words, range: range, to: newId)
        return p
    }

    /// The words a text selection touches, where `characters` are offsets into `Merge.join(words)`.
    /// Offsets are relative to `words`; nil when the selection covers no word (a caret, or only spaces).
    public static func words(_ words: [Word], touching characters: Range<Int>) -> Range<Int>? {
        guard !characters.isEmpty else { return nil }
        var offset = 0, first: Int?, last: Int?
        var previous: Character?
        for (i, word) in words.enumerated() where !word.text.isEmpty {
            if let previous, let c = word.text.first, !(Merge.isUnspaced(previous) && Merge.isUnspaced(c)) { offset += 1 }
            let span = offset..<(offset + word.text.count)
            if span.overlaps(characters) {
                if first == nil { first = i }
                last = i
            }
            offset = span.upperBound
            previous = word.text.last
        }
        guard let first, let last else { return nil }
        return first..<(last + 1)
    }
}
