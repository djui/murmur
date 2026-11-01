import Foundation

/// Recordings handed to the share extension (Voice Memos › Share › Murmur) wait here, in the container the app
/// and the extension share, until Murmur is next in front and imports them.
enum SharedInbox {
    static let group = "group.com.djui.Murmur"

    static var folder: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Extension: keeps a copy of `file` under its own name, in a folder of its own so names never clash.
    static func add(_ file: URL, name: String) throws {
        guard let folder else { throw CocoaError(.fileNoSuchFile) }
        let slot = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: slot.appendingPathComponent(name))
    }

    /// App: the waiting files, oldest first.
    static func pending() -> [URL] {
        guard let folder, let slots = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.creationDateKey]) else { return [] }
        let date = { (u: URL) in (try? u.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast }
        return slots.sorted { date($0) < date($1) }.compactMap {
            try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil).first
        }
    }

    /// App: forgets a file once it is imported (or can't be).
    static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }
}
