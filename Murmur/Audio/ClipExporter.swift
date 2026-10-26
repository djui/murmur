import AVFoundation
import Foundation

/// Cuts sections out of the media as audio (.m4a) or video (.mp4) files.
enum ClipExporter {
    struct Clip {
        var name: String
        var start: Double
        var end: Double
    }

    /// Exports `clips` from `source`. `joined` writes one file at `destination`; otherwise one file
    /// per clip is written into the folder `destination`. Returns the written files.
    /// `bleeps` are times in the source to cover with a tone (hidden personal details); they apply to
    /// audio clips.
    static func export(source: URL, clips: [Clip], video: Bool, joined: Bool, destination: URL,
                       bleeps: [ClosedRange<Double>] = []) async throws -> [URL] {
        let asset = AVURLAsset(url: source)
        if joined {
            let url = destination
            try await write(asset: asset, clips: clips, video: video, to: url)
            if !video { try await bleep(url, ranges: offsets(bleeps, in: clips)) }
            return [url]
        }
        var out: [URL] = []
        for (i, clip) in clips.enumerated() {
            let base = clip.name.isEmpty ? "Clip \(i + 1)" : clip.name
            let safe = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            let url = destination.appendingPathComponent(safe).appendingPathExtension(video ? "mp4" : "m4a")
            try? FileManager.default.removeItem(at: url)
            try await write(asset: asset, clips: [clip], video: video, to: url)
            if !video { try await bleep(url, ranges: offsets(bleeps, in: [clip])) }
            out.append(url)
        }
        return out
    }

    /// Bleep ranges moved onto the clip's own timeline (clips are laid end to end).
    static func offsets(_ bleeps: [ClosedRange<Double>], in clips: [Clip]) -> [ClosedRange<Double>] {
        var out: [ClosedRange<Double>] = []
        var cursor = 0.0
        for clip in clips {
            for b in bleeps where b.upperBound > clip.start && b.lowerBound < clip.end {
                out.append((max(b.lowerBound, clip.start) - clip.start + cursor)...(min(b.upperBound, clip.end) - clip.start + cursor))
            }
            cursor += clip.end - clip.start
        }
        return out
    }

    /// Rewrites an audio file with a 1 kHz tone in place of the given ranges.
    static func bleep(_ url: URL, ranges: [ClosedRange<Double>]) async throws {
        guard !ranges.isEmpty else { return }
        let rate = 44_100.0
        var samples = try await AudioDecoder.decode(url, sampleRate: rate)
        for r in ranges {
            let lo = max(0, Int(r.lowerBound * rate)), hi = min(samples.count, Int(r.upperBound * rate))
            guard lo < hi else { continue }
            for i in lo..<hi { samples[i] = 0.25 * sin(2 * .pi * 1000 * Float(i) / Float(rate)) }
        }
        let temp = url.deletingLastPathComponent().appendingPathComponent(".bleep-\(UUID().uuidString).m4a")
        let writer = try StemWriter(url: temp, sampleRate: rate)
        writer.write(samples)
        _ = writer.finish()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }

    private static func write(asset: AVURLAsset, clips: [Clip], video: Bool, to url: URL) async throws {
        let composition = AVMutableComposition()
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = video ? try await asset.loadTracks(withMediaType: .video) : []
        var targets: [(AVAssetTrack, AVMutableCompositionTrack)] = []
        for track in audioTracks + videoTracks {
            if let target = composition.addMutableTrack(withMediaType: track.mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) {
                targets.append((track, target))
            }
        }
        var cursor = CMTime.zero
        for clip in clips {
            let range = CMTimeRange(start: CMTime(seconds: clip.start, preferredTimescale: 600),
                                    end: CMTime(seconds: clip.end, preferredTimescale: 600))
            for (source, target) in targets {
                try target.insertTimeRange(range, of: source, at: cursor)
            }
            cursor = cursor + range.duration
        }
        let preset = video ? AVAssetExportPresetHighestQuality : AVAssetExportPresetAppleM4A
        guard let session = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try? FileManager.default.removeItem(at: url)
        try await session.export(to: url, as: video ? .mp4 : .m4a)
    }
}
