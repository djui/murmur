import Foundation
import Testing
@testable import MurmurCore

@Suite struct GapRepairTests {
    let words = [Word(text: "gar", start: 0.95, end: 1.2), Word(text: "nicht", start: 1.25, end: 1.6, speaker: 2),
                 Word(text: "Deine", start: 4, end: 4.4), Word(text: "Hände", start: 4.5, end: 5)]

    func peaks(loud: [Range<Int>]) -> [Float] {
        var p = [Float](repeating: 0.02, count: 600)
        for w in words { for b in Int(w.start * 100)..<Int(w.end * 100) { p[b] = 0.8 } }
        for r in loud { for b in r { p[b] = 0.6 } }
        return p
    }

    @Test func loudGapIsFoundQuietOneIsNot() {
        #expect(GapRepair.gaps(in: words, duration: 6, peaks: peaks(loud: [170..<230])).map(\.after) == [1])
        #expect(GapRepair.gaps(in: words, duration: 6, peaks: peaks(loud: [])).isEmpty)
    }

    @Test func windowStartsOnAWordBeforeTheGap() {
        let gap = GapRepair.gaps(in: words, duration: 6, peaks: peaks(loud: [170..<230]))[0]
        #expect(abs(gap.windowStart - 0.8) < 1e-9)
        #expect(abs(gap.windowEnd - 4.3) < 1e-9)
    }

    @Test func spliceKeepsOnlyNewWordsInsideTheGap() throws {
        let gap = GapRepair.gaps(in: words, duration: 6, peaks: peaks(loud: [170..<230]))[0]
        let heard = [Word(text: "nicht", start: 1.26, end: 1.6), Word(text: "auf.", start: 1.9, end: 2.2),
                     Word(text: "Deine", start: 4.0, end: 4.4)]
        let out = try #require(GapRepair.splice(words, gap: gap, heard: heard))
        #expect(out.map(\.text) == ["gar", "nicht", "auf.", "Deine", "Hände"])
        #expect(out[2].speaker == 2)
    }

    @Test func spliceRefusesADifferentContext() {
        let gap = GapRepair.gaps(in: words, duration: 6, peaks: peaks(loud: [170..<230]))[0]
        let heard = [Word(text: "noch", start: 1.26, end: 1.6), Word(text: "auf.", start: 1.9, end: 2.2)]
        #expect(GapRepair.splice(words, gap: gap, heard: heard) == nil)
    }
}
