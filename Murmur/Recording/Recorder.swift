import AVFoundation
import Foundation
import MurmurCore
import Observation
import Voz

/// One line of the live transcript.
struct LiveLine: Identifiable, Equatable {
    let id: String
    let isMe: Bool
    let start: Double
    let text: String
    let tentative: Bool
}

/// Groups live words from both tracks into lines, dropping the remote side's echo on the mic.
enum LiveLines {
    static func build(mic rawMic: [(MurmurCore.Word, Bool)], system rawSystem: [(MurmurCore.Word, Bool)]) -> [LiveLine] {
        let mic = dedupe(rawMic), system = dedupe(rawSystem)
        let kept = Set(Merge.removeEcho(mic: mic.map(\.0), system: system.map(\.0)).map { "\($0.start)|\($0.text)" })
        let mine = mic.filter { kept.contains("\($0.0.start)|\($0.0.text)") }
        let all = (mine.map { ($0.0, $0.1, true) } + system.map { ($0.0, $0.1, false) }).sorted { $0.0.start < $1.0.start }
        var out: [LiveLine] = []
        var current: [(MurmurCore.Word, Bool, Bool)] = []
        func close() {
            guard let first = current.first else { return }
            out.append(LiveLine(id: "\(first.2 ? "m" : "s")\(Int(first.0.start * 100))", isMe: first.2, start: first.0.start,
                                text: Merge.join(current.map(\.0)), tentative: current.contains { $0.1 }))
            current = []
        }
        for item in all {
            if let last = current.last, last.2 != item.2 || item.0.start - last.0.end > 1.5 { close() }
            current.append(item)
        }
        close()
        return Array(out.suffix(300))
    }
}

extension LiveLines {
    /// Live passes can repeat the word where settled and tentative text meet; drop the echo.
    static func dedupe(_ words: [(MurmurCore.Word, Bool)]) -> [(MurmurCore.Word, Bool)] {
        var out: [(MurmurCore.Word, Bool)] = []
        for item in words {
            if let last = out.last, item.0.start - last.0.start < 0.6,
               Merge.normalized(last.0.text) == Merge.normalized(item.0.text) {
                continue
            }
            if let last = out.last, item.0.start < last.0.start { continue }
            out.append(item)
        }
        return out
    }
}

/// A Bool shared with the audio threads.
final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set(_ v: Bool) { lock.withLock { value = v } }
}

/// Records the microphone ("Me") and system audio ("Others") as two tracks with a live transcript,
/// then turns the recording into a project.
@Observable
@MainActor
final class RecordingController {
    enum State { case idle, starting, recording, paused, finishing }

    var state: State = .idle
    var isActive: Bool { state != .idle }
    var elapsed: Double = 0
    var micLevel: Float = 0
    var systemLevel: Float = 0
    var micHistory: [Float] = Array(repeating: 0, count: 140)
    var systemHistory: [Float] = Array(repeating: 0, count: 140)
    var lines: [LiveLine] = []
    var marks: [Mark] = []
    /// Notes written while recording, each at the moment its writing began.
    var notes: [Note] = []
    /// Bumped to put the cursor in the note field (from the strip, which has no field of its own).
    var noteFocusRequest = 0
    var warning: String?
    var strip = false
    var startedAt = Date()
    var systemSourceName = "All apps"
    var liveAvailable = true
    /// The speakers the microphone's echo is being cancelled for, when it is.
    var echoCancelledOn: String?

