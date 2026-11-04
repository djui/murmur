import Foundation

/// Microphone words taken out of a recording as the remote side leaking in through the speakers.
/// Kept with the project so they can be shown and put back.
public struct EchoSpan: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var words: [Word]

    public init(id: UUID = UUID(), words: [Word]) {
        self.id = id
        self.words = words
    }

    public var start: Double { words.first?.start ?? 0 }
    public var end: Double { words.last?.end ?? 0 }
}

/// Finds the remote side's voices on the microphone track by sound: where the microphone is explained by
/// the system track a moment earlier, it is the speakers being heard, not you.
public enum Echo {
    /// Envelope resolution for finding the delay.
    static let envelopeHop = 0.01
    /// Resolution of the echo decision.
    public static let frameSeconds = 0.05

    /// Where the microphone is only hearing the speakers, per `frameSeconds` frame of microphone time.
    public struct Gate: Sendable, Equatable {
        /// How far the microphone lags the system track, in seconds.
        public var delay: Double
        /// True for frames that are echo.
        public var frames: [Bool]

        public init(delay: Double, frames: [Bool]) {
            self.delay = delay
            self.frames = frames
        }

        /// Share of `start..<end` (microphone time) that is echo.
        public func echoShare(from start: Double, to end: Double) -> Double {
            guard !frames.isEmpty, end > start else { return 0 }
            let lo = max(0, Int(start / Echo.frameSeconds))
            let hi = min(frames.count, Int((end / Echo.frameSeconds).rounded(.up)))
            guard hi > lo else { return 0 }
            var n = 0
            for i in lo..<hi where frames[i] { n += 1 }
            return Double(n) / Double(hi - lo)
        }
    }

