import Foundation
import MurmurCore

/// A recording in progress, kept so that nothing is lost if the app is killed, crashes or the phone switches
/// off: the microphone in a `CAFWriter` file, and a journal of the title and marks beside it. On stop, or at
/// the next launch for a recording that was cut off, it becomes an .m4a and a project.
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

    private let writer: CAFWriter
    private var journal: Journal
    private let queue = DispatchQueue(label: "Murmur.RecordingFile")

    init(startedAt: Date, title: String, sampleRate: Double) throws {
        let stamp = startedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash).time(includingFractionalSeconds: false).timeSeparator(.omitted))
        let url = Self.folder.appendingPathComponent("Recording \(stamp).caf")
        journal = Journal(startedAt: startedAt, title: title, marks: [])
        try Self.write(journal, for: url)
        writer = try CAFWriter(url: url, sampleRate: sampleRate)
    }

    var url: URL { writer.url }
    var seconds: Double { writer.seconds }
    var error: Error? { writer.error }

    func write(_ samples: [Float], sampleRate: Double) { writer.write(samples, sampleRate: sampleRate) }

    /// Keeps the marks with the recording, so a recording that is cut off keeps them too.
    func save(marks: [Mark]) {
        queue.async { [self] in
            journal.marks = marks
            try? Self.write(journal, for: url)
        }
    }

    func close() {
        writer.close()
        queue.sync {}
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

    /// Turns a closed recording into an .m4a and a project, then removes the CAF and its journal; nil if
    /// it holds less than half a second. Safe to run again if it is cut off itself: the CAF goes only once
    /// the project is written. If the .m4a can't be made, a copy of the CAF becomes the media.
    static func makeProject(from caf: URL) async throws -> URL? {
        let created = (try? caf.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let journal = journal(for: caf)
            ?? Journal(startedAt: created, title: caf.deletingPathExtension().lastPathComponent, marks: [])
        let m4a = Library.mediaFolder.appendingPathComponent(caf.deletingPathExtension().lastPathComponent).appendingPathExtension("m4a")
        let converted = await Task.detached(priority: .userInitiated) { try? CAFWriter.encode(caf, to: m4a) }.value
        let media: URL, seconds: Double
        if let converted {
            media = m4a
            seconds = converted
        } else {
            guard let length = CAFWriter.length(of: caf) else { remove(caf); return nil }
            seconds = length
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
