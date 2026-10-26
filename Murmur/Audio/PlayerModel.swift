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
    private(set) var url: URL?
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var stopAt: Double?

    init() {
        player.automaticallyWaitsToMinimizeStalling = false
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            MainActor.assumeIsolated { self?.tick(t.seconds) }
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        time = seconds
        isPlaying = player.rate != 0
        if let stopAt, seconds >= stopAt {
            player.pause()
            self.stopAt = nil
            isPlaying = false
        }
    }

    /// Switches to `url`, keeping the playhead position.
    func load(_ url: URL?, duration: Double) {
        self.duration = duration
        guard url != self.url else { return }
        let keep = time
        self.url = url
        player.replaceCurrentItem(with: url.map { AVPlayerItem(url: $0) })
        if keep > 0 { seek(to: keep) }
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
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(by delta: Double) { seek(to: time + delta) }

    /// Plays one section and stops at its end.
    func play(from start: Double, to end: Double) {
        seek(to: start)
        stopAt = end
        player.play()
        isPlaying = true
    }
}
