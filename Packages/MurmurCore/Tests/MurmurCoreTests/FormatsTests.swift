import Foundation
import Testing
@testable import MurmurCore

@Suite struct FormatsTests {
    var project: Project {
        var p = Project()
        p.title = "Sync"
        p.duration = 10
        p.speakers = [Speaker(id: 0, name: "Maya"), Speaker(id: 1, isMe: true)]
        p.words = [
            Word(text: "Hello", start: 0, end: 0.4, speaker: 0),
            Word(text: "um", start: 0.5, end: 0.7, speaker: 0, isFiller: true),
            Word(text: "there.", start: 0.8, end: 1.2, speaker: 0),
            Word(text: "Hi!", start: 2.0, end: 2.3, speaker: 1),
        ]
        return p
    }

    @Test func plainHidesFillers() {
        let out = Renderer.render(project, format: .plain)
        #expect(out == "Maya: Hello there.\n\nMe: Hi!\n")
    }

    @Test func timestampsKeepFillersWhenAsked() {
        let out = Renderer.render(project, format: .timestamps, options: RenderOptions(hideFillers: false))
        #expect(out == "[00:00] Maya: Hello um there.\n\n[00:02] Me: Hi!\n")
    }

    @Test func markdownSectionsHaveHeadings() {
        let sections = [TranscriptSection(name: "Greeting", start: 0, end: 1.5), TranscriptSection(name: "Reply", start: 1.5, end: 3)]
        let out = Renderer.render(project, sections: sections, format: .markdown)
        #expect(out.contains("# Sync"))
        #expect(out.contains("## Greeting (00:00 – 00:01)"))
        #expect(out.contains("**Me** · 00:02\nHi!"))
    }

    @Test func summaryInMarkdownAndJSON() {
        var p = project
        p.summary = "Maya says hello."
        #expect(Renderer.render(p, format: .markdown).hasPrefix("# Sync\n\n> Maya says hello.\n\n"))
        #expect(Renderer.render(p, format: .json).contains("\"summary\" : \"Maya says hello.\""))
    }

    @Test func relativeTimes() {
        let out = Renderer.render(project, sections: [TranscriptSection(start: 1.5, end: 3)], format: .timestamps,
                                  options: RenderOptions(relativeTimes: true))
        #expect(out == "[00:00] Me: Hi!\n")
    }

    @Test func srtAndVtt() {
        let srt = Renderer.render(project, format: .srt)
        #expect(srt.hasPrefix("1\n00:00:00,000 --> 00:00:01,200\nMaya: Hello there."))
        let vtt = Renderer.render(project, format: .vtt)
        #expect(vtt.hasPrefix("WEBVTT\n\n00:00:00.000 --> 00:00:01.200\n<v Maya>Hello there."))
    }

    @Test func jsonHasWordsAndSpeakers() throws {
        let out = Renderer.render(project, format: .json, options: RenderOptions(hideFillers: false))
        let obj = try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any]
        let sections = obj?["sections"] as? [[String: Any]]
        #expect((sections?.first?["words"] as? [Any])?.count == 4)
        #expect((obj?["speakers"] as? [Any])?.count == 2)
    }

    @Test func projectRoundTrips() throws {
        var p = project
        p.createdAt = Date(timeIntervalSince1970: 1_800_000_000.25)
        #expect(try Project.decode(p.encoded()) == p)
    }
}
