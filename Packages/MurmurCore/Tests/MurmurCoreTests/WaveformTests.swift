import Testing
@testable import MurmurCore

@Suite struct WaveformLevelTests {
    @Test func talkWithPausesDrawsBelowSolidTalk() {
        // 100 bins a second: one second of solid talk, one of talk with pauses, one of a quiet room.
        let solid = [Float](repeating: 0.6, count: 100)
        let pauses = (0..<100).map { $0 % 4 == 0 ? Float(0.6) : 0.02 }
        let quiet = [Float](repeating: 0.01, count: 100)
        let peaks = solid + pauses + quiet
        let a = Peaks.level(in: peaks, from: 0, to: 1), b = Peaks.level(in: peaks, from: 1, to: 2), c = Peaks.level(in: peaks, from: 2, to: 3)
        #expect(a > b && b > c)
        // The old peak-per-bar drew the first two the same.
        #expect(Peaks.peak(in: peaks, from: 0, to: 1) == Peaks.peak(in: peaks, from: 1, to: 2))
        // Zoomed in to one bin, a bar is that bin's peak.
        #expect(Peaks.level(in: peaks, from: 1.0, to: 1.01) == 0.6)
        // Heights: zoomed out, solid talk clearly above talk with pauses, silence at the bottom.
        let h = [0.0, 1.0, 2.0].map { Peaks.barHeight(in: peaks, from: $0, to: $0 + 1) }
        #expect(h[0] - h[1] > 0.25)
        #expect(h[2] < 0.05)
    }
}
