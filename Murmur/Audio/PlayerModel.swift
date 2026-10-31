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
        player.replaceCurrentItem(with: url.map {
            let item = AVPlayerItem(url: $0)
            item.audioTimePitchAlgorithm = .timeDomain
            return item
        })
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
