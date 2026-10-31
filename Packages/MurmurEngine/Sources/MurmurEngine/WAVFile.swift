import Foundation

/// 16-bit PCM mono WAV, which every Windows player and Media Foundation read without codecs.
public enum WAVFile {
    public static func data(_ samples: [Float], sampleRate: Int) -> Data {
        var out = Data(capacity: 44 + samples.count * 2)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        out.append(contentsOf: Array("RIFF".utf8)); append(36 + bytes)
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16))
        append(UInt16(1)) // PCM
        append(UInt16(1)) // mono
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2)) // bytes per second
        append(UInt16(2)) // block align
        append(UInt16(16)) // bits per sample
        out.append(contentsOf: Array("data".utf8)); append(bytes)
        for s in samples { append(Int16((max(-1, min(1, s)) * Float(Int16.max)).rounded())) }
        return out
    }

    public static func write(_ samples: [Float], sampleRate: Int, to url: URL) throws {
        try data(samples, sampleRate: sampleRate).write(to: url, options: .atomic)
    }
}