    @ObservationIgnored private let mic = MicrophoneEngine()
    /// When the microphone last finished starting.
    @ObservationIgnored private var micStartedAt = Date.distantPast
    /// A restart after the audio devices changed is under way; `restartPending` asks it for one more.
    @ObservationIgnored private var restarting = false
    @ObservationIgnored private var restartPending = false
    /// Set when voice processing keeps the engine restarting; the rest of the recording goes without it.
    @ObservationIgnored private var voiceProcessingUnstable = false
    @ObservationIgnored private var tap: SystemAudioTap?
    @ObservationIgnored private var micWriter: CAFWriter?
    @ObservationIgnored private var systemWriter: CAFWriter?
    @ObservationIgnored private var micLive: LiveTranscriber?
    @ObservationIgnored private var systemLive: LiveTranscriber?
    /// The tasks reading each live transcriber's updates; cancelled on stop.
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    @ObservationIgnored private var micWords: [(MurmurCore.Word, Bool)] = []
    @ObservationIgnored private var systemWords: [(MurmurCore.Word, Bool)] = []
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let paused = AtomicFlag()
    @ObservationIgnored private var levelTick = 0
    /// The system track's length at the last tick, to see whether the tap still delivers.
    @ObservationIgnored private var lastSystemSeconds = 0.0
    /// When the tap may next be restarted after it stopped delivering.
    @ObservationIgnored private var nextTapRestart = Date.distantPast

    var title: String { "Recording · " + startedAt.formatted(date: .abbreviated, time: .shortened) }

    // MARK: - Start

    func start() {
        guard state == .idle else { CompactPanelController.shared.show(); return }
        state = .starting
        warning = nil
        lines = []
        marks = []
        notes = []
        elapsed = 0
        micWords = []
        systemWords = []
        voiceProcessingUnstable = false
        lastSystemSeconds = 0
        nextTapRestart = .distantPast
        startedAt = Date()
        paused.set(false)
        Task { await begin() }
    }

