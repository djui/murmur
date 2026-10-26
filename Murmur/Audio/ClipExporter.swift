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
    static func export(source: URL, clips: [Clip], video: Bool, joined: Bool, destination: URL) async throws -> [URL] {
        let asset = AVURLAsset(url: source)
        if joined {
            let url = destination
            try await write(asset: asset, clips: clips, video: video, to: url)
            return [url]
        }
        var out: [URL] = []
        for (i, clip) in clips.enumerated() {
            let base = clip.name.isEmpty ? "Clip \(i + 1)" : clip.name
            let safe = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
            let url = destination.appendingPathComponent(safe).appendingPathExtension(video ? "mp4" : "m4a")
            try? FileManager.default.removeItem(at: url)
            try await write(asset: asset, clips: [clip], video: video, to: url)
            out.append(url)
        }
        return out
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
