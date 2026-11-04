import Foundation

/// The waveform as one peak per bin, computed once and cached as `peaks.bin`.
public enum Peaks {
    public static let binsPerSecond = 100

    public static func compute(_ samples: [Float], sampleRate: Double, binsPerSecond: Int = binsPerSecond) -> [Float] {
        let size = max(1, Int(sampleRate) / binsPerSecond)
        let count = (samples.count + size - 1) / size
        var out = [Float](repeating: 0, count: count)
        samples.withUnsafeBufferPointer { buf in
            for bin in 0..<count {
                var peak: Float = 0
                let end = min(buf.count, (bin + 1) * size)
                var i = bin * size
                while i < end {
                    let v = abs(buf[i])
                    if v > peak { peak = v }
                    i += 1
                }
                out[bin] = peak
            }
        }
        return out
    }

    /// Scales so the loudest 0.5 % of bins reach 1, so quiet recordings still draw a shape.
    public static func normalize(_ peaks: [Float]) -> [Float] {
        guard !peaks.isEmpty else { return peaks }
        let sorted = peaks.sorted()
        let ref = max(0.01, sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.995))])
        return peaks.map { min(1, $0 / ref) }
    }

    /// The highest peak between two times.
    public static func peak(in peaks: [Float], from start: Double, to end: Double, binsPerSecond: Int = binsPerSecond) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let lo = Swift.max(0, Int(start * Double(binsPerSecond)))
        let hi = Swift.min(peaks.count, Swift.max(lo + 1, Int((end * Double(binsPerSecond)).rounded(.up))))
        guard lo < hi else { return 0 }
        var m: Float = 0
        for i in lo..<hi where peaks[i] > m { m = peaks[i] }
        return m
    }

    /// How loud a stretch is, for one waveform bar: the mean of its bins' peaks. A bar over a few seconds of
    /// talk with pauses stays below a bar of solid talk, and silence stays low, where the single highest peak
    /// draws almost every bar of a zoomed-out conversation at full height. One bin per bar: the peak itself.
    public static func level(in peaks: [Float], from start: Double, to end: Double, binsPerSecond: Int = binsPerSecond) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let lo = Swift.max(0, Int(start * Double(binsPerSecond)))
        let hi = Swift.min(peaks.count, Swift.max(lo + 1, Int((end * Double(binsPerSecond)).rounded(.up))))
        guard lo < hi else { return 0 }
        var sum: Float = 0
        for i in lo..<hi { sum += peaks[i] }
        return sum / Float(hi - lo)
    }

    /// Height (0...1) of the waveform bar for `start..<end`. Zoomed in, a 36 dB scale gives quiet syllables
    /// shape; zoomed out, the range narrows to 24 dB so solid talk, talk with pauses and silence come apart.
    public static func barHeight(in peaks: [Float], from start: Double, to end: Double, binsPerSecond: Int = binsPerSecond) -> Float {
        let bins = Swift.max(1, (end - start) * Double(binsPerSecond))
        let range = Float(36 - 12 * Swift.min(1, log10(bins) / 2))
        return loudness(level(in: peaks, from: start, to: end, binsPerSecond: binsPerSecond), range: range)
    }

    /// Bar height for a peak on a loudness (decibel) scale over `range` dB, so quiet speech still
    /// has shape instead of looking flat next to the loudest moments.
    public static func loudness(_ peak: Float, range: Float = 36) -> Float {
        guard peak > 0 else { return 0 }
        let db = 20 * log10(min(1, peak))
        return max(0, min(1, (db + range) / range))
    }

    public static func encode(_ peaks: [Float]) -> Data {
        peaks.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