    private func begin() async {
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            state = .idle
            AppState.shared.presentError(RecorderError.noMicrophone, title: "Murmur can’t use the microphone")
            return
        }
        let stamp = startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let folder = ProjectFile.defaultFolder.appendingPathComponent("Recordings/\(stamp)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        // Written first: a folder with a journal is a recording that hasn't become a project yet.
        Self.write(Journal(startedAt: startedAt, title: title, marks: [], notes: []), in: folder)

        // Live transcription needs the transcriber; recording works without it.
        liveAvailable = Engines.shared.isDownloaded(.voz)
        if liveAvailable, let voz = try? await Engines.shared.voz() {
            let config = Voz.LiveConfiguration()
            micLive = voz.liveTranscriber(configuration: config)
            systemLive = voz.liveTranscriber(configuration: config)
            listen(micLive!, isMe: true)
            listen(systemLive!, isMe: false)
        } else {
            liveAvailable = false
        }

        do {
            try await startMicrophoneEngine(writerIn: folder)
        } catch {
            await stopAudio()
            state = .idle
            AppState.shared.presentError(error, title: "Couldn’t start recording")
            return
        }
        startSystemAudio(into: folder)

        state = .recording
        CompactPanelController.shared.show()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Starts (or, after the audio devices changed, restarts) the microphone into the one `mic.caf`.
    /// Through speakers the microphone hears the call: cancel it with the system's echo canceller, the one
    /// FaceTime uses. With headphones the microphone is left as it is.
    private func startMicrophoneEngine(writerIn folder: URL) async throws {
        echoCancelledOn = nil
        if let route = OutputRoute.current(), route.isSpeakers, AppSettings.bool(AppSettings.cancelEcho), !voiceProcessingUnstable {
            do {
                try await startMicrophone(into: folder, voiceProcessing: true)
                echoCancelledOn = route.name
                micStartedAt = Date()
                return
            } catch {
                await mic.stop()
            }
        }
        try await startMicrophone(into: folder, voiceProcessing: false)
        micStartedAt = Date()
    }

    private func startMicrophone(into folder: URL, voiceProcessing: Bool) async throws {
        // One file for the whole recording; a restart keeps writing into it and resamples if the rate changed.
        let existing = micWriter
        let url = folder.appendingPathComponent("mic.caf")
        let live = micLive
        let paused = self.paused
        micWriter = try await mic.start(voiceProcessing: voiceProcessing, onChange: { [weak self] in
            self?.microphoneChanged()
        }) { [weak self] rate in
            let writer = try existing ?? CAFWriter(url: url, sampleRate: rate)
            return (writer, { samples in
                guard !paused.isSet else { return }
                writer.write(samples, sampleRate: rate)
                if let live { Task { await live.append(samples, sampleRate: rate) } }
                let level = rms(samples)
                DispatchQueue.main.async { self?.micLevel = level }
            })
        }
    }

    /// Plugging in headphones, switching speakers or another app taking the microphone stops the engine and
    /// it doesn't start again by itself: start it again, or the rest of the recording has no "Me". Changes
    /// come in bursts, and a restart takes a moment: one restart at a time, and one more after it if needed.
    private func microphoneChanged() {
        guard state == .recording || state == .paused else { return }
        if restarting { restartPending = true; return }
        restarting = true
        Task {
            repeat {
                restartPending = false
                await restartMicrophone()
            } while restartPending
            restarting = false
        }
    }

    /// After the audio devices changed: the microphone again, with silence for the moment it was gone so it
    /// stays in time with the system track, and echo cancellation decided again for the new output.
    private func restartMicrophone() async {
        guard state == .recording || state == .paused, let folder, let writer = micWriter else { return }
        // A change right after starting with voice processing is voice processing itself: don't loop.
        if echoCancelledOn != nil, Date().timeIntervalSince(micStartedAt) < 2 { voiceProcessingUnstable = true }
        await mic.stop()
        // Stopped meanwhile: the writer is closed and handed to saving; starting again would start a new file.
        guard state == .recording || state == .paused else { return }
        let behind = (systemWriter?.seconds ?? writer.seconds) - writer.seconds
        if behind > 0.05 {
            let silence = [Float](repeating: 0, count: Int(behind * writer.sampleRate))
            writer.write(silence, sampleRate: writer.sampleRate)
            if let live = micLive { Task { await live.append(silence, sampleRate: writer.sampleRate) } }
        }
        do {
            try await startMicrophoneEngine(writerIn: folder)
            // Stopped while this was starting: don't leave the microphone on.
            if !(state == .recording || state == .paused) { await mic.stop() }
        } catch {
            warning = "The microphone stopped when the audio devices changed: \(error.localizedDescription)"
        }
    }

    /// Starts (or, after it stopped delivering, restarts) the system audio tap into the one `system.caf`.
    private func startSystemAudio(into folder: URL) {
        let source = UserDefaults.standard.string(forKey: AppSettings.systemAudioSource) ?? ""
        let tap = SystemAudioTap()
        do {
            try tap.start(bundleID: source.isEmpty ? nil : source)
            guard let format = tap.format else { throw SystemAudioTap.TapError.message("No tap format") }
            let writer = try systemWriter ?? CAFWriter(url: folder.appendingPathComponent("system.caf"), sampleRate: format.sampleRate)
            let live = systemLive
            let paused = self.paused
            tap.onBuffer = { [weak self] buffer in
                guard !paused.isSet else { return }
                let samples = monoSamples(buffer)
                writer.write(samples, sampleRate: format.sampleRate)
                if let live { Task { await live.append(samples, sampleRate: format.sampleRate) } }
                let level = rms(samples)
                DispatchQueue.main.async { self?.systemLevel = level }
            }
            self.tap = tap
            systemWriter = writer
            systemSourceName = source.isEmpty ? "All apps"
                : SystemAudioTap.audioProcesses().first { $0.bundleID == source }?.name ?? source
        } catch {
            tap.stop()
            warning = "System audio isn’t being recorded: \(error.localizedDescription)"
        }
    }

    /// The tap is bound to the output device that was the default when it started; when that device changes
    /// or goes away (headphones switching to their call mode, a display sleeping) Core Audio stops calling it,
    /// silently. It delivers continuously otherwise, silence included, so a system track falling behind the
    /// microphone means the tap is gone: start it again, with silence for the time it was gone so the two
    /// tracks stay in time, or the rest of the recording has no "Others".
    private func checkSystemAudio() {
        guard let folder, let mic = micWriter, let system = systemWriter else { return }
        let seconds = system.seconds
        if seconds == lastSystemSeconds { systemLevel = 0 }
        lastSystemSeconds = seconds
        guard mic.seconds - seconds > 2, !restarting, Date() >= nextTapRestart else { return }
        nextTapRestart = Date().addingTimeInterval(5)
        tap?.onBuffer = nil
        tap?.stop()
        tap = nil
        let silence = [Float](repeating: 0, count: Int((mic.seconds - seconds) * system.sampleRate))
        system.write(silence, sampleRate: system.sampleRate)
        if let live = systemLive { Task { await live.append(silence, sampleRate: system.sampleRate) } }
        startSystemAudio(into: folder)
        if tap != nil, warning?.hasPrefix("System audio") == true { warning = nil }
    }

    private func listen(_ live: LiveTranscriber, isMe: Bool) {
        listeners.append(Task { [weak self] in
            for await update in live.updates {
                let words = update.committedWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), false) }
                    + update.tentativeWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), true) }
                await MainActor.run {
                    guard let self else { return }
                    if isMe { self.micWords = words } else { self.systemWords = words }
                    self.rebuildLines()
                }
            }
        })
    }

    private func rebuildLines() {
        lines = LiveLines.build(mic: micWords, system: systemWords)
    }

    private func tick() {
        guard state == .recording else { return }
        elapsed = max(micWriter?.seconds ?? 0, systemWriter?.seconds ?? 0)
        if let error = micWriter?.error ?? systemWriter?.error {
            // The disk is full, most likely: keep what was recorded.
            stop()
            AppState.shared.presentError(error, title: "Recording stopped; what was recorded is kept")
            return
        }
        micHistory.removeFirst()
        micHistory.append(micLevel)
        checkSystemAudio()
        systemHistory.removeFirst()
        systemHistory.append(systemLevel)
    }

    // MARK: - Controls

    func togglePause() {
        switch state {
        case .recording: paused.set(true); state = .paused
        case .paused: paused.set(false); state = .recording
        default: break
        }
    }

    func addMark() {
        guard isActive else { return }
        let t = elapsed
        let mark = Mark(name: "Moment at \(Timecode.short(t))", start: max(0, t - 20), end: t + 5)
        marks.append(mark)
        saveJournal()
    }

    /// Keeps a note at `time`, the moment its writing began, so slow typing doesn't move it.
    func addNote(_ text: String, at time: Double) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isActive, !text.isEmpty else { return }
        notes.append(Note(text: text, time: min(time, elapsed)))
        saveJournal()
    }

    /// Opens the panel, if shrunk to the strip, with the cursor in the note field.
    func writeNote() {
        if strip { CompactPanelController.shared.setStrip(false) }
        CompactPanelController.shared.makeKey()
        noteFocusRequest += 1
    }

    private func saveJournal() {
        if let folder { Self.write(Journal(startedAt: startedAt, title: title, marks: marks, notes: notes), in: folder) }
    }

    /// Hands off at once: the panel goes and the library shows the recording being saved, with its progress,
    /// until it opens as a project. The live transcript isn't finished: the project transcribes it all again,
    /// and a last pass over a backlog would only hold up saving.
    func stop() {
        guard state == .recording || state == .paused else { return }
        state = .finishing
        timer?.invalidate()
        timer = nil
        let job = FinishingRecording(title: title, duration: elapsed)
        AppState.shared.finishing.append(job)
        CompactPanelController.shared.close()
        AppState.shared.showLibrary()
        listeners.forEach { $0.cancel() }
        listeners = []
        micLive = nil
        systemLive = nil
        let writers = [micWriter, systemWriter].compactMap { $0 }
        micWriter = nil
        systemWriter = nil
        Task {
            await stopAudio()
            // Closing waits for the writes still queued.
            await Task.detached(priority: .userInitiated) { writers.forEach { $0.close() } }.value
            saveJournal()
            let folder = self.folder
            self.folder = nil
            // Ready for the next recording while this one is saved.
            state = .idle
            guard let folder else {
                AppState.shared.finishing.removeAll { $0 === job }
                return
            }
            await Self.finish(folder, job: job, open: true)
        }
    }

    private func stopAudio() async {
        tap?.onBuffer = nil
        tap?.stop()
        tap = nil
        await mic.stop()
    }

    /// Makes the recording in `folder` a project, keeping `job` up to date, then opens it if `open`.
    private static func finish(_ folder: URL, job: FinishingRecording, open: Bool) async {
        let progress = FinishProgress()
        let poll = Task { @MainActor in
            while !Task.isCancelled {
                job.update(from: progress)
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        defer {
            poll.cancel()
            AppState.shared.finishing.removeAll { $0 === job }
        }
        do {
            guard let file = try await makeProject(in: folder, progress: progress) else { return }
            job.phase = "Opening…"
            job.fraction = 1
            AppState.shared.remember(file)
            if open { AppState.shared.openDocument?(file) }
        } catch {
            AppState.shared.presentError(error, title: "Couldn’t save the recording")
        }
    }

    // MARK: - Recordings on disk

    /// The title and marks of a recording, beside its tracks, so one that is cut off keeps them.
    struct Journal: Codable {
        var startedAt: Date
        var title: String
        var marks: [Mark]
        /// Optional so journals from before notes still make projects.
        var notes: [Note]?
    }

    private static func write(_ journal: Journal, in folder: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(journal).write(to: folder.appendingPathComponent("recording.json"), options: .atomic)
    }

    /// Turns a recording's folder (its tracks closed, or cut off) into a project: each track's CAF becomes an
    /// .m4a (or stays a CAF if that fails), the two are mixed for playback, and the journal goes last, so this
    /// can run again if it is itself cut off. Nil if neither track holds half a second.
    static func makeProject(in folder: URL, progress: FinishProgress = FinishProgress()) async throws -> URL? {
        guard let journal = journal(in: folder) else { return nil }
        // Both tracks at once: each is a long, single-threaded encode.
        progress.phase = .encoding
        async let micStem = stem("mic", in: folder, progress: progress)
        async let systemStem = stem("system", in: folder, progress: progress)
        let stems = ["mic": await micStem, "system": await systemStem].compactMapValues { $0 }
        let mic = stems["mic"].flatMap { $0.seconds > 0.5 ? $0 : nil }
        let system = stems["system"].flatMap { $0.seconds > 0.5 ? $0 : nil }
        let kept = [mic, system].compactMap { $0 }
        guard !kept.isEmpty else {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        let media = folder.appendingPathComponent("recording.m4a")
        try? FileManager.default.removeItem(at: media)
        progress.phase = .mixing
        if kept.count == 1 {
            try FileManager.default.copyItem(at: kept[0].url, to: media)
        } else {
            try await StemMixer.mix(kept.map(\.url), to: media) { progress.set(.mixing, $0) }
        }
        progress.set(.mixing, 1)
        progress.phase = .saving
        var project = Project()
        project.media = MediaRef(path: media.path, bookmark: try? media.bookmarkData(), hasVideo: false,
                                 micStem: mic?.url.path, systemStem: system?.url.path)
        project.duration = kept.map(\.seconds).max() ?? 0
        project.title = journal.title
        project.titleIsGenerated = true
        project.marks = journal.marks.filter { $0.start < project.duration }
            .map { Mark(id: $0.id, name: $0.name, start: $0.start, end: min($0.end, project.duration)) }
        let notes = (journal.notes ?? []).filter { $0.time <= project.duration }
        project.notes = notes.isEmpty ? nil : notes
        project.speakers = [Speaker(id: 0, isMe: true)]
        project.createdAt = journal.startedAt
        let file = ProjectFile.newURL(named: journal.title.replacingOccurrences(of: "·", with: "-"))
        try ProjectFile.write(project, to: file)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("recording.json"))
        return file
    }

    static func journal(in folder: URL) -> Journal? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: folder.appendingPathComponent("recording.json")))
            .flatMap { try? decoder.decode(Journal.self, from: $0) }
    }

    /// One track as .m4a, or its CAF if encoding fails; nil if there's neither.
    private static func stem(_ name: String, in folder: URL, progress: FinishProgress) async -> (url: URL, seconds: Double)? {
        let caf = folder.appendingPathComponent("\(name).caf"), m4a = folder.appendingPathComponent("\(name).m4a")
        defer { progress.set(.encoding(name), 1) }
        if FileManager.default.fileExists(atPath: caf.path) {
            let seconds = await Task.detached(priority: .userInitiated) {
                try? CAFWriter.encode(caf, to: m4a) { progress.set(.encoding(name), $0) }
            }.value
            if let seconds {
                try? FileManager.default.removeItem(at: caf)
                return (m4a, seconds)
            }
            return CAFWriter.length(of: caf).map { (caf, $0) }
        }
        // Encoded by an earlier run that was cut off before the project.
        guard let file = try? AVAudioFile(forReading: m4a) else { return nil }
        return (m4a, Double(file.length) / file.processingFormat.sampleRate)
    }

    /// Recordings the app quit, crashed or lost power during, made into projects and added to the library.
    /// At launch, before any recording can start.
    static func recover() {
        let root = ProjectFile.defaultFolder.appendingPathComponent("Recordings", isDirectory: true)
        let folders = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("recording.json").path) }
        guard !folders.isEmpty else { return }
        let jobs = folders.map { folder in
            let journal = journal(in: folder)
            let job = FinishingRecording(title: journal?.title ?? folder.lastPathComponent, duration: nil)
            job.phase = "Waiting to recover…"
            return job
        }
        AppState.shared.finishing.append(contentsOf: jobs)
        Task {
            for (folder, job) in zip(folders, jobs) { await finish(folder, job: job, open: false) }
        }
    }

    #if DEBUG
    /// Fills the recorder with sample state and shows the compact window, for checking its layout.
    func preview(strip: Bool) {
        state = .recording
        elapsed = 1421
        micLevel = 0.3
        systemLevel = 0.6
        lines = [
            LiveLine(id: "1", isMe: false, start: 1326, text: "It works if we get the help center articles done by the Friday before.", tentative: false),
            LiveLine(id: "2", isMe: false, start: 1351, text: "I would add one more day of buffer for the translations.", tentative: false),
            LiveLine(id: "3", isMe: true, start: 1367, text: "Fair. Let's say the fourteenth, and I'll send the updated plan after this call.", tentative: false),
            LiveLine(id: "4", isMe: false, start: 1400, text: "Sounds good. One question about the pricing page before we wrap up", tentative: true),
        ]
        marks = [Mark(name: "Moment at 22:47", start: 1347, end: 1372)]
        notes = [Note(text: "Ask Lena if the 14th works for DE and FR", time: 1360)]
        CompactPanelController.shared.show()
        CompactPanelController.shared.allowCapture()
        if strip { CompactPanelController.shared.setStrip(true) }
    }
    #endif

    enum RecorderError: LocalizedError {
        case noMicrophone
        var errorDescription: String? {
            "Allow Murmur to use the microphone in System Settings › Privacy & Security › Microphone."
        }
    }
}

