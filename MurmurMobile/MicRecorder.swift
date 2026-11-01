import AVFoundation
import Foundation
import MurmurCore
import Observation
import Voz

/// Records the microphone with a live transcript, then turns the recording into a project. Unlike the
/// Mac app there is one track: everyone in the room is on it, and Who tells them apart afterwards.
@Observable
@MainActor
final class MicRecorder {
    enum State { case idle, starting, recording, paused, finishing }

    struct Line: Identifiable, Equatable {
        let id: Int
        let start: Double
        let text: String
        let tentative: Bool
    }

    var state: State = .idle
    var elapsed: Double = 0
    var level: Float = 0
    var history: [Float] = Array(repeating: 0, count: 90)
    var lines: [Line] = []
    var marks: [Mark] = []
    var liveAvailable = false
    var error: String?
    var startedAt = Date()

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var writer: StemWriter?
    @ObservationIgnored private var live: LiveTranscriber?
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let paused = Flag()
    @ObservationIgnored private var interruption: NSObjectProtocol?

    var isActive: Bool { state == .recording || state == .paused }

    var title: String { "Recording · " + startedAt.formatted(date: .abbreviated, time: .shortened) }

    func start() async {
        guard state == .idle else { return }
        state = .starting
        error = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Murmur can’t use the microphone. Allow it in Settings › Apps › Murmur."
            state = .idle
            return
        }
        startedAt = Date()
        elapsed = 0
        lines = []
        marks = []
        paused.set(false)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            fail(error)
            return
        }

        // Live transcription needs the transcriber; recording works without it.
        liveAvailable = Engines.shared.isDownloaded(.voz)
        if liveAvailable, let voz = try? await Engines.shared.voz() {
            let transcriber = voz.liveTranscriber(configuration: Voz.LiveConfiguration())
            live = transcriber
            listen(transcriber)
        } else {
            liveAvailable = false
        }

        do {
            let stamp = startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
            let url = Library.mediaFolder.appendingPathComponent("Recording \(stamp).m4a")
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { throw RecorderError.noMicrophone }
            let writer = try StemWriter(url: url, sampleRate: format.sampleRate)
            let live = self.live, paused = self.paused
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard !paused.isSet else { return }
                let samples = Self.mono(buffer)
                writer.write(samples)
                if let live { Task { await live.append(samples, sampleRate: format.sampleRate) } }
                let level = Self.rms(samples)
                DispatchQueue.main.async { self?.level = level }
            }
            engine.prepare()
            try engine.start()
            self.engine = engine
            self.writer = writer
            file = url
        } catch {
            fail(error)
            return
        }

        // A phone call or Siri pauses the recording; it carries on when they let go of the microphone.
        interruption = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                if type == .began, self.state == .recording { self.togglePause() }
                if type == .ended, self.state == .paused { try? self.engine?.start() }
            }
        }

        state = .recording
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func listen(_ live: LiveTranscriber) {
        Task { [weak self] in
            for await update in live.updates {
                let words = update.committedWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), false) }
                    + update.tentativeWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), true) }
                await MainActor.run { self?.lines = Self.lines(words) }
            }
        }
    }

    /// Words into lines at pauses longer than 1.5 s.
    static func lines(_ words: [(MurmurCore.Word, Bool)]) -> [Line] {
        var out: [Line] = []
        var current: [(MurmurCore.Word, Bool)] = []
        func close() {
            guard let first = current.first else { return }
            out.append(Line(id: Int(first.0.start * 100), start: first.0.start, text: Merge.join(current.map(\.0)),
                            tentative: current.contains { $0.1 }))
            current = []
        }
        for item in words {
            if let last = current.last, item.0.start - last.0.end > 1.5 { close() }
            current.append(item)
        }
        close()
        return Array(out.suffix(200))
    }

    private func tick() {
        guard state == .recording else { return }
        elapsed = writer?.seconds ?? 0
        history.removeFirst()
        history.append(level)
    }

    func togglePause() {
        switch state {
        case .recording: paused.set(true); state = .paused; level = 0
        case .paused: paused.set(false); state = .recording
        default: break
        }
    }

    /// Keeps the last 20 seconds and the next 5 as a mark, as ⌥⌘M does on the Mac.
    func addMark() {
        guard isActive else { return }
        let t = elapsed
        marks.append(Mark(name: "Moment at \(Timecode.short(t))", start: max(0, t - 20), end: t + 5))
    }

    /// Stops and returns the new project, or nil if nothing was recorded.
    func stop() async -> URL? {
        guard isActive else { return nil }
        state = .finishing
        defer { reset() }
        stopAudio()
        await live?.finish()
        live = nil
        guard let result = writer?.finish(), result.seconds > 0.5 else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return nil
        }
        do {
            var project = Project()
            project.media = MediaRef.make(for: result.url, hasVideo: false)
            project.duration = result.seconds
            project.title = title
            project.titleIsGenerated = true
            project.marks = marks.map { Mark(id: $0.id, name: $0.name, start: $0.start, end: min($0.end, result.seconds)) }
            project.createdAt = startedAt
            project.settings.enhance = AppSettings.bool(AppSettings.enhanceNewProjects)
            let url = ProjectFile.newURL(named: title.replacingOccurrences(of: "·", with: "-"))
            try ProjectFile.write(project, to: url)
            Library.shared.reload()
            return url
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Stops without keeping anything.
    func discard() {
        guard isActive else { return }
        stopAudio()
        _ = writer?.finish()
        if let file { try? FileManager.default.removeItem(at: file) }
        Task { await live?.finish(); live = nil }
        reset()
    }

    private func stopAudio() {
        timer?.invalidate()
        timer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        if let interruption { NotificationCenter.default.removeObserver(interruption) }
        interruption = nil
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    private func reset() {
        writer = nil
        file = nil
        state = .idle
        level = 0
        history = Array(repeating: 0, count: history.count)
    }

    private func fail(_ error: Error) {
        stopAudio()
        reset()
        self.error = error.localizedDescription
    }

    nonisolated static func mono(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        let n = Int(buffer.frameLength), channels = Int(buffer.format.channelCount)
        guard channels > 1 else { return Array(UnsafeBufferPointer(start: data[0], count: n)) }
        var out = [Float](repeating: 0, count: n)
        for c in 0..<channels { for i in 0..<n { out[i] += data[c][i] } }
        let scale = 1 / Float(channels)
        for i in 0..<n { out[i] *= scale }
        return out
    }

    nonisolated static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return min(1, (sum / Float(samples.count)).squareRoot() * 4)
    }

    /// A Bool shared with the audio thread.
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var isSet: Bool { lock.withLock { value } }
        func set(_ v: Bool) { lock.withLock { value = v } }
    }

    enum RecorderError: LocalizedError {
        case noMicrophone
        var errorDescription: String? { "No microphone is available." }
    }
}
