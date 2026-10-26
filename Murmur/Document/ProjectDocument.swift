import Foundation
import MurmurCore
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let murmurProject = UTType(exportedAs: "com.djui.murmur.project", conformingTo: .package)
}

/// A `.murmur` package: `project.json` plus the cached waveform `peaks.bin`.
final class ProjectDocument: ReferenceFileDocument {
    struct Contents {
        var project: Project
        var peaks: [Float]
    }

    static var readableContentTypes: [UTType] { [.murmurProject] }

    @Published var project: Project
    @Published var peaks: [Float]

    init() {
        project = Project()
        peaks = []
    }

    required init(configuration: ReadConfiguration) throws {
        let contents = try ProjectFile.read(configuration.file)
        project = contents.project
        peaks = contents.peaks
    }

    func snapshot(contentType: UTType) throws -> Contents {
        Contents(project: project, peaks: peaks)
    }

    func fileWrapper(snapshot: Contents, configuration: WriteConfiguration) throws -> FileWrapper {
        try ProjectFile.wrapper(snapshot.project, peaks: snapshot.peaks)
    }
}

/// Reading and writing `.murmur` packages outside the document system, for the library and for
/// creating projects from imports and recordings.
enum ProjectFile {
    static func read(_ wrapper: FileWrapper) throws -> ProjectDocument.Contents {
        guard let files = wrapper.fileWrappers, let json = files["project.json"]?.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let project = try Project.decode(json)
        let peaks = files["peaks.bin"]?.regularFileContents.map(Peaks.decode) ?? []
        return .init(project: project, peaks: peaks)
    }

    static func read(at url: URL) throws -> Project {
        try Project.decode(Data(contentsOf: url.appendingPathComponent("project.json")))
    }

    static func wrapper(_ project: Project, peaks: [Float]) throws -> FileWrapper {
        let json = FileWrapper(regularFileWithContents: try project.encoded())
        json.preferredFilename = "project.json"
        var files = ["project.json": json]
        if !peaks.isEmpty {
            let bin = FileWrapper(regularFileWithContents: Peaks.encode(peaks))
            bin.preferredFilename = "peaks.bin"
            files["peaks.bin"] = bin
        }
        return FileWrapper(directoryWithFileWrappers: files)
    }

    static func write(_ project: Project, peaks: [Float] = [], to url: URL) throws {
        try wrapper(project, peaks: peaks).write(to: url, options: .atomic, originalContentsURL: nil)
    }

    /// Where new projects go: ~/Documents/Murmur, or the `projectsFolder` default when set.
    static var defaultFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = UserDefaults.standard.string(forKey: "projectsFolder").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? docs.appendingPathComponent("Murmur", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A free `<name>.murmur` URL in the default folder.
    static func newURL(named name: String) -> URL {
        let clean = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        var url = defaultFolder.appendingPathComponent(clean).appendingPathExtension("murmur")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = defaultFolder.appendingPathComponent("\(clean) \(n)").appendingPathExtension("murmur")
            n += 1
        }
        return url
    }

    /// Per-project cache for derived audio (the enhanced copy).
    static func cacheFolder(for project: Project) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("com.djui.Murmur/\(project.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

extension MediaRef {
    /// Resolves the media file, following the bookmark if the file moved.
    func resolvedURL() -> URL? {
        if FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        guard let bookmark else { return nil }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale),
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        return nil
    }

    static func make(for url: URL, hasVideo: Bool) -> MediaRef {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        return MediaRef(path: url.path, bookmark: try? url.bookmarkData(), hasVideo: hasVideo, fileSize: size)
    }
}
