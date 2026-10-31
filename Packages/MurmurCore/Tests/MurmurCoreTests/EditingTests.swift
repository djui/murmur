import Testing
@testable import MurmurCore

@Suite struct EditingTests {
    let old = [
        Word(text: "We", start: 0, end: 0.2),
        Word(text: "had", start: 0.3, end: 0.5),
        Word(text: "high", start: 0.6, end: 0.8),
        Word(text: "drophones", start: 0.9, end: 1.4),
        Word(text: "there.", start: 1.5, end: 1.8),
    ]

    @Test func unchangedWordsKeepTiming() {
        let out = Editing.retime(old, newText: "We had hydrophones there.", speaker: 0)
        #expect(out.map(\.text) == ["We", "had", "hydrophones", "there."])
        #expect(out[0].start == 0 && out[1].start == 0.3 && out[3].start == 1.5)
        #expect(!out[0].edited && out[2].edited)
        // The new word takes the time of the two it replaced.
        #expect(out[2].start == 0.6 && out[2].end == 1.4)
    }

    @Test func insertionGetsTimeBetweenNeighbours() {
        let out = Editing.retime(old, newText: "We really had high drophones there.", speaker: 0)
        #expect(out.count == 6)
        #expect(out[1].text == "really" && out[1].edited)
        #expect(out[1].start >= 0.1 && out[1].end <= 0.4)
    }

    @Test func punctuationChangeMarksEditedButKeepsTime() {
        let out = Editing.retime(old, newText: "We had high drophones there!", speaker: 0)
        #expect(out[4].text == "there!" && out[4].edited && out[4].start == 1.5)
    }

    @Test func replaceUpdatesRange() {
        let words = old + [Word(text: "Next", start: 3, end: 3.2, speaker: 1)]
        let (out, range) = Editing.replace(in: words, range: 0..<5, with: "We had them")
        #expect(range == 0..<3)
        #expect(out.count == 4 && out[3].text == "Next")
    }

    @Test func mergeSpeakers() {
        var p = Project()
        p.speakers = [Speaker(id: 0), Speaker(id: 1)]
        p.words = [Word(text: "a", start: 0, end: 1, speaker: 1)]
        let merged = Editing.mergeSpeaker(p, from: 1, into: 0)
        #expect(merged.words[0].speaker == 0 && merged.speakers.count == 1)
    }

    @Test func selectionFindsTheWordsItTouches() {
        // "We had high drophones there."
        #expect(Editing.words(old, touching: 0..<2) == 0..<1)
        #expect(Editing.words(old, touching: 4..<9) == 1..<3)      // "ad hi"
        #expect(Editing.words(old, touching: 12..<28) == 3..<5)    // to the end
        #expect(Editing.words(old, touching: 2..<3) == nil)        // just the space
        #expect(Editing.words(old, touching: 5..<5) == nil)        // a caret
    }

    @Test func partOfAParagraphMovesToAnotherSpeaker() {
        var p = Project()
        p.speakers = [Speaker(id: 0), Speaker(id: 1)]
        p.words = old
        p.words = Editing.reassign(p.words, range: 2..<4, to: 1)
        let paragraphs = Merge.paragraphs(p.words)
        #expect(paragraphs.map(\.speaker) == [0, 1, 0])
        #expect(paragraphs.map(\.range) == [0..<2, 2..<4, 4..<5])
    }

    @Test func endOfAParagraphBecomesANewSpeaker() {
        var p = Project()
        p.speakers = [Speaker(id: 0), Speaker(id: 1)]
        p.words = old
        let out = Editing.toNewSpeaker(p, range: 3..<5)
        #expect(out.speakers.map(\.id) == [0, 1, 2])
        #expect(out.words.map(\.speaker) == [0, 0, 0, 2, 2])
    }
}
