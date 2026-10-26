import AVFoundation
import Foundation

/// Reads the audio of any file AVFoundation understands as mono Float samples.
enum AudioDecoder {
    struct Info {
        var duration: Double
        var hasVideo: Bool
        var hasAudio: Bool
    }

    static func info(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        return Info(duration: duration.isFinite ? duration : 0, hasVideo: !video.isEmpty, hasAudio: !audio.isEmpty)
    }

    /// All audio tracks mixed to mono at `sampleRate`, optionally only between two times.
    static func decode(_ url: URL, sampleRate: Double = 16_000, from start: Double? = nil, to end: Double? = nil) async throws -> [Float] {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw DecodeError.noAudio }
        var duration = try await asset.load(.duration).seconds

        let reader = try AVAssetReader(asset: asset)
        if let start, let end, end > start {
            reader.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                           end: CMTime(seconds: end, preferredTimescale: 600))
            duration = end - start
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? DecodeError.unreadable }

        var samples: [Float] = []
        if duration.isFinite, duration > 0 { samples.reserveCapacity(Int(duration * sampleRate) + 1024) }
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: count))
            samples.withUnsafeMutableBytes { raw in
                _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                               destination: raw.baseAddress! + start * MemoryLayout<Float>.size)
            }
        }
        if reader.status == .failed { throw reader.error ?? DecodeError.unreadable }
        return samples
    }

    enum DecodeError: LocalizedError {
        case noAudio, unreadable
        var errorDescription: String? {
            switch self {
            case .noAudio: "The file has no audio track."
            case .unreadable: "The file could not be read."
            }
        }
    }
}