    /// Mean energy of each `hop`-second frame.
    static func energies(_ samples: [Float], sampleRate: Double, hop: Double) -> [Float] {
        let size = max(1, Int(sampleRate * hop))
        let count = samples.count / size
        var out = [Float](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { p in
            for i in 0..<count {
                var sum: Float = 0
                let base = i * size
                for j in 0..<size { let s = p[base + j]; sum += s * s }
                out[i] = sum / Float(size)
            }
        }
        return out
    }

    /// The delay (0 ... `maxDelay` s) at which the microphone's loudness follows the system track's most closely,
    /// or nil when they don't follow each other (headphones, or nobody else talking).
    public static func delay(mic: [Float], system: [Float], sampleRate: Double, maxDelay: Double = 0.3) -> Double? {
        let m = logEnvelope(energies(mic, sampleRate: sampleRate, hop: envelopeHop))
        let s = logEnvelope(energies(system, sampleRate: sampleRate, hop: envelopeHop))
        let n = min(m.count, s.count)
        let maxLag = Int(maxDelay / envelopeHop)
        guard n > maxLag * 4 else { return nil }
        var best = -1.0, bestLag = 0
        for lag in 0...maxLag {
            // mic[t] against system[t - lag]
            var dot = 0.0, mm = 0.0, ss = 0.0
            for t in lag..<n {
                let a = Double(m[t]), b = Double(s[t - lag])
                dot += a * b; mm += a * a; ss += b * b
            }
            let r = dot / max(1e-12, (mm * ss).squareRoot())
            if r > best { best = r; bestLag = lag }
        }
        return best >= 0.3 ? Double(bestLag) * envelopeHop : nil
    }

    /// Log energies with the mean taken out, so correlation follows the shape of speech, not its level.
    static func logEnvelope(_ e: [Float]) -> [Float] {
        let logs = e.map { log10(max($0, 1e-10)) }
        let mean = logs.reduce(0, +) / Float(max(1, logs.count))
        return logs.map { $0 - mean }
    }

    /// Marks microphone frames that the delayed system track explains: the system is talking, and the microphone
    /// is no louder than the speakers' usual leak into it predicts. When you talk over someone, the microphone is
    /// much louder than the leak and the frame is kept. Nil when the microphone doesn't hear the system at all.
    public static func gate(mic: [Float], system: [Float], sampleRate: Double, delay knownDelay: Double? = nil) -> Gate? {
        guard let delay = knownDelay ?? self.delay(mic: mic, system: system, sampleRate: sampleRate) else { return nil }
        let m = energies(mic, sampleRate: sampleRate, hop: frameSeconds)
        let s = energies(system, sampleRate: sampleRate, hop: frameSeconds)
        let lag = Int((delay / frameSeconds).rounded())
        guard m.count > lag, !s.isEmpty else { return nil }
        let sysFloor = percentile(s.filter { $0 > 0 }, 0.2) * 4 + 1e-9
        let micFloor = percentile(m.filter { $0 > 0 }, 0.2) * 4 + 1e-9
        // The leak: mic energy per unit of system energy. A low percentile, since frames where you talk
        // over the others pull the ratio up.
        var ratios: [Float] = []
        for t in lag..<m.count where t - lag < s.count {
            let sv = sysPeak(s, t - lag)
            if sv > sysFloor, m[t] > micFloor { ratios.append(m[t] / sv) }
        }
        guard ratios.count >= 20 else { return Gate(delay: delay, frames: Array(repeating: false, count: m.count)) }
        let leak = percentile(ratios, 0.3)
        var frames = [Bool](repeating: false, count: m.count)
        for t in lag..<m.count where t - lag < s.count {
            let sv = sysPeak(s, t - lag)
            // 8x the predicted leak's energy (9 dB) or more is you talking.
            frames[t] = sv > sysFloor && m[t] <= leak * sv * 8
        }
        return Gate(delay: delay, frames: smooth(frames))
    }

    /// The loudest of a frame and its neighbours: the room keeps the leak going a little after the source.
    private static func sysPeak(_ s: [Float], _ i: Int) -> Float {
        var v = s[i]
        if i > 0 { v = max(v, s[i - 1]) }
        if i + 1 < s.count { v = max(v, s[i + 1]) }
        return v
    }

    /// Closes single-frame holes and drops single-frame islands.
    static func smooth(_ frames: [Bool]) -> [Bool] {
        guard frames.count > 2 else { return frames }
        var out = frames
        for i in 1..<(frames.count - 1) {
            if !frames[i] && frames[i - 1] && frames[i + 1] { out[i] = true }
            if frames[i] && !frames[i - 1] && !frames[i + 1] { out[i] = false }
        }
        return out
    }

    static func percentile(_ values: [Float], _ p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * p))]
    }

    /// Splits microphone words into yours and echo: by sound where there is a gate, then by matching text
    /// against the system track's words. Removed words come back grouped into spans.
    public static func split(mic: [Word], system: [Word], gate: Gate?) -> (kept: [Word], removed: [EchoSpan]) {
        var byGate: [Word] = []
        var gone: [Word] = []
        for w in mic {
            if let gate, gate.echoShare(from: w.start, to: w.end) >= 0.6 { gone.append(w) } else { byGate.append(w) }
        }
        let kept = Merge.removeEcho(mic: byGate, system: system, delay: gate?.delay ?? 0)
        var keptKeys = Set<Key>()
        for w in kept { keptKeys.insert(Key(w)) }
        gone += byGate.filter { !keptKeys.contains(Key($0)) }
        return (kept, spans(gone.sorted { $0.start < $1.start }))
    }

    /// Groups words into spans split at pauses longer than `gap`.
    public static func spans(_ words: [Word], gap: Double = 1.5) -> [EchoSpan] {
        var out: [EchoSpan] = []
        var current: [Word] = []
        for w in words {
            if let last = current.last, w.start - last.end > gap { out.append(EchoSpan(words: current)); current = [] }
            current.append(w)
        }
        if !current.isEmpty { out.append(EchoSpan(words: current)) }
        return out
    }

    private struct Key: Hashable {
        let start: Double, text: String
        init(_ w: Word) { start = w.start; text = w.text }
    }
}

extension Merge {
    /// Drops microphone words that are the remote side leaking into an open mic: a word on the system track
    /// that sounds alike, within `tolerance` seconds once the microphone's `delay` is taken off.
    public static func removeEcho(mic: [Word], system: [Word], tolerance: Double = 0.6, delay: Double = 0) -> [Word] {
        guard !system.isEmpty else { return mic }
        let sys = system.sorted { $0.start < $1.start }
        let sysKeys = sys.map { normalized($0.text) }
        var j = 0
        return mic.filter { word in
            let t = word.start - delay
            while j < sys.count && sys[j].start < t - tolerance { j += 1 }
            let key = normalized(word.text)
            guard !key.isEmpty else { return true }
            var k = j
            while k < sys.count && sys[k].start <= t + tolerance {
                if soundsAlike(key, sysKeys[k]) { return false }
                k += 1
            }
            return true
        }
    }

    /// Two normalized words two transcribers could have written for the same sound: equal, one a stem of the
    /// other at least four letters long ("realistic"/"realistically"), or close in spelling ("live"/"life",
    /// "twelve"/"twelfth"). Words shorter than four letters must match exactly.
    static func soundsAlike(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let short = min(a.count, b.count), long = max(a.count, b.count)
        guard short >= 4 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        let shared = zip(a, b).prefix { $0 == $1 }.count
        if shared >= 4, Double(shared) / Double(short) >= 0.6, long - short <= 3 { return true }
        let distance = editDistance(a, b)
        return distance <= 2 && Double(distance) / Double(long) <= 0.34
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count), cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }
}
