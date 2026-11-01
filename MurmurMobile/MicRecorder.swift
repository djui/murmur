import AVFoundation
import Foundation
import MurmurCore
import Observation
import Voz
import Who

/// Records the microphone with a live transcript, then turns the recording into a project. Unlike the
/// Mac app there is one track: everyone in the room is on it. While recording, Who runs again every
/// few seconds on what it has, so lines carry a provisional voice ("Voice A"); the speakers are
/// settled by the full transcription after the recording stops.
@Observable
@MainActor
final class MicRecorder {
    enum State { case idle, starting, recording, paused, finishing }

    struct Line: Identifiable, Equatable {
        let id: Int
        let start: Double
        let end: Double
        let text: String
        let tentative: Bool
        /// The provisional voice, 0 = "Voice A", by first appearance; nil until Who has heard it.
        var voice: Int?
    }

    var state: State = .idle
    var elapsed: Double = 0
    var level: Float = 0
    var history: [Float] = Array(repeating: 0, count: 90)
    var lines: [Line] = []
    /// Voices Who has told apart so far.
    var voiceCount = 0
    var marks: [Mark] = []
    var liveAvailable = false
    /// Voz is downloaded but could not be loaded for the live transcript.
    var liveFailed = false
    var error: String?
    var startedAt = Date()

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var writer: StemWriter?
    @ObservationIgnored private var live: LiveTranscriber?
    @ObservationIgnored private var file: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let paused = Flag()
    @ObservationIgnored private var interruption: NSObjectProtocol?
    @ObservationIgnored private let audio = VoiceBuffer()
    /// Provisional turns on the recording's clock, voices numbered by first appearance.
    @ObservationIgnored private var turns: [Turn] = []
    @ObservationIgnored private var voices: Task<Void, Never>?

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
        turns = []
        voiceCount = 0
        audio.reset()
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
        liveFailed = false
        if liveAvailable, let voz = try? await Engines.shared.voz() {
            let transcriber = voz.liveTranscriber(configuration: Voz.LiveConfiguration())
            live = transcriber
            listen(transcriber)
        } else {
            liveFailed = liveAvailable
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
            let live = self.live, paused = self.paused, audio = self.audio
            input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard !paused.isSet else { return }
                let samples = Self.mono(buffer)
                writer.write(samples)
                audio.append(samples, sampleRate: format.sampleRate)
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
        if Engines.shared.isDownloaded(.who) { listenForVoices() }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func listen(_ live: LiveTranscriber) {
        Task { [weak self] in
            for await update in live.updates {
                let words = update.committedWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), false) }
                    + update.tentativeWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), true) }
                await MainActor.run {
                    guard let self else { return }
                    self.lines = self.labelled(Self.lines(words))
                }
            }
        }
    }

    /// Words into lines at pauses longer than 1.5 s.
    static func lines(_ words: [(MurmurCore.Word, Bool)]) -> [Line] {
        var out: [Line] = []
        var current: [(MurmurCore.Word, Bool)] = []
        func close() {
            guard let first = current.first else { return }
            out.append(Line(id: Int(first.0.start * 100), start: first.0.start, end: current.last?.0.end ?? first.0.end,
                            text: Merge.join(current.map(\.0)), tentative: current.contains { $0.1 }))
            current = []
        }
        for item in words {
            if let last = current.last, item.0.start - last.0.end > 1.5 { close() }
            current.append(item)
        }
        close()
        return Array(out.suffix(200))
    }

    // MARK: Provisional voices

    /// Who on the last five minutes (one pass, ~0.3 s on a Mac's Neural Engine), every 10 seconds.
    private func listenForVoices() {
        voices = Task { [weak self] in
            await Engines.shared.warmUp(.who)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self, self.isActive else { continue }
                let window = self.audio.last(seconds: 300)
                guard window.samples.count > Int(VoiceBuffer.rate * 4) else { continue }
                let result = await Task.detached(priority: .utility) {
                    try? await Engines.shared.who.diarize(samples: window.samples, sampleRate: VoiceBuffer.rate)
                }.value
                guard let result, !Task.isCancelled else { continue }
                self.adopt(result, offset: window.start)
            }
        }
    }

    /// Takes a run's turns for its window, keeping earlier voices' letters: each speaker of this run
    /// becomes the voice it overlaps most in the previous run, or a new voice.
    private func adopt(_ result: Diarization, offset: Double) {
        let shifted = result.turns.map { Turn(start: $0.start + offset, end: $0.end + offset, speaker: $0.speaker) }
        var mapping: [Int: Int] = [:]
        var taken: Set<Int> = []
        let bySpeaker = Dictionary(grouping: shifted, by: \.speaker)
        // Longest speakers choose first, so a short new voice can't take a long one's letter.
        for (speaker, own) in bySpeaker.sorted(by: { Self.length($0.value) > Self.length($1.value) }) {
            var best: (voice: Int, overlap: Double)?
            for voice in Set(turns.map(\.speaker)).subtracting(taken) {
                let overlap = Self.overlap(own, turns.filter { $0.speaker == voice })
                if overlap > 0.5, overlap > (best?.overlap ?? 0) { best = (voice, overlap) }
            }
            let voice = best?.voice ?? (Set(turns.map(\.speaker)).union(mapping.values).max().map { $0 + 1 } ?? 0)
            mapping[speaker] = voice
            taken.insert(voice)
        }
        turns = turns.filter { $0.end <= offset } + shifted.map { Turn(start: $0.start, end: $0.end, speaker: mapping[$0.speaker] ?? 0) }
        voiceCount = Set(turns.map(\.speaker)).count
        lines = labelled(lines)
    }

    /// Each line's voice: the one heard most between its first and last word.
    private func labelled(_ lines: [Line]) -> [Line] {
        guard !turns.isEmpty else { return lines }
        return lines.map { line in
            var line = line
            var talk: [Int: Double] = [:]
            for t in turns where t.end > line.start && t.start < line.end {
                talk[t.speaker, default: 0] += min(t.end, line.end) - max(t.start, line.start)
            }
            line.voice = talk.max { $0.value < $1.value }?.key
            return line
        }
    }

    private static func length(_ turns: [Turn]) -> Double { turns.reduce(0) { $0 + $1.duration } }

    private static func overlap(_ a: [Turn], _ b: [Turn]) -> Double {
        var sum = 0.0
        for x in a { for y in b where y.end > x.start && y.start < x.end { sum += min(x.end, y.end) - max(x.start, y.start) } }
        return sum
    }

    static func voiceName(_ voice: Int) -> String {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return "Voice " + (voice < letters.count ? String(letters[voice]) : "\(voice + 1)")
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
        voices?.cancel()
        voices = nil
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

    /// The recording at 16 kHz mono for Who, filled from the audio thread. Holds 5 minutes plus a
    /// little; older audio is dropped (Who runs on the last five minutes).
    final class VoiceBuffer: @unchecked Sendable {
        static let rate = 16_000.0
        private let lock = NSLock()
        private var samples: [Float] = []
        /// Seconds of audio dropped from the front.
        private var dropped = 0.0
        private var carry: [Float] = []

        func reset() { lock.withLock { samples = []; dropped = 0; carry = [] } }

        /// Downsamples by averaging (48 kHz → every 3 samples), plenty for telling voices apart.
        func append(_ input: [Float], sampleRate: Double) {
            let step = max(1, Int((sampleRate / Self.rate).rounded()))
            lock.withLock {
                carry += input
                let whole = carry.count / step * step
                var out = [Float](repeating: 0, count: whole / step)
                for i in 0..<out.count {
                    var s: Float = 0
                    for j in 0..<step { s += carry[i * step + j] }
                    out[i] = s / Float(step)
                }
                carry.removeFirst(whole)
                samples += out
                let limit = Int(Self.rate * 330)
                if samples.count > limit {
                    let cut = samples.count - Int(Self.rate * 300)
                    samples.removeFirst(cut)
                    dropped += Double(cut) / Self.rate
                }
            }
        }

        /// The last `seconds` and where they start on the recording's clock.
        func last(seconds: Double) -> (samples: [Float], start: Double) {
            lock.withLock {
                let n = min(samples.count, Int(seconds * Self.rate))
                return (Array(samples.suffix(n)), dropped + Double(samples.count - n) / Self.rate)
            }
        }
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
