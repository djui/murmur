import Foundation
import Testing
@testable import MurmurCore

@Suite struct RedactionTests {
    let words = [
        Word(text: "Call", start: 0, end: 0.3), Word(text: "Priya", start: 0.4, end: 0.7),
        Word(text: "Shah", start: 0.8, end: 1.1), Word(text: "today.", start: 1.2, end: 1.5),
    ]

    @Test func charRangesMapBackToWords() {
        let (text, ranges) = Redactor.text(of: words)
        #expect(text == "Call Priya Shah today.")
        let span = Redactor.span(words: words, ranges: ranges, chars: 5..<15, category: "name", original: "Priya Shah")
        #expect(span?.start == 0.4 && span?.end == 1.1)
    }

    @Test func styles() {
        let span = RedactedSpan(start: 0.4, end: 1.1, category: "name", original: "Priya Shah")
        #expect(Redactor.apply(words, spans: [span], style: .labels).map(\.text) == ["Call", "[name]", "today."])
        #expect(Redactor.apply(words, spans: [span], style: .initials).map(\.text) == ["Call", "P. S.", "today."])
        let comma = [Word(text: "with", start: 0, end: 0.2), Word(text: "Jonas,", start: 0.3, end: 0.6)]
        let jonas = RedactedSpan(start: 0.3, end: 0.6, category: "name", original: "Jonas")
        #expect(Redactor.apply(comma, spans: [jonas], style: .labels).map(\.text) == ["with", "[name],"])
        #expect(Redactor.apply(words, spans: [span], style: .bars)[1].text == "██████████")
        var shown = span
        shown.revealed = true
        #expect(Redactor.apply(words, spans: [shown], style: .labels).count == 4)
    }

    @Test func rendererRedactsWhenOn() {
        var p = Project()
        p.speakers = [Speaker(id: 0, name: "Maya")]
        p.words = words
        p.redactions = [RedactedSpan(start: 0.4, end: 1.1, category: "name", original: "Priya Shah")]
        #expect(Renderer.render(p, format: .plain) == "Maya: Call Priya Shah today.\n")
        p.settings.redact = true
        #expect(Renderer.render(p, format: .plain) == "Maya: Call [name] today.\n")
    }

    @Test func oldProjectFilesStillOpen() throws {
        let json = #"{"settings":{"enhance":false,"showFillers":true,"showVideo":true}}"#
        let settings = try JSONDecoder().decode(ProjectSettings.self, from: Data(json.utf8).subdata(in: 12..<(json.utf8.count - 1)))
        #expect(settings.redact == nil)
    }

    @Test func overlappingMarksGetRows() {
        let a = Mark(name: "a", start: 0, end: 10), b = Mark(name: "b", start: 5, end: 8)
        let c = Mark(name: "c", start: 9, end: 12), d = Mark(name: "d", start: 11, end: 20)
        let rows = MarkLayout.rows([a, b, c, d])
        #expect(rows[a.id] == 0 && rows[b.id] == 1 && rows[c.id] == 1 && rows[d.id] == 0)
        #expect(MarkLayout.rowCount([a, b, c, d]) == 2)
    }

    @Test func loudnessLiftsQuietSpeech() {
        #expect(Peaks.loudness(1) == 1)
        #expect(Peaks.loudness(0.1) > 0.4)
        #expect(Peaks.loudness(0.001) == 0)
    }
}
