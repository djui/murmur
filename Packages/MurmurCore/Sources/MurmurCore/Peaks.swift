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

    public static func encode(_ peaks: [Float]) -> Data {
        peaks.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func decode(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
