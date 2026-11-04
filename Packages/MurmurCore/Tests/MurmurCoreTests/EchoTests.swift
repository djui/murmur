import Foundation
import Testing
@testable import MurmurCore

@Suite struct EchoTests {
    let rate = 16_000.0

    /// Deterministic noise.
    struct Noise {
        var state: UInt64
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: state >> 11) % 2000) / 1000
        }
    }

    /// Speech-like bursts: noise switched on in syllables of uneven length inside `ranges` (seconds).
    func bursts(_ ranges: [(Double, Double)], length: Double, seed: UInt64, level: Float = 0.5) -> [Float] {
        var noise = Noise(state: seed)
        var out = [Float](repeating: 0, count: Int(length * rate))
        for (a, b) in ranges {
            var t = a
            var syllable = 0
            while t < b {
                let dur = 0.12 + Double(syllable % 3) * 0.07
                let lo = Int(t * rate), hi = min(out.count, Int(min(b, t + dur) * rate))
                if lo < hi { for i in lo..<hi { out[i] = noise.next() * level } }
                t += dur + 0.04 + Double(syllable % 2) * 0.05
                syllable += 1
            }
        }
        // A quiet room underneath.
        for i in out.indices { out[i] += noise.next() * 0.002 }
        return out
    }

    /// The system track delayed by `delay` and quietened, as the microphone hears it through the speakers.
    func leak(_ system: [Float], delay: Double, gain: Float) -> [Float] {
        let shift = Int(delay * rate)
        var out = [Float](repeating: 0, count: system.count)
        for i in shift..<system.count { out[i] = system[i - shift] * gain }
        return out
    }

    func w(_ text: String, _ start: Double, _ end: Double) -> Word { Word(text: text, start: start, end: end) }

    @Test func findsTheSpeakerDelay() {
        let system = bursts([(1, 8), (12, 20)], length: 24, seed: 1)
        let mic = leak(system, delay: 0.08, gain: 0.15)
        let delay = Echo.delay(mic: mic, system: system, sampleRate: rate)
        #expect(delay != nil)
        #expect(abs((delay ?? 0) - 0.08) <= 0.011)
    }

    @Test func noDelayWithHeadphones() {
        let system = bursts([(1, 8), (12, 20)], length: 24, seed: 1)
        let mic = bursts([(9, 11), (21, 23)], length: 24, seed: 2)
        #expect(Echo.delay(mic: mic, system: system, sampleRate: rate) == nil)
    }

    @Test func gateFlagsLeakButKeepsYouAndDoubleTalk() throws {
        let system = bursts([(1, 8), (12, 20)], length: 24, seed: 1)
        let own = bursts([(9, 11), (15, 16.5), (21, 23)], length: 24, seed: 2)
        let echo = leak(system, delay: 0.08, gain: 0.15)
        let mic = zip(own, echo).map { $0 + $1 }
        let gate = try #require(Echo.gate(mic: mic, system: system, sampleRate: rate))
        // Only the others talking: echo.
        #expect(gate.echoShare(from: 2, to: 7) > 0.6)
        // Only you: kept.
        #expect(gate.echoShare(from: 9.2, to: 10.8) < 0.1)
        #expect(gate.echoShare(from: 21.2, to: 22.8) < 0.1)
        // You talking over them: mostly kept.
        #expect(gate.echoShare(from: 15.1, to: 16.4) < 0.4)
    }

    @Test func splitUsesGateAndKeepsRemovedWords() {
        let gate = Echo.Gate(delay: 0.1, frames: (0..<200).map { $0 < 100 })  // echo during the first 5 s
        let mic = [w("lisbon", 1.0, 1.4), w("office", 1.5, 1.9), w("mine", 6, 6.3), w("too", 6.4, 6.6)]
        let out = Echo.split(mic: mic, system: [], gate: gate)
        #expect(out.kept.map(\.text) == ["mine", "too"])
        #expect(out.removed.count == 1)
        #expect(out.removed.first?.words.map(\.text) == ["lisbon", "office"])
    }

    @Test func looseSpellingCountsAsEcho() {
        // The same words written slightly differently by the two transcribers, 0.1 s later on the mic.
        let system = [w("wants", 1.0, 1.3), w("live", 2.0, 2.2), w("twelfth", 3.0, 3.4), w("realistically", 4.0, 4.6)]
        let mic = [w("want", 1.1, 1.4), w("life", 2.1, 2.3), w("twelve", 3.1, 3.5), w("realistic", 4.1, 4.6),
                   w("mine", 8, 8.3)]
        #expect(Merge.removeEcho(mic: mic, system: system, delay: 0.1).map(\.text) == ["mine"])
    }

    @Test func shortWordsMustMatchExactly() {
        #expect(!Merge.soundsAlike("yes", "yet"))
        #expect(!Merge.soundsAlike("a", "the"))
        #expect(Merge.soundsAlike("ok", "ok"))
        #expect(!Merge.soundsAlike("plan", "page"))
        #expect(Merge.soundsAlike("twelve", "twelfth"))
    }

    @Test func spansSplitAtPauses() {
        let spans = Echo.spans([w("a", 0, 0.5), w("b", 0.6, 1), w("c", 5, 5.4)])
        #expect(spans.map { $0.words.count } == [2, 1])
        #expect(spans.last?.start == 5)
    }

    @Test func echoSpansRoundTripAndOldProjectsDecode() throws {
        var project = Project()
        project.echo = [EchoSpan(words: [w("hi", 1, 2)])]
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(project))
        #expect(back.echo?.first?.words.first?.text == "hi")
        let old = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(Project()))
        #expect(old.echo == nil)
    }
}
