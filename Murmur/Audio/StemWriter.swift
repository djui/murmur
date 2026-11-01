import AVFoundation
import Foundation

/// Writes one mono track as AAC, from any thread (calls must not overlap).
final class StemWriter: @unchecked Sendable {
    struct Result { let url: URL; let seconds: Double }

    let url: URL
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var frames: Int64 = 0
    private var closed = false

    init(url: URL, sampleRate: Double) throws {
        self.url = url
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    var seconds: Double { lock.withLock { Double(frames) / format.sampleRate } }

    func write(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        lock.withLock {
            guard !closed else { return }
            try? file.write(from: buffer)
            frames += Int64(samples.count)
        }
    }

    func finish() -> Result {
        lock.withLock {
            closed = true
            file.close()
            return Result(url: url, seconds: Double(frames) / format.sampleRate)
        }
    }
}
