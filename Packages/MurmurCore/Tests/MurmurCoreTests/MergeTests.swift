import Testing
@testable import MurmurCore

@Suite struct MergeTests {
    func w(_ text: String, _ start: Double, _ end: Double, _ speaker: Int = 0) -> Word {
        Word(text: text, start: start, end: end, speaker: speaker)
    }

    @Test func assignsByOverlapAndRenumbersByFirstAppearance() {
        let words = [w("hi", 0, 0.5), w("there", 0.6, 1.0), w("hello", 2.0, 2.4), w("back", 2.5, 2.9)]
        let turns = [SpeakerTurn(start: 0, end: 1.2, speaker: 3), SpeakerTurn(start: 1.8, end: 3, speaker: 1)]
        let out = Merge.assign(words, turns: turns)
        #expect(out.map(\.speaker) == [0, 0, 1, 1])
    }

    @Test func wordOutsideAnyTurnGoesToNearest() {
        let out = Merge.assign([w("early", 0.2, 0.4), w("late", 5, 5.2)],
                               turns: [SpeakerTurn(start: 0, end: 1, speaker: 0),
                                       SpeakerTurn(start: 4, end: 4.9, speaker: 1)])
        #expect(out.map(\.speaker) == [0, 1])
    }

    @Test func assignHonoursFirstId() {
        let out = Merge.assign([w("a", 0, 1)], turns: [SpeakerTurn(start: 0, end: 1, speaker: 7)], firstId: 1)
        #expect(out[0].speaker == 1)
    }

    @Test func paragraphsBreakOnSpeakerAndPause() {
        let words = [w("a", 0, 0.3, 0), w("b", 0.4, 0.6, 0), w("c", 0.7, 0.9, 1), w("d", 3.0, 3.2, 1)]
        let ps = Merge.paragraphs(words)
        #expect(ps.map(\.range) == [0..<2, 2..<3, 3..<4])
        #expect(ps[1].speaker == 1)
    }

    @Test func mergedParagraphsStayTogether() {
        let words = [w("a", 0, 0.3, 0), w("b", 3.0, 3.2, 0), w("c", 3.3, 3.5, 1)]
        let joined = Editing.join(words, 0..<1, 1..<2, speaker: 0)
        #expect(Merge.paragraphs(joined).map(\.range) == [0..<2, 2..<3])
        // Into the next paragraph: the merged one takes that speaker.
        let next = Editing.join(joined, 0..<2, 2..<3, speaker: 1)
        #expect(Merge.paragraphs(next).map(\.range) == [0..<3])
        #expect(next.map(\.speaker) == [1, 1, 1])
    }

    @Test func wholeParagraphMergesPastTheLengthLimit() {
        // Two 40 s paragraphs of sentences, split by a pause: merged, the length limit must not split them again.
        let a = (0..<4).map { w("A\($0).", Double($0) * 10, Double($0) * 10 + 9) }
        let b = (0..<4).map { w("B\($0).", 42 + Double($0) * 10, 42 + Double($0) * 10 + 9) }
        let words = a + b
        #expect(Merge.paragraphs(words).map(\.range) == [0..<4, 4..<8])
        let joined = Editing.join(words, 0..<4, 4..<8, speaker: 0)
        #expect(Merge.paragraphs(joined).map(\.range) == [0..<8])
        // Editing the merged paragraph keeps it merged.
        let edited = Editing.replace(in: joined, range: 0..<8, with: "A0. A1. A2. A3. B0. B1. B2. B3!").words
        #expect(Merge.paragraphs(edited).map(\.range) == [0..<8])
    }

    @Test func echoOnMicIsRemoved() {
        let mic = [w("hello", 1.0, 1.3), w("mine", 5, 5.3)]
        let system = [w("Hello,", 0.8, 1.1)]
        #expect(Merge.removeEcho(mic: mic, system: system).map(\.text) == ["mine"])
    }

    @Test func fillersAreMarkedOrInserted() {
        let words = [w("so", 0, 0.3), w("um", 0.5, 0.8), w("yes", 2.0, 2.3)]
        let out = Merge.markFillers(words, fillers: [FillerSpan(start: 0.45, end: 0.85),
                                                     FillerSpan(start: 1.2, end: 1.6, label: "uh")])
        #expect(out.map(\.text) == ["so", "um", "uh", "yes"])
        #expect(out.map(\.isFiller) == [false, true, true, false])
    }

    @Test func indicesSnapToWholeWords() {
        let words = [w("a", 0, 1), w("b", 1, 2), w("c", 2, 3)]
        #expect(Merge.indices(of: words, from: 0.9, to: 2.4) == 1..<2)
        #expect(Merge.indices(of: words, from: 0, to: 10) == 0..<3)
    }

    @Test func peaksRoundTrip() {
        let samples: [Float] = (0..<1600).map { Float($0 % 160) / 160 }
        let peaks = Peaks.compute(samples, sampleRate: 16000)
        #expect(peaks.count == 10)
        #expect(Peaks.decode(Peaks.encode(peaks)) == peaks)
    }

    @Test func timecodes() {
        #expect(Timecode.short(75.4) == "01:15")
        #expect(Timecode.short(3725) == "1:02:05")
        #expect(Timecode.precise(75.46) == "01:15.4")
        #expect(Timecode.srt(3.5) == "00:00:03,500")
    }
}

@Suite struct JoinTests {
    @Test func cjkJoinsWithoutSpaces() {
        #expect(Merge.join(["こ", "ん", "に", "ち", "は", "。"]) == "こんにちは。")
        #expect(Merge.join(["Hello", "world."]) == "Hello world.")
        #expect(Merge.join(["Tokyo", "東", "京"]) == "Tokyo 東京")
    }

    @Test func monotonicKeepsOrder() {
        let out = Merge.monotonic([Word(text: "a", start: 1, end: 1.2), Word(text: "b", start: 0.9, end: 1.0)])
        #expect(out[1].start == 1 && out[1].end == 1)
    }
}
