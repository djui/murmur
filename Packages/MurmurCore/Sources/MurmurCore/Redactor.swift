import Foundation

public enum RedactionStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case labels, bars, initials

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .labels: "Labels, like [name]"
        case .bars: "Black bars"
        case .initials: "Initials for names"
        }
    }
}

/// Applying redactions to words, and mapping text ranges found by the model back to words.
public enum Redactor {
    /// The hidden span a word falls in, if any.
    public static func span(for word: Word, in spans: [RedactedSpan]) -> RedactedSpan? {
        spans.first { !$0.revealed && word.mid >= $0.start && word.mid <= $0.end }
    }

    public static func replacement(for span: RedactedSpan, style: RedactionStyle) -> String {
        switch style {
        case .labels:
            return "[\(span.category)]"
        case .bars:
            return String(repeating: "█", count: max(3, min(12, span.original.count)))
        case .initials:
            guard span.category == "name" else { return "[\(span.category)]" }
            return span.original.split(separator: " ").compactMap { $0.first.map { "\($0)." } }.joined(separator: " ")
        }
    }

    /// Words with each hidden span collapsed into one replacement word.
    public static func apply(_ words: [Word], spans: [RedactedSpan], style: RedactionStyle) -> [Word] {
        guard spans.contains(where: { !$0.revealed }) else { return words }
        var out: [Word] = []
        var current: RedactedSpan?
        for word in words {
            if let span = span(for: word, in: spans) {
                // Keep the punctuation that followed the hidden words.
                let tail = String(word.text.reversed().prefix { ".,;:!?".contains($0) }.reversed())
                if span == current, var last = out.popLast() {
                    last.end = word.end
                    last.text = replacement(for: span, style: style) + tail
                    out.append(last)
                } else {
                    out.append(Word(text: replacement(for: span, style: style) + tail, start: word.start, end: word.end,
                                    speaker: word.speaker, edited: true))
                }
                current = span
            } else {
                out.append(word)
                current = nil
            }
        }
        return out
    }

    /// The text the model reads for a run of words, and each word's character range in it.
    public static func text(of words: [Word]) -> (String, [Range<Int>]) {
        var text = ""
        var ranges: [Range<Int>] = []
        for word in words where !word.text.isEmpty {
            if let last = text.last, let first = word.text.first, !(Merge.isUnspaced(last) && Merge.isUnspaced(first)) {
                text += " "
            }
            let start = text.count
            text += word.text
            ranges.append(start..<text.count)
        }
        return (text, ranges)
    }

    /// Turns a character range found in `text(of:)` back into a time span over the words it covers.
    public static func span(words: [Word], ranges: [Range<Int>], chars: Range<Int>, category: String,
                            original: String) -> RedactedSpan? {
        let hit = ranges.indices.filter { ranges[$0].overlaps(chars) }
        guard let first = hit.first, let last = hit.last else { return nil }
        return RedactedSpan(start: words[first].start, end: words[last].end, category: category, original: original)
    }
}
