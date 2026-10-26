import Foundation

/// Everything Murmur knows about one recording. Stored as `project.json` inside a `.murmur` package.
public struct Project: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case new, processing, ready, failed }

    public var formatVersion = 1
    public var id = UUID()
    public var status: Status = .new
    public var media: MediaRef?
    public var duration: Double = 0
    /// ISO 639-1 code of the spoken language.
    public var language: String?
    public var languageConfidence: Double?
    /// Set when the text-language check disagrees with the spoken-language check.
    public var languageWarning: String?
    /// "voz" or "apple".
    public var transcriber: String?
    public var title: String?
    public var summary: String?
    /// True while `title` is still the generated one.
    public var titleIsGenerated = false
    public var speakers: [Speaker] = []
    public var words: [Word] = []
    public var marks: [Mark] = []
    /// Personal details found by the redaction model; shown hidden while `settings.redact` is on.
    public var redactions: [RedactedSpan]?
    public var settings = ProjectSettings()
    public var createdAt = Date()
    public var processedAt: Date?
    public var failure: String?

    public init() {}

    public func speaker(_ id: Int) -> Speaker? { speakers.first { $0.id == id } }

    public func name(of id: Int) -> String {
        speaker(id)?.displayName ?? "Speaker \(id + 1)"
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return media.map { URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent } ?? "Untitled"
    }

    /// Talk time per speaker id, from word spans.
    public var talkTime: [Int: Double] {
        var out: [Int: Double] = [:]
        for p in Merge.paragraphs(words) { out[p.speaker, default: 0] += p.end - p.start }
        return out
    }
}

/// Where the audio or video lives. Media is referenced, never copied.
public struct MediaRef: Codable, Sendable, Equatable {
    public var path: String
    public var bookmark: Data?
    public var hasVideo: Bool
    public var fileSize: Int64?
    /// For recordings: the microphone track ("Me").
    public var micStem: String?
    /// For recordings: the system-audio track ("Others").
    public var systemStem: String?

    public init(path: String, bookmark: Data? = nil, hasVideo: Bool = false, fileSize: Int64? = nil,
                micStem: String? = nil, systemStem: String? = nil) {
        self.path = path
        self.bookmark = bookmark
        self.hasVideo = hasVideo
        self.fileSize = fileSize
        self.micStem = micStem
        self.systemStem = systemStem
    }

    public var isRecording: Bool { micStem != nil || systemStem != nil }
}

public struct ProjectSettings: Codable, Sendable, Equatable {
    /// Play, transcribe and export the Clear-enhanced audio.
    public var enhance = false
    /// Show filler words (faded) in the editor.
    public var showFillers = true
    public var showVideo = true
    /// Hide personal details in the transcript, copies, exports and clips. Optional so older
    /// project files still open.
    public var redact: Bool?

    public init() {}
}

public struct Speaker: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var name: String
    /// The microphone owner in a recording.
    public var isMe: Bool

    public init(id: Int, name: String = "", isMe: Bool = false) {
        self.id = id
        self.name = name
        self.isMe = isMe
    }

    public var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return isMe ? "Me" : "Speaker \(id + 1)"
    }
}

public struct Word: Codable, Sendable, Equatable {
    public var text: String
    public var start: Double
    public var end: Double
    public var speaker: Int
    public var isFiller: Bool
    /// Typed by the user rather than heard by the transcriber.
    public var edited: Bool

    public init(text: String, start: Double, end: Double, speaker: Int = 0,
                isFiller: Bool = false, edited: Bool = false) {
        self.text = text
        self.start = start
        self.end = max(start, end)
        self.speaker = speaker
        self.isFiller = isFiller
        self.edited = edited
    }

    public var mid: Double { (start + end) / 2 }
}

public struct Mark: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var start: Double
    public var end: Double

    public init(id: UUID = UUID(), name: String, start: Double, end: Double) {
        self.id = id
        self.name = name
        self.start = min(start, end)
        self.end = max(start, end)
    }

    public var duration: Double { end - start }
}

/// A stretch of speech holding a personal detail (a name, phone number, address…).
public struct RedactedSpan: Codable, Sendable, Equatable {
    public var start: Double
    public var end: Double
    /// Short category, such as "name" or "phone".
    public var category: String
    public var original: String
    /// Shown anyway, because the person chose to un-redact it.
    public var revealed: Bool

    public init(start: Double, end: Double, category: String, original: String, revealed: Bool = false) {
        self.start = start
        self.end = end
        self.category = category
        self.original = original
        self.revealed = revealed
    }
}

/// A run of words by one speaker, shown as one block in the transcript.
public struct Paragraph: Sendable, Equatable, Identifiable {
    public var id: Int { range.lowerBound }
    public let speaker: Int
    public let range: Range<Int>
    public let start: Double
    public let end: Double

    public init(speaker: Int, range: Range<Int>, start: Double, end: Double) {
        self.speaker = speaker
        self.range = range
        self.start = start
        self.end = end
    }
}

public extension Project {
    private static let dateStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    static func decode(_ data: Data) throws -> Project {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            return try (try? dateStyle.parse(string)) ?? Date.ISO8601FormatStyle().parse(string)
        }
        return try decoder.decode(Project.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Self.dateStyle))
        }
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