/// The first channel of a buffer.
func firstChannel(_ buffer: AVAudioPCMBuffer) -> [Float] {
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    guard frames > 0, channels > 0, let data = buffer.floatChannelData else { return [] }
    if buffer.format.isInterleaved {
        return (0..<frames).map { data[0][$0 * channels] }
    }
    return Array(UnsafeBufferPointer(start: data[0], count: frames))
}

func rms(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    var sum: Float = 0
    for s in samples { sum += s * s }
    return min(1, sqrt(sum / Float(samples.count)) * 4)
}

/// Mixes the two stems into one playable file.
enum StemMixer {
    static func mix(_ stems: [URL], to url: URL, progress: (Double) -> Void = { _ in }) async throws {
        let composition = AVMutableComposition()
        for stem in stems {
            let asset = AVURLAsset(url: stem)
            guard let track = try await asset.loadTracks(withMediaType: .audio).first,
                  let target = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let duration = try await asset.load(.duration)
            try target.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        }
        let reader = try AVAssetReader(asset: composition)
        let pcm: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsNonInterleaved: false, AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1,
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: composition.tracks(withMediaType: .audio), audioSettings: pcm)
        reader.add(output)
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
        ])
        writer.add(input)
        guard reader.startReading(), writer.startWriting() else { throw writer.error ?? reader.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let total = composition.duration.seconds
        while true {
            if input.isReadyForMoreMediaData {
                guard let buffer = output.copyNextSampleBuffer() else { break }
                input.append(buffer)
                if total > 0 { progress(min(1, CMSampleBufferGetPresentationTimeStamp(buffer).seconds / total)) }
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

/// The microphone's audio engine. Building, starting and tearing one down blocks for a second or more (with
/// voice processing, several), so all of it happens on this engine's own queue, never the main thread.
final class MicrophoneEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.djui.Murmur.microphone", qos: .userInitiated)
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?

    /// Starts tapping the microphone. `prepare` gets the input's sample rate, on this engine's queue, and
    /// returns a value for the caller and the handler for each buffer's mono samples (on the audio thread).
    /// `onChange` runs on the main thread when the audio devices change under this engine.
    func start<Value>(voiceProcessing: Bool, onChange: @escaping @MainActor () -> Void,
                      prepare: @escaping (Double) throws -> (Value, ([Float]) -> Void)) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try self.startHere(voiceProcessing: voiceProcessing,
                                                                      onChange: onChange, prepare: prepare))
                } catch {
                    self.stopHere()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.stopHere()
                continuation.resume()
            }
        }
    }

    private func startHere<Value>(voiceProcessing: Bool, onChange: @escaping @MainActor () -> Void,
                                  prepare: (Double) throws -> (Value, ([Float]) -> Void)) throws -> Value {
        stopHere()
        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            // Keep the call itself at full volume.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(enableAdvancedDucking: false, duckingLevel: .min)
            // Voice processing runs input and output together; the output plays silence.
            _ = engine.mainMixerNode
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecordingController.RecorderError.noMicrophone }
        let (value, handle) = try prepare(format.sampleRate)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            // With voice processing the processed voice is the first channel; the others aren't the microphone.
            handle(voiceProcessing ? firstChannel(buffer) : monoSamples(buffer))
        }
        engine.prepare()
        try engine.start()
        // Only changes under the engine that is running now count; one that was replaced meanwhile doesn't.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                                          queue: nil) { [weak self, weak engine] _ in
            self?.queue.async {
                guard let self, let engine, self.engine === engine else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { onChange() } }
            }
        }
        return value
    }

    private func stopHere() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
    }
}

