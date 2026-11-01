import Foundation
import Testing
@testable import MurmurCore

/// The browser version ports MurmurCore to TypeScript (`web/app/src/core`). Both run the same cases:
/// this test computes what MurmurCore returns for fixed inputs and keeps it in `Fixtures/core.json`,
/// and the TypeScript tests expect the same. Run with `MURMUR_WRITE_FIXTURES=1` after a deliberate
/// change to regenerate the file.
@Suite struct FixtureTests {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/core.json")

    @Test func fixturesMatchMurmurCore() throws {
        let current = try JSONSerialization.data(withJSONObject: Self.cases(), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if ProcessInfo.processInfo.environment["MURMUR_WRITE_FIXTURES"] != nil {
            try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try current.write(to: Self.url)
        }
        let stored = try Data(contentsOf: Self.url)
        let a = try JSONSerialization.jsonObject(with: current) as! NSDictionary
        let b = try JSONSerialization.jsonObject(with: stored) as! NSDictionary
        #expect(a == b, "Fixtures/core.json is out of date: run the tests with MURMUR_WRITE_FIXTURES=1")
    }

    // MARK: inputs

    static func word(_ text: String, _ start: Double, _ end: Double, _ speaker: Int = 0, filler: Bool = false) -> Word {
        Word(text: text, start: start, end: end, speaker: speaker, isFiller: filler)
    }

    static let words: [Word] = [
        word("Hello", 0, 0.4), word("um", 0.5, 0.7, filler: true), word("there.", 0.8, 1.2),
        word("Hi!", 2.0, 2.3, 1), word("Call", 2.4, 2.6, 1), word("Anna", 2.7, 3.0, 1),
        word("Berg", 3.05, 3.3, 1), word("at", 3.4, 3.5, 1), word("555", 3.6, 4.0, 1), word("0199.", 4.0, 4.6, 1),
        word("Sure,", 7.0, 7.3), word("will", 7.35, 7.5), word("do.", 7.55, 7.9),
    ]

    static var project: Project {
        var p = Project()
        p.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        p.createdAt = Date(timeIntervalSince1970: 1_790_000_000)
        p.title = "Sync"
        p.duration = 10
        p.language = "en"
        p.status = .ready
        p.speakers = [Speaker(id: 0, name: "Maya"), Speaker(id: 1, isMe: true)]
        p.words = words
        p.marks = [Mark(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!, name: "Number", start: 2.4, end: 4.6)]
        p.redactions = [
            RedactedSpan(start: 2.7, end: 3.3, category: "name", original: "Anna Berg"),
            RedactedSpan(start: 3.6, end: 4.6, category: "phone", original: "555 0199"),
        ]
        return p
    }

    // MARK: outputs

    static func json(_ w: Word) -> [String: Any] {
        ["text": w.text, "start": w.start, "end": w.end, "speaker": w.speaker, "isFiller": w.isFiller, "edited": w.edited]
    }

    static func json(_ words: [Word]) -> [[String: Any]] { words.map { json($0) } }

    static func cases() throws -> [String: Any] {
        var out: [String: Any] = [:]
        out["words"] = json(words)

        let times: [Double] = [0, 5.04, 59.99, 61.25, 3599.95, 3725.5]
        out["timecode"] = times.map { ["t": $0, "short": Timecode.short($0), "precise": Timecode.precise($0),
                                       "srt": Timecode.srt($0), "vtt": Timecode.vtt($0)] as [String: Any] }

        let turns = [SpeakerTurn(start: 0, end: 1.5, speaker: 3), SpeakerTurn(start: 1.9, end: 4.7, speaker: 1),
                     SpeakerTurn(start: 6.8, end: 8, speaker: 3)]
        out["assign"] = ["turns": turns.map { ["start": $0.start, "end": $0.end, "speaker": $0.speaker] },
                         "result": json(Merge.assign(words.map { var w = $0; w.speaker = 0; return w }, turns: turns))]

        out["paragraphs"] = Merge.paragraphs(words).map {
            ["speaker": $0.speaker, "lower": $0.range.lowerBound, "upper": $0.range.upperBound, "start": $0.start, "end": $0.end]
        }
        out["join"] = [["Hello", "there."], ["東京", "に", "行く"], ["Hi", "東京", "ok"], ["", "a", "", "b"]]
            .map { ["in": $0, "out": Merge.join($0)] as [String: Any] }
        out["normalized"] = ["Hello,", "DON'T", "naïve!", "0199."].map { ["in": $0, "out": Merge.normalized($0)] }
        out["indices"] = [(0.0, 1.0), (2.5, 4.1), (5, 6), (0, 100)].map {
            let r = Merge.indices(of: words, from: $0.0, to: $0.1)
            return ["from": $0.0, "to": $0.1, "lower": r.lowerBound, "upper": r.upperBound] as [String: Any]
        }
        out["monotonic"] = ["in": json([word("a", 1, 2), word("b", 0.5, 0.8), word("c", 3, 4)]),
                            "out": json(Merge.monotonic([word("a", 1, 2), word("b", 0.5, 0.8), word("c", 3, 4)]))]

        let old = Array(words[10..<13])
        out["retime"] = ["Sure, will do.", "Sure, we will do it.", "Okay.", "", "will do. Sure,"].map {
            ["text": $0, "out": json(Editing.retime(old, newText: $0, speaker: 0))] as [String: Any]
        }
        let replaced = Editing.replace(in: words, range: 10..<13, with: "Sure thing, will do.")
        out["replace"] = ["words": json(replaced.words), "lower": replaced.range.lowerBound, "upper": replaced.range.upperBound]
        out["touching"] = [(0, 3), (6, 7), (5, 6), (12, 20), (0, 0)].map {
            let r = Editing.words(words, touching: $0.0..<$0.1)
            return ["lower": $0.0, "upper": $0.1, "range": r.map { [$0.lowerBound, $0.upperBound] } ?? NSNull()] as [String: Any]
        }

        let spans = project.redactions!
        out["redact"] = RedactionStyle.allCases.map {
            ["style": $0.rawValue, "out": json(Redactor.apply(words, spans: spans, style: $0))] as [String: Any]
        }
        let (text, ranges) = Redactor.text(of: words)
        out["redactText"] = ["text": text, "ranges": ranges.map { [$0.lowerBound, $0.upperBound] }]

        let marks = [Mark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "a", start: 0, end: 5),
                     Mark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "b", start: 1, end: 2),
                     Mark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, name: "c", start: 2, end: 6),
                     Mark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, name: "d", start: 5, end: 7),
                     Mark(id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!, name: "e", start: 1.5, end: 3)]
        let rows = MarkLayout.rows(marks, maxRows: 2)
        out["markRows"] = ["marks": marks.map { ["id": $0.id.uuidString, "start": $0.start, "end": $0.end] },
                           "rows": marks.map { rows[$0.id].map { $0 as Any } ?? NSNull() },
                           "rowCount": MarkLayout.rowCount(marks, maxRows: 2)]

        let samples: [Float] = (0..<1000).map { Float(sin(Double($0) / 7)) * Float($0 % 250) / 250 }
        let peaks = Peaks.compute(samples, sampleRate: 1000, binsPerSecond: 50)
        out["peaks"] = ["samples": samples.map(Double.init), "compute": peaks.map(Double.init),
                        "normalize": Peaks.normalize(peaks).map(Double.init),
                        "peak": Double(Peaks.peak(in: peaks, from: 0.1, to: 0.35, binsPerSecond: 50)),
                        "loudness": [0, 0.001, 0.05, 0.5, 1].map { Double(Peaks.loudness(Float($0))) }]

        var renders: [[String: Any]] = []
        var redacted = project
        redacted.settings.redact = true
        let sections = [TranscriptSection(name: "Greeting", start: 0, end: 1.5), TranscriptSection(name: "Reply", start: 1.5, end: 8)]
        for format in TextFormat.allCases {
            for (name, p, parts, options) in [
                ("all", project, nil as [TranscriptSection]?, RenderOptions()),
                ("fillers", project, nil, RenderOptions(hideFillers: false, redactionStyle: .labels)),
                ("noNames", project, nil, RenderOptions(speakerNames: false)),
                ("sections", project, sections, RenderOptions(relativeTimes: true)),
                ("redacted", redacted, nil, RenderOptions(redactionStyle: .initials)),
            ] {
                renders.append(["format": format.rawValue, "case": name,
                                "out": Renderer.render(p, sections: parts, format: format, options: options)])
            }
        }
        out["render"] = renders
        out["project"] = try JSONSerialization.jsonObject(with: redacted.encoded())

        var map = ShortcutMap()
        let first = map.add(ShortcutKey(rawValue: "m")!, to: .playPause)
        let second = map.add(ShortcutKey(rawValue: "?")!, to: .back)
        out["shortcuts"] = ["defaults": ShortcutAction.allCases.map { [$0.rawValue: $0.defaultKeys.map(\.rawValue)] },
                            "afterAddingMToPlay": map.stored, "results": ["\(first)", "\(second)"]]

        // Gap repair: words at speech level, a loud gap (a skipped word), a quiet gap (a pause) and a
        // loud stretch after the last word.
        let gw = [word("es", 0, 0.3), word("fällt", 0.35, 0.7), word("dir", 0.75, 0.9), word("gar", 0.95, 1.2),
                  word("nicht", 1.25, 1.6), word("Deine", 4, 4.4), word("Hände", 4.5, 5), word("zittern", 7.5, 8)]
        var gp = [Float](repeating: 0.02, count: 1000)
        for w in gw { for b in Int(w.start * 100)..<Int(w.end * 100) { gp[b] = 0.8 } }
        for b in 170..<230 { gp[b] = 0.6 }      // the skipped "auf"
        for b in 820..<900 { gp[b] = 0.7 }      // something after the last word
        let gaps = GapRepair.gaps(in: gw, duration: 10, peaks: gp)
        let gap = gaps.first { $0.after == 4 }!
        func heard(_ items: [(String, Double, Double)]) -> [Word] { items.map { word($0.0, $0.1, $0.2) } }
        out["gapRepair"] = [
            "words": json(gw), "peaks": gp.map(Double.init), "duration": 10,
            "gaps": gaps.map { ["after": $0.after, "start": $0.start, "end": $0.end, "windowStart": $0.windowStart, "windowEnd": $0.windowEnd] },
            "splices": [
                ("matches", heard([("gar", 0.96, 1.2), ("nicht", 1.26, 1.62), ("auf.", 1.9, 2.2), ("Deine", 4.01, 4.4)])),
                ("other context", heard([("gar", 0.96, 1.2), ("noch", 1.26, 1.62), ("auf.", 1.9, 2.2)])),
                ("nothing new", heard([("gar", 0.96, 1.2), ("nicht.", 1.26, 1.62), ("Deine", 4.01, 4.4)])),
            ].map { name, h in
                ["case": name, "heard": json(h), "out": GapRepair.splice(gw, gap: gap, heard: h).map { json($0) as Any } ?? NSNull()] as [String: Any]
            },
        ] as [String: Any]

        out["palettes"] = SpeakerPalettes.schemes.mapValues { $0.map { [String(format: "%06X", $0.light), String(format: "%06X", $0.dark)] } }
        return out
    }
}
