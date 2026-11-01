import Foundation
import MurmurCore
import Observation

/// The projects in Documents/Murmur, and making new ones from files and recordings.
@Observable
@MainActor
final class Library {
    static let shared = Library()

    struct Item: Identifiable, Hashable {
        var url: URL
        var title: String
        var createdAt: Date
        var duration: Double
        var status: Project.Status
        var speakers: Int
        /// Each speaker's share of the talking, by their position in the list (which picks the colour).
        var talk: [(index: Int, name: String, share: Double)] = []
        var id: URL { url }
        /// Everything a row shows, so a row redraws when its project changes (talk has tuples, so no synthesis).
        static func == (a: Item, b: Item) -> Bool {
            a.url == b.url && a.title == b.title && a.duration == b.duration && a.status == b.status
                && a.speakers == b.speakers && a.talk.map(\.share) == b.talk.map(\.share)
        }
        func hash(into h: inout Hasher) { h.combine(url) }
    }

    private(set) var items: [Item] = []
    var error: String?
    /// Projects transcribing now, open or not.
    var transcribing: Set<URL> = []
    /// Projects whose transcription waits for an answer (which language), shown when opened.
    var asking: Set<URL> = []

    init() { reload() }

    func reload() {
        let folder = ProjectFile.defaultFolder
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        items = urls.filter { $0.pathExtension == "murmur" }.compactMap { url in
            guard let p = try? ProjectFile.read(at: url) else { return nil }
            let title = p.title ?? url.deletingPathExtension().lastPathComponent
            var item = Item(url: url, title: title, createdAt: p.createdAt, duration: p.duration, status: p.status,
                            speakers: p.speakers.count)
            let talk = p.talkTime, total = max(1, talk.values.reduce(0, +))
            item.talk = p.speakers.enumerated().map { ($0.offset, p.name(of: $0.element.id), (talk[$0.element.id] ?? 0) / total) }
            return item
        }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Imported and recorded media live next to the projects, so they stay with the app's container.
    static var mediaFolder: URL {
        let url = ProjectFile.defaultFolder.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Copies a file from Files, another app or the share sheet into the app and makes a project for it.
    func importMedia(_ source: URL) async throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var target = Self.mediaFolder.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = Self.mediaFolder.appendingPathComponent(
                "\(source.deletingPathExtension().lastPathComponent) \(n).\(source.pathExtension)")
            n += 1
        }
        try FileManager.default.copyItem(at: source, to: target)
        // Files handed over through "Open in" land in Inbox, which is ours to clean up.
        if source.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: source) }
        return try await makeProject(for: target, name: source.deletingPathExtension().lastPathComponent)
    }

    func makeProject(for media: URL, name: String) async throws -> URL {
        let info = try await AudioDecoder.info(media)
        guard info.hasAudio else {
            try? FileManager.default.removeItem(at: media)
            throw AudioDecoder.DecodeError.noAudio
        }
        var project = Project()
        project.media = MediaRef.make(for: media, hasVideo: info.hasVideo)
        project.duration = info.duration
        project.settings.enhance = AppSettings.bool(AppSettings.enhanceNewProjects)
        let file = ProjectFile.newURL(named: name)
        try ProjectFile.write(project, to: file)
        reload()
        return file
    }

    /// Deletes the project and, since Murmur keeps its own copy, its media.
    func delete(_ url: URL) {
        if let media = (try? ProjectFile.read(at: url))?.media?.resolvedURL(),
           media.standardizedFileURL.path.hasPrefix(Self.mediaFolder.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: media)
        }
        if let project = try? ProjectFile.read(at: url) {
            try? FileManager.default.removeItem(at: ProjectFile.cacheFolder(for: project))
        }
        try? FileManager.default.removeItem(at: url)
        reload()
    }
}
