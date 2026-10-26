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
    var warning: String?
    var strip = false
    var startedAt = Date()
    var systemSourceName = "All apps"
    var liveAvailable = true

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var tap: SystemAudioTap?
    @ObservationIgnored private var micWriter: StemWriter?
    @ObservationIgnored private var systemWriter: StemWriter?
    @ObservationIgnored private var micLive: LiveTranscriber?
    @ObservationIgnored private var systemLive: LiveTranscriber?
    @ObservationIgnored private var micWords: [(MurmurCore.Word, Bool)] = []
    @ObservationIgnored private var systemWords: [(MurmurCore.Word, Bool)] = []
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private let paused = AtomicFlag()
    @ObservationIgnored private var levelTick = 0

    var title: String { "Recording · " + startedAt.formatted(date: .abbreviated, time: .shortened) }

    // MARK: - Start

    func start() {
        guard state == .idle else { CompactPanelController.shared.show(); return }
        state = .starting
        warning = nil
        lines = []
        marks = []
        elapsed = 0
        micWords = []
        systemWords = []
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
            try startMicrophone(into: folder)
        } catch {
            stopAudio()
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

    private func startMicrophone(into folder: URL) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecorderError.noMicrophone }
        let writer = try StemWriter(url: folder.appendingPathComponent("mic.m4a"), sampleRate: format.sampleRate)
        let live = micLive
        let paused = self.paused
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard !paused.isSet else { return }
            let samples = monoSamples(buffer)
            writer.write(samples)
            if let live { Task { await live.append(samples, sampleRate: format.sampleRate) } }
            let level = rms(samples)
            DispatchQueue.main.async { self?.micLevel = level }
        }
        engine.prepare()
        try engine.start()
        self.engine = engine
        micWriter = writer
    }

    private func startSystemAudio(into folder: URL) {
        let source = UserDefaults.standard.string(forKey: AppSettings.systemAudioSource) ?? ""
        let tap = SystemAudioTap()
        do {
            try tap.start(bundleID: source.isEmpty ? nil : source)
            guard let format = tap.format else { throw SystemAudioTap.TapError.message("No tap format") }
            let writer = try StemWriter(url: folder.appendingPathComponent("system.m4a"), sampleRate: format.sampleRate)
            let live = systemLive
            let paused = self.paused
            tap.onBuffer = { [weak self] buffer in
                guard !paused.isSet else { return }
                let samples = monoSamples(buffer)
                writer.write(samples)
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

    private func listen(_ live: LiveTranscriber, isMe: Bool) {
        Task { [weak self] in
            for await update in live.updates {
                let words = update.committedWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), false) }
                    + update.tentativeWords.map { (MurmurCore.Word(text: $0.text, start: $0.start, end: $0.end), true) }
                await MainActor.run {
                    guard let self else { return }
                    if isMe { self.micWords = words } else { self.systemWords = words }
                    self.rebuildLines()
                }
            }
        }
    }

    private func rebuildLines() {
        lines = LiveLines.build(mic: micWords, system: systemWords)
    }

    private func tick() {
        guard state == .recording else { return }
        elapsed = max(micWriter?.seconds ?? 0, systemWriter?.seconds ?? 0)
        micHistory.removeFirst()
        micHistory.append(micLevel)
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
    }

    func stop() {
        guard state == .recording || state == .paused else { return }
        state = .finishing
        timer?.invalidate()
        timer = nil
        stopAudio()
        Task {
            await micLive?.finish()
            await systemLive?.finish()
            micLive = nil
            systemLive = nil
            await finishProject()
        }
    }

    private func stopAudio() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        tap?.onBuffer = nil
        tap?.stop()
        tap = nil
    }

    private func finishProject() async {
        defer {
            state = .idle
            CompactPanelController.shared.close()
        }
        guard let folder else { return }
        let mic = micWriter?.finish()
        let system = systemWriter?.finish()
        micWriter = nil
        systemWriter = nil
        let stems = [mic, system].compactMap { $0 }.filter { $0.seconds > 0.5 }
        guard !stems.isEmpty else { return }

        let media = folder.appendingPathComponent("recording.m4a")
        do {
            if stems.count == 1 {
                try FileManager.default.copyItem(at: stems[0].url, to: media)
            } else {
                try await StemMixer.mix(stems.map(\.url), to: media)
            }
            var project = Project()
            project.media = MediaRef(path: media.path, bookmark: try? media.bookmarkData(), hasVideo: false,
                                     micStem: mic.flatMap { $0.seconds > 0.5 ? $0.url.path : nil },
                                     systemStem: system.flatMap { $0.seconds > 0.5 ? $0.url.path : nil })
            project.duration = stems.map(\.seconds).max() ?? 0
            project.title = title
            project.titleIsGenerated = true
            project.marks = marks.map { Mark(id: $0.id, name: $0.name, start: $0.start, end: min($0.end, project.duration)) }
            project.speakers = [Speaker(id: 0, isMe: true)]
            project.createdAt = startedAt
            let file = ProjectFile.newURL(named: title.replacingOccurrences(of: "·", with: "-"))
            try ProjectFile.write(project, to: file)
            AppState.shared.remember(file)
            AppState.shared.openDocument?(file)
        } catch {
            AppState.shared.presentError(error, title: "Couldn’t save the recording")
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

func rms(_ samples: [Float]) -> Float {
    guard !samples.isEmpty else { return 0 }
    var sum: Float = 0
    for s in samples { sum += s * s }
    return min(1, sqrt(sum / Float(samples.count)) * 4)
}

/// Writes one mono track as AAC, from any thread (calls must not overlap).
final class StemWriter: @unchecked Sendable {
    struct Result { let url: URL; let seconds: Double }

    let url: URL
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let lock = NSLock()
    private var frames: Int64 = 0
    private var closed = false

    init(url: URL, sampleRate: Double) throws {
        self.url = url
        format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    var seconds: Double { lock.withLock { Double(frames) / format.sampleRate } }

    func write(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        lock.withLock {
            guard !closed else { return }
            try? file.write(from: buffer)
            frames += Int64(samples.count)
        }
    }

    func finish() -> Result {
        lock.withLock {
            closed = true
            file.close()
            return Result(url: url, seconds: Double(frames) / format.sampleRate)
        }
    }
}

/// Mixes the two stems into one playable file.
enum StemMixer {
    static func mix(_ stems: [URL], to url: URL) async throws {
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
        while true {
            if input.isReadyForMoreMediaData {
                guard let buffer = output.copyNextSampleBuffer() else { break }
                input.append(buffer)
            } else {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status == .failed { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}
