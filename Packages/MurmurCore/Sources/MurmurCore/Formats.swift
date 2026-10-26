import Foundation

/// Text formats for copying and exporting.
public enum TextFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case plain, timestamps, markdown, srt, vtt, json

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .plain: "Plain text"
        case .timestamps: "Text with timestamps"
        case .markdown: "Markdown"
        case .srt: "SRT subtitles"
        case .vtt: "WebVTT"
        case .json: "JSON (words)"
        }
    }

    public var fileExtension: String {
        switch self {
        case .plain, .timestamps: "txt"
        case .markdown: "md"
        case .srt: "srt"
        case .vtt: "vtt"
        case .json: "json"
        }
    }

    /// The formats offered in the Copy menu.
    public static let copyFormats: [TextFormat] = [.plain, .timestamps, .markdown, .srt]
}

public struct RenderOptions: Sendable, Equatable {
    public var speakerNames = true
    public var hideFillers = true
    /// Times count from the start of each section instead of the start of the file.
    public var relativeTimes = false

    public init(speakerNames: Bool = true, hideFillers: Bool = true, relativeTimes: Bool = false) {
        self.speakerNames = speakerNames
        self.hideFillers = hideFillers
        self.relativeTimes = relativeTimes
    }
}

/// A named part of the recording to render, such as a mark or the selection.
public struct TranscriptSection: Sendable, Equatable {
    public var name: String?
    public var start: Double
    public var end: Double

    public init(name: String? = nil, start: Double, end: Double) {
        self.name = name
        self.start = start
        self.end = end
    }
}

public enum Renderer {
    /// Renders `sections` (the whole file when nil) of `project` as `format`.
    public static func render(_ project: Project, sections: [TranscriptSection]? = nil, format: TextFormat,
                              options: RenderOptions = .init()) -> String {
        let parts = sections ?? [TranscriptSection(start: 0, end: .greatestFiniteMagnitude)]
        let showHeadings = sections != nil && parts.count > 1
        switch format {
        case .json: return json(project, parts, options)
        case .srt, .vtt: return subtitles(project, parts, format: format, options)
        case .plain, .timestamps, .markdown:
            var blocks: [String] = []
            if format == .markdown, let title = project.title, !title.isEmpty { blocks.append("# \(title)") }
            for section in parts {
                let offset = options.relativeTimes ? section.start : 0
                let paragraphs = self.paragraphs(project, section, options)
                if showHeadings || (format == .markdown && section.name != nil) {
                    let range = "\(Timecode.short(section.start)) – \(Timecode.short(section.end))"
                    let name = section.name ?? "Section"
                    blocks.append(format == .markdown ? "## \(name) (\(range))" : "— \(name) (\(range)) —")
                }
                for (speaker, words) in paragraphs {
                    let text = Merge.join(words)
                    let who = project.name(of: speaker)
                    let time = Timecode.short((words.first?.start ?? 0) - offset)
                    switch format {
                    case .markdown:
                        blocks.append(options.speakerNames ? "**\(who)** · \(time)\n\(text)" : "\(time)\n\(text)")
                    case .timestamps:
                        blocks.append(options.speakerNames ? "[\(time)] \(who): \(text)" : "[\(time)] \(text)")
                    default:
                        blocks.append(options.speakerNames ? "\(who): \(text)" : text)
                    }
                }
            }
            return blocks.joined(separator: "\n\n") + "\n"
        }
    }

    /// The words of a section grouped into paragraphs, with fillers dropped when asked.
    static func paragraphs(_ project: Project, _ section: TranscriptSection, _ options: RenderOptions) -> [(Int, [Word])] {
        let range = Merge.indices(of: project.words, from: section.start, to: section.end)
        var words = Array(project.words[range])
        if options.hideFillers { words.removeAll(where: \.isFiller) }
        return Merge.paragraphs(words).map { p in (p.speaker, Array(words[p.range])) }
    }

    static func subtitles(_ project: Project, _ sections: [TranscriptSection], format: TextFormat, _ options: RenderOptions) -> String {
        var cues: [String] = []
        var n = 0
        for section in sections {
            let offset = options.relativeTimes ? section.start : 0
            for (speaker, words) in paragraphs(project, section, options) {
                for chunk in cueChunks(words) {
                    n += 1
                    let start = chunk.first!.start - offset, end = chunk.last!.end - offset
                    let text = Merge.join(chunk)
                    let who = project.name(of: speaker)
                    if format == .srt {
                        cues.append("\(n)\n\(Timecode.srt(start)) --> \(Timecode.srt(end))\n"
                            + (options.speakerNames ? "\(who): \(text)" : text))
                    } else {
                        cues.append("\(Timecode.vtt(start)) --> \(Timecode.vtt(end))\n"
                            + (options.speakerNames ? "<v \(who)>\(text)" : text))
                    }
                }
            }
        }
        let body = cues.joined(separator: "\n\n") + "\n"
        return format == .vtt ? "WEBVTT\n\n" + body : body
    }

    /// Splits a paragraph into subtitle-sized cues: at most ~6 s or ~80 characters.
    static func cueChunks(_ words: [Word]) -> [[Word]] {
        var out: [[Word]] = []
        var cur: [Word] = []
        var chars = 0
        for w in words {
            if let first = cur.first, w.end - first.start > 6 || chars + w.text.count > 80 {
                out.append(cur)
                cur = []
                chars = 0
            }
            cur.append(w)
            chars += w.text.count + 1
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    struct JSONExport: Encodable {
        struct JSpeaker: Encodable { let id: Int; let name: String }
        struct JWord: Encodable { let text: String; let start: Double; let end: Double; let speaker: Int; let filler: Bool }
        struct JSection: Encodable { let name: String?; let start: Double; let end: Double; let words: [JWord] }
        let title: String?
        let language: String?
        let duration: Double
        let speakers: [JSpeaker]
        let sections: [JSection]
    }

    static func json(_ project: Project, _ sections: [TranscriptSection], _ options: RenderOptions) -> String {
        let speakers = project.speakers.map { JSONExport.JSpeaker(id: $0.id, name: $0.displayName) }
        let parts = sections.map { section -> JSONExport.JSection in
            let offset = options.relativeTimes ? section.start : 0
            let range = Merge.indices(of: project.words, from: section.start, to: section.end)
            let words = project.words[range].filter { !(options.hideFillers && $0.isFiller) }.map {
                JSONExport.JWord(text: $0.text, start: round3($0.start - offset), end: round3($0.end - offset),
                                 speaker: $0.speaker, filler: $0.isFiller)
            }
            let end = section.end == .greatestFiniteMagnitude ? project.duration : section.end
            return JSONExport.JSection(name: section.name, start: section.start, end: end, words: words)
        }
        let export = JSONExport(title: project.title, language: project.language, duration: project.duration,
                                speakers: speakers, sections: parts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? String(decoding: encoder.encode(export), as: UTF8.self)) ?? "{}"
    }

    static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}
