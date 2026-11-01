import AVFoundation
import Foundation
import Observation

/// Playback of the project's media, with the playhead published 30 times a second.
@Observable
@MainActor
final class PlayerModel {
    let player = AVPlayer()
    var time: Double = 0
    var duration: Double = 0
    var isPlaying = false
    /// Playback speed; pitch stays natural.
    var rate: Float = 1 {
        didSet {
            player.defaultRate = rate
            if isPlaying { player.rate = rate }
        }
    }
    static let rates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]
    private(set) var url: URL?
    private(set) var videoURL: URL?
    /// Why the video can't be shown on this Mac, e.g. AV1 without an AV1 decoder; nil when it plays.
    private(set) var videoProblem: String?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var stopAt: Double?
    /// Where a seek is headed until the player gets there. Ticks in between still report the old
    /// position; without this, a second skip would start from there.
    @ObservationIgnored private var seekTarget: Double?
    @ObservationIgnored private var seekCount = 0

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
    }

    /// The playhead read straight from the player while playing, for drawing at display rate between ticks.
    var displayTime: Double {
        guard isPlaying, player.rate != 0, seekTarget == nil else { return time }
        let t = player.currentTime().seconds
        return t.isFinite ? t : time
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        isPlaying = player.rate != 0
        guard seekTarget == nil else { return }
        time = seconds
        if let stopAt, seconds >= stopAt {
            player.pause()
            self.stopAt = nil
            isPlaying = false
        }
    }

    /// Switches to `url`, keeping the playhead position. With `video`, shows that file's picture,
    /// paired with the sound of `url` when it is another file (the enhanced audio).
    func load(_ url: URL?, video: URL? = nil, duration: Double) {
        self.duration = duration
        guard url != self.url || video != videoURL else { return }
        let keep = time
        self.url = url
        videoURL = video
        videoProblem = nil
        loading?.cancel()
        player.replaceCurrentItem(with: url.map { Self.item(AVURLAsset(url: $0)) })
        if keep > 0 { seek(to: keep) }
        guard let video else { return }
        loading = Task { [weak self] in
            guard let track = try? await AVURLAsset(url: video).loadTracks(withMediaType: .video).first else { return }
            let playable = (try? await track.load(.isPlayable)) ?? false
            guard let self, !Task.isCancelled else { return }
            if !playable {
                videoProblem = await Self.problem(with: track)
                return
            }
            guard let url, url != video,
                  let composed = await Self.compose(video: track, audio: AVURLAsset(url: url)),
                  !Task.isCancelled else { return }
            let keep = time
            player.replaceCurrentItem(with: Self.item(composed))
            seek(to: keep)
            if isPlaying { player.play() }
        }
    }

    private static func item(_ asset: AVAsset) -> AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .timeDomain
        return item
    }

    /// The picture of `video` with the sound of `audio`.
    private static func compose(video: AVAssetTrack, audio: AVURLAsset) async -> AVAsset? {
        guard let sound = try? await audio.loadTracks(withMediaType: .audio).first,
              let soundRange = try? await sound.load(.timeRange),
              let pictureRange = try? await video.load(.timeRange) else { return nil }
        let composition = AVMutableComposition()
        guard let v = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let a = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              (try? v.insertTimeRange(pictureRange, of: video, at: pictureRange.start)) != nil,
              (try? a.insertTimeRange(soundRange, of: sound, at: .zero)) != nil else { return nil }
        v.preferredTransform = (try? await video.load(.preferredTransform)) ?? .identity
        return composition
    }

    private static func problem(with track: AVAssetTrack) async -> String {
        let codec = (try? await track.load(.formatDescriptions))?.first?.mediaSubType
        if codec?.rawValue == kCMVideoCodecType_AV1 {
            return "This Mac can't play AV1 video; that needs an M3 chip or later. The sound plays as usual."
        }
        return "This Mac can't play this video's format. The sound plays as usual."
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        if duration > 0, time >= duration - 0.05 { seek(to: 0) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let t = max(0, min(duration > 0 ? duration : seconds, seconds))
        time = t
        seekTarget = t
        seekCount += 1
        let count = seekCount
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor [weak self] in
                // Only the latest seek clears the target; an earlier one finishing changes nothing.
                if let self, self.seekCount == count { self.seekTarget = nil }
            }
        }
    }

    func skip(by delta: Double) { seek(to: (seekTarget ?? displayTime) + delta) }

    /// One step slower (-1) or faster (+1) through `rates`.
    func changeRate(by step: Int) {
        let i = Self.rates.firstIndex { $0 >= rate } ?? Self.rates.count - 1
        rate = Self.rates[max(0, min(Self.rates.count - 1, i + step))]
    }

    static func label(_ rate: Float) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }

    /// Plays one section and stops at its end.
    func play(from start: Double, to end: Double) {
        seek(to: start)
        stopAt = end
        player.play()
        isPlaying = true
    }
}
