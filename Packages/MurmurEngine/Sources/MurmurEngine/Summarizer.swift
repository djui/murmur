import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A short title and summary for a transcript, from Apple's on-device language model.
public enum Summarizer {
    public static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    public struct Card: Sendable {
        public var title: String
        public var summary: String
    }

    public static func card(for transcript: String) async throws -> Card? {
        #if canImport(FoundationModels)
        guard isAvailable, !transcript.isEmpty else { return nil }
        // Keep well inside the model's context window.
        let passage = String(transcript.prefix(6000))
        let session = LanguageModelSession(instructions: """
            You write factual titles and summaries for transcripts of meetings and conversations. \
            Use the language of the transcript. No emoji, no hype, no quotes around the title.
            """)
        let prompt = """
            Write a title of 3 to 8 words and a summary of one or two sentences for this transcript.
            Answer exactly in this form:
            Title: <title>
            Summary: <summary>

            TRANSCRIPT:
            \(passage)
            """
        let reply = try await session.respond(to: prompt).content
        return parse(reply)
        #else
        return nil
        #endif
    }

    public static func parse(_ reply: String) -> Card? {
        var title = "", summary = ""
        for line in reply.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.lowercased().hasPrefix("title:") { title = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            else if s.lowercased().hasPrefix("summary:") { summary = String(s.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
            else if !summary.isEmpty { summary += " " + s }
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”*#"))
        guard !title.isEmpty else { return nil }
        return Card(title: title, summary: summary)
    }
}
