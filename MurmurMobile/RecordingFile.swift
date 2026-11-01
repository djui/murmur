import AVFoundation
import Foundation
import MurmurCore

/// A recording in progress, written so that nothing is lost if the app is killed, crashes or the phone
/// switches off: 16-bit PCM in a CAF file whose header is complete from the first byte (the data chunk's
/// size is "to the end of the file"), synced to storage every few seconds, and a journal of the title and
/// marks beside it. AAC in .m4a, by contrast, is unreadable until it is closed. On stop, or at the next
/// launch for a recording that was cut off, the CAF becomes an .m4a and a project.
final class RecordingFile: @unchecked Sendable {
    struct Journal: Codable {
        var startedAt: Date
        var title: String
        var marks: [Mark]
    }

    /// Recordings in progress, hidden from the Files app.
    static var folder: URL {
        let url = Library.mediaFolder.appendingPathComponent(".Recording", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    let url: URL
    let sampleRate: Double
    private var journal: Journal
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "Murmur.RecordingFile")
    private let lock = NSLock()
    private var frames: Int64 = 0
    private var failure: Error?
    private var lastSync = Date()
    private var converter: AVAudioConverter?
    private var closed = false

    init(startedAt: Date, title: String, sampleRate: Double) throws {
        let stamp = startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        url = Self.folder.appendingPathComponent("Recording \(stamp).caf")
        self.sampleRate = sampleRate
        journal = Journal(startedAt: startedAt, title: title, marks: [])
        try Self.write(journal, for: url)
        guard FileManager.default.createFile(atPath: url.path, contents: Self.header(sampleRate: sampleRate)) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    var seconds: Double { lock.withLock { Double(frames) / sampleRate } }

    /// Why writing stopped (storage full, most likely), or nil.
    var error: Error? { lock.withLock { failure } }

    /// Appends mono samples at any rate (a Bluetooth microphone can change it mid-recording).
    func write(_ samples: [Float], sampleRate rate: Double) {
        guard !samples.isEmpty else { return }
        queue.async { [self] in
            guard !closed, error == nil else { return }
            let samples = rate == sampleRate ? samples : resample(samples, from: rate)
            var data = Data(count: samples.count * 2)
            data.withUnsafeMutableBytes { raw in
                let out = raw.bindMemory(to: Int16.self)
                for (i, s) in samples.enumerated() { out[i] = Int16(max(-1, min(1, s)) * 32767).littleEndian }
            }
            do {
                try handle.write(contentsOf: data)
                // Written bytes survive the app being killed; syncing keeps them if the phone dies too.
                if Date().timeIntervalSince(lastSync) > 5 {
                    try handle.synchronize()
                    lastSync = Date()
                }
                lock.withLock { frames += Int64(samples.count) }
            } catch {
                lock.withLock { failure = error }
            }
        }
    }

    /// Keeps the marks with the recording, so a recording that is cut off keeps them too.
    func save(marks: [Mark]) {
        queue.async { [self] in
            journal.marks = marks
            try? Self.write(journal, for: url)
        }
    }

    func close() {
        queue.sync {
            guard !closed else { return }
            closed = true
            try? handle.synchronize()
            try? handle.close()
        }
    }

    private func resample(_ samples: [Float], from rate: Double) -> [Float] {
        let input = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let output = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        if converter?.inputFormat.sampleRate != rate { converter = AVAudioConverter(from: input, to: output) }
        guard let converter,
              let source = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: AVAudioFrameCount(samples.count)),
              let target = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(Double(samples.count) * sampleRate / rate) + 64)
        else { return [] }
        source.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        var given = false
        _ = converter.convert(to: target, error: nil) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true
            status.pointee = .haveData
            return source
        }
        return Array(UnsafeBufferPointer(start: target.floatChannelData![0], count: Int(target.frameLength)))
    }

    // MARK: The file

    /// The CAF header: file header, audio description (16-bit little-endian mono PCM), and a data chunk
    /// of unknown size, which a reader takes to run to the end of the file.
    static func header(sampleRate: Double) -> Data {
        var d = Data()
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func i64(_ v: Int64) { withUnsafeBytes(of: v.bigEndian) { d.append(contentsOf: $0) } }
        func tag(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        tag("caff"); u16(1); u16(0)
        tag("desc"); i64(32)
        withUnsafeBytes(of: sampleRate.bitPattern.bigEndian) { d.append(contentsOf: $0) }
        tag("lpcm")
        u32(2) // kCAFLinearPCMFormatFlagIsLittleEndian
        u32(2); u32(1); u32(1); u32(16) // bytes per packet, frames per packet, channels, bits
        tag("data"); i64(-1)
        u32(0) // edit count
        return d
    }

    private static func journalURL(for caf: URL) -> URL { caf.deletingPathExtension().appendingPathExtension("json") }

    private static func write(_ journal: Journal, for caf: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(journal).write(to: journalURL(for: caf), options: .atomic)
    }

    private static func journal(for caf: URL) -> Journal? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: journalURL(for: caf))).flatMap { try? decoder.decode(Journal.self, from: $0) }
    }

    static func remove(_ caf: URL) {
        try? FileManager.default.removeItem(at: caf)
        try? FileManager.default.removeItem(at: journalURL(for: caf))
    }

    // MARK: Into a project

    /// Turns a closed recording into an .m4a and a project, then removes the CAF and its journal; nil if
    /// it holds less than half a second. Safe to run again if it is cut off itself: the CAF goes only once
    /// the project is written. If the .m4a can't be made, the CAF itself becomes the media.
    static func makeProject(from caf: URL) async throws -> URL? {
        let created = (try? caf.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let journal = journal(for: caf)
            ?? Journal(startedAt: created, title: caf.deletingPathExtension().lastPathComponent, marks: [])
        let m4a = Library.mediaFolder.appendingPathComponent(caf.deletingPathExtension().lastPathComponent).appendingPathExtension("m4a")
        let converted = await Task.detached(priority: .userInitiated) { try? encode(caf, to: m4a) }.value
        let media: URL, seconds: Double
        if let converted {
            media = m4a
            seconds = converted
        } else {
            guard let file = try? AVAudioFile(forReading: caf) else { remove(caf); return nil }
            seconds = Double(file.length) / file.processingFormat.sampleRate
            media = Library.mediaFolder.appendingPathComponent(caf.lastPathComponent)
            try? FileManager.default.removeItem(at: media)
            try FileManager.default.copyItem(at: caf, to: media)
        }
        guard seconds > 0.5 else {
            try? FileManager.default.removeItem(at: media)
            remove(caf)
            return nil
        }
        var project = Project()
        project.media = MediaRef.make(for: media, hasVideo: false)
        project.duration = seconds
        project.title = journal.title
        project.titleIsGenerated = true
        project.marks = journal.marks.filter { $0.start < seconds }
            .map { Mark(id: $0.id, name: $0.name, start: $0.start, end: min($0.end, seconds)) }
        project.createdAt = journal.startedAt
        project.settings.enhance = AppSettings.bool(AppSettings.enhanceNewProjects)
        let url = ProjectFile.newURL(named: journal.title.replacingOccurrences(of: "·", with: "-"))
        try ProjectFile.write(project, to: url)
        remove(caf)
        return url
    }

    /// The CAF as AAC; its length in seconds.
    private static func encode(_ caf: URL, to m4a: URL) throws -> Double {
        try? FileManager.default.removeItem(at: m4a)
        let input = try AVAudioFile(forReading: caf)
        let writer = try StemWriter(url: m4a, sampleRate: input.processingFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 1 << 16) else {
            throw CocoaError(.fileReadUnknown)
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            writer.write(Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength))))
        }
        let result = writer.finish()
        // A half-written .m4a is no use; the caller falls back to the CAF.
        guard let check = try? AVAudioFile(forReading: m4a),
              abs(Double(check.length) / check.processingFormat.sampleRate - result.seconds) < 1 else {
            try? FileManager.default.removeItem(at: m4a)
            throw CocoaError(.fileWriteUnknown)
        }
        return result.seconds
    }

    /// Recordings the app was killed during, made into projects. Called at launch: the folder is read before
    /// any new recording can start, so one that starts meanwhile is left alone.
    @MainActor
    static func recover() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        // Journals whose recording never started.
        for json in files where json.pathExtension == "json"
            && !FileManager.default.fileExists(atPath: json.deletingPathExtension().appendingPathExtension("caf").path) {
            try? FileManager.default.removeItem(at: json)
        }
        let cut = files.filter { $0.pathExtension == "caf" }
        guard !cut.isEmpty else { return }
        // The Live Activity of the recording that was cut off.
        LiveRecording.end()
        Task {
            for caf in cut { _ = try? await makeProject(from: caf) }
            Library.shared.reload()
        }
    }
}
