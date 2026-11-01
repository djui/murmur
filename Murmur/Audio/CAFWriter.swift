import AVFoundation
import Foundation

/// Writes one mono track as 16-bit PCM in a CAF file that is readable at every moment, so a recording
/// survives the app being killed, crashing or the power going. The header is complete from the first
/// byte (the data chunk's size is "to the end of the file"); samples are appended on a queue of their own
/// and synced to storage every few seconds. AAC in .m4a, by contrast, is unreadable until it is closed;
/// `encode(_:to:)` turns a finished CAF into one.
final class CAFWriter: @unchecked Sendable {
    let url: URL
    let sampleRate: Double
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "Murmur.CAFWriter")
    private let lock = NSLock()
    private var frames: Int64 = 0
    private var failure: Error?
    private var lastSync = Date()
    private var converter: AVAudioConverter?
    private var closed = false

    init(url: URL, sampleRate: Double) throws {
        self.url = url
        self.sampleRate = sampleRate
        guard FileManager.default.createFile(atPath: url.path, contents: Self.header(sampleRate: sampleRate)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    var seconds: Double { lock.withLock { Double(frames) / sampleRate } }

    /// Why writing stopped (storage full, most likely), or nil.
    var error: Error? { lock.withLock { failure } }

    /// Appends mono samples at any rate (a Bluetooth microphone can change it mid-recording), from any thread.
    func write(_ samples: [Float], sampleRate rate: Double) {
        guard !samples.isEmpty else { return }
        queue.async { [self] in
            guard !closed, error == nil else { return }
            let samples = rate == sampleRate ? samples : resample(samples, from: rate)
            var data = Data(count: samples.count * 2)
            data.withUnsafeMutableBytes { raw in
                let out = raw.bindMemory(to: Int16.self)
                for (i, s) in samples.enumerated() { out[i] = Int16(max(-1, min(1, s)) * 32767).littleEndian }
            }
            do {
                try handle.write(contentsOf: data)
                // Written bytes survive the app being killed; syncing keeps them if the power goes too.
                if Date().timeIntervalSince(lastSync) > 5 {
                    try handle.synchronize()
                    lastSync = Date()
                }
                lock.withLock { frames += Int64(samples.count) }
            } catch {
                lock.withLock { failure = error }
            }
        }
    }

    /// Waits for every write so far, then closes the file.
    func close() {
        queue.sync {
            guard !closed else { return }
            closed = true
            try? handle.synchronize()
            try? handle.close()
        }
    }

    private func resample(_ samples: [Float], from rate: Double) -> [Float] {
        let input = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let output = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        if converter?.inputFormat.sampleRate != rate { converter = AVAudioConverter(from: input, to: output) }
        guard let converter,
              let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(samples.count)),
              let target = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(Double(samples.count) * sampleRate / rate) + 64)
        else { return [] }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        var given = false
        _ = converter.convert(to: target, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return source
        }
        return Array(UnsafeBufferPointer(start: target.floatChannelData![0], count: Int(target.frameLength)))
    }

    /// The CAF header: file header, audio description (16-bit little-endian mono PCM), and a data chunk
    /// of unknown size, which a reader takes to run to the end of the file.
    static func header(sampleRate: Double) -> Data {
        var d = Data()
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func i64(_ v: Int64) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func tag(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        tag("caff"); u16(1); u16(0)
        tag("desc"); i64(32)
        withUnsafeBytes(of: sampleRate.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        tag("lpcm")
        u32(2) // kCAFLinearPCMFormatFlagIsLittleEndian
        u32(2); u32(1); u32(1); u32(16) // bytes per packet, frames per packet, channels, bits
        tag("data"); i64(-1)
        u32(0) // edit count
        return d
    }

    /// A CAF (closed, or cut off) as AAC; its length in seconds. Throws, and leaves no file, if the result
    /// isn't whole, so the caller can fall back to the CAF.
    static func encode(_ caf: URL, to m4a: URL) throws -> Double {
        try? FileManager.default.removeItem(at: m4a)
        let input = try AVAudioFile(forReading: caf)
        let writer = try StemWriter(url: m4a, sampleRate: input.processingFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 1 << 16) else {
            throw CocoaError(.fileReadUnknown)
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            writer.write(Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))))
        }
        let result = writer.finish()
        guard let check = try? AVAudioFile(forReading: m4a),
              abs(Double(check.length) / check.processingFormat.sampleRate - result.seconds) < 1 else {
            try? FileManager.default.removeItem(at: m4a)
            throw CocoaError(.fileWriteUnknown)
        }
        return result.seconds
    }

    /// A CAF's length in seconds, or nil if it can't be read.
    static func length(of caf: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: caf) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }
}