/// How far a recording's saving has got, written from any thread.
final class FinishProgress: @unchecked Sendable {
    enum Phase: Equatable { case encoding, mixing, saving }
    enum Part: Hashable { case encoding(String), mixing }

    private let lock = NSLock()
    private var parts: [Part: Double] = [:]
    private var current = Phase.encoding

    var phase: Phase {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func set(_ part: Part, _ value: Double) { lock.withLock { parts[part] = value } }

    /// Encoding the two tracks (side by side) is the first half, mixing them the second.
    var fraction: Double {
        lock.withLock {
            let encoding = ((parts[.encoding("mic")] ?? 0) + (parts[.encoding("system")] ?? 0)) / 2
            return min(1, encoding * 0.5 + (parts[.mixing] ?? 0) * 0.5)
        }
    }
}

/// A recording being saved, as the library shows it.
@Observable
@MainActor
final class FinishingRecording: Identifiable {
    let id = UUID()
    let title: String
    /// How long the recording is, when known.
    let duration: Double?
    var phase = "Stopping the recording…"
    /// Nil until there's something to measure.
    var fraction: Double?

    init(title: String, duration: Double?) {
        self.title = title
        self.duration = duration
    }

    func update(from progress: FinishProgress) {
        fraction = progress.fraction
        switch progress.phase {
        case .encoding: phase = "Saving the tracks…"
        case .mixing: phase = "Mixing the tracks for playback…"
        case .saving: phase = "Creating the project…"
        }
    }
}
