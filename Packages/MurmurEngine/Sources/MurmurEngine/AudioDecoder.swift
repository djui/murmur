#if canImport(AVFoundation)
import AVFoundation
#elseif os(Windows)
import CMediaFoundation
#endif
import Foundation

/// Reads the audio of a media file as mono Float samples: AVFoundation on the Mac, Media Foundation
/// on Windows.
public enum AudioDecoder {
    public struct Info: Sendable {
        public var duration: Double
        public var hasVideo: Bool
        public var hasAudio: Bool
    }

    public enum DecodeError: LocalizedError {
        case noAudio, unreadable
        case system(Int32)
        public var errorDescription: String? {
            switch self {
            case .noAudio: "The file has no audio track."
            case .unreadable: "The file could not be read."
            case .system(let hr): "The file could not be read (0x\(String(UInt32(bitPattern: hr), radix: 16)))."
            }
        }
    }

    #if canImport(AVFoundation)
    public static func info(_ url: URL) async throws -> Info {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        return Info(duration: duration.isFinite ? duration : 0, hasVideo: !video.isEmpty, hasAudio: !audio.isEmpty)
    }

    /// All audio tracks mixed to mono at `sampleRate`, optionally only between two times.
    public static func decode(_ url: URL, sampleRate: Double = 16_000, from start: Double? = nil, to end: Double? = nil) async throws -> [Float] {
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
    #elseif os(Windows)
    public static func info(_ url: URL) async throws -> Info {
        var info = MFMediaInfo()
        let hr = url.nativePath.withCString(encodedAs: UTF16.self) { mf_probe($0, &info) }
        guard hr == 0 else { throw DecodeError.system(hr) }
        return Info(duration: info.duration, hasVideo: info.hasVideo != 0, hasAudio: info.hasAudio != 0)
    }

    /// The first audio track mixed to mono at `sampleRate`, optionally only between two times.
    public static func decode(_ url: URL, sampleRate: Double = 16_000, from start: Double? = nil, to end: Double? = nil) async throws -> [Float] {
        var lo = -1.0, hi = -1.0
        if let start, let end, end > start { lo = start; hi = end }
        let path = url.nativePath
        return try await Task.detached(priority: .userInitiated) { [lo, hi] in
            var pointer: UnsafeMutablePointer<Float>?
            var count = 0
            let hr = path.withCString(encodedAs: UTF16.self) { mf_decode_mono($0, sampleRate, lo, hi, &pointer, &count) }
            guard hr == 0 else { throw DecodeError.system(hr) }
            guard let pointer else { throw DecodeError.noAudio }
            defer { mf_free(pointer) }
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }.value
    }
    #endif
}

#if os(Windows)
extension URL {
    /// `C:\Users\…`, which Media Foundation wants, rather than URL's `/C:/Users/…`.
    var nativePath: String { withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? path }
}
#endif
