import AppKit
import Foundation
import MurmurCore
import Observation
import SwiftUI

/// The timeline across the top, or as a column on the left with time running down.
enum TimelineLayout: String, CaseIterable, Identifiable {
    case top, left

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "Top"
        case .left: "Left"
        }
    }
}

/// App-wide state: the recorder and the list of known projects.
@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    let recorder = RecordingController()
    /// Set by the SwiftUI scene so non-view code can open project windows.
    @ObservationIgnored var openDocument: ((URL) -> Void)?
    @ObservationIgnored var openWindow: ((String) -> Void)?

    var libraryVersion = 0
    /// Recordings being saved; the library shows each until it opens as a project.
    var finishing: [FinishingRecording] = []

    /// Brings the library forward, where a recording that just stopped shows its progress.
    func showLibrary() {
        openWindow?("library")
        NSApp.activate()
    }

    /// Paths of projects Murmur created or opened, so the library can list projects saved anywhere.
    var knownProjects: [String] {
        get { UserDefaults.standard.stringArray(forKey: AppSettings.knownProjects) ?? [] }
        set {
            UserDefaults.standard.set(newValue, forKey: AppSettings.knownProjects)
            libraryVersion += 1
        }
    }

    func remember(_ url: URL) {
        var list = knownProjects.filter { $0 != url.path }
        list.insert(url.path, at: 0)
        knownProjects = Array(list.prefix(500))
    }

    func forget(_ url: URL) {
        knownProjects = knownProjects.filter { $0 != url.path }
    }

    /// Projects in the default folder are listed by scanning it, so forgetting them alone doesn't hide them.
    static func isInDefaultFolder(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == ProjectFile.defaultFolder.standardizedFileURL
    }

    /// Moves projects to the Trash. A recording's audio folder goes with it, since Murmur made it;
    /// imported media stays where the user keeps it.
    func trash(_ urls: [URL]) {
        let recordings = ProjectFile.defaultFolder.appendingPathComponent("Recordings", isDirectory: true).standardizedFileURL
        var list = knownProjects
        for url in urls {
            if let media = (try? ProjectFile.read(at: url))?.media, media.isRecording {
                let folder = URL(fileURLWithPath: media.path).deletingLastPathComponent().standardizedFileURL
                if folder.deletingLastPathComponent() == recordings {
                    try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
                }
            }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                list.removeAll { $0 == url.path }
            } catch {
                presentError(error, title: "Murmur couldn’t move “\(url.deletingPathExtension().lastPathComponent)” to the Trash")
            }
        }
        knownProjects = list
    }

    // MARK: - Tags

    private final class WeakSession { weak var session: ProjectSession?; init(_ s: ProjectSession) { session = s } }
    /// Project windows that are open, by file, so the library changes their projects through their undo
    /// and saving instead of writing a file the window would save over.
    @ObservationIgnored private var openSessions: [URL: WeakSession] = [:]

    func register(_ session: ProjectSession) {
        guard let url = session.fileURL?.standardizedFileURL else { return }
        openSessions[url] = WeakSession(session)
    }

    func unregister(_ session: ProjectSession) {
        guard let url = session.fileURL?.standardizedFileURL, openSessions[url]?.session === session else { return }
        openSessions[url] = nil
        libraryVersion += 1
    }

    /// The projects open in windows, which may be newer than their files.
    var openProjects: [URL: Project] {
        openSessions.compactMapValues { $0.session?.project }
    }

    /// Tags made in the library that no project may carry yet.
    var savedTags: [String] = Tags.normalize(UserDefaults.standard.stringArray(forKey: AppSettings.libraryTags) ?? []) {
        didSet {
            let list = Tags.normalize(savedTags)
            if list != savedTags { savedTags = list; return }
            UserDefaults.standard.set(list, forKey: AppSettings.libraryTags)
            libraryVersion += 1
        }
    }

    /// Every tag the library knows: on its projects or made empty. Set by the library as it loads.
    var tagsInUse: [String] = []

    var allTags: [String] { Tags.normalize(tagsInUse + savedTags) }

    func createTag(_ name: String) {
        guard let tag = Tags.clean(name) else { return }
        savedTags.append(tag)
    }

    func setTag(_ tag: String, _ on: Bool, for urls: [URL]) {
        guard let tag = Tags.clean(tag) else { return }
        if on, !savedTags.contains(where: { Tags.same($0, tag) }) { savedTags.append(tag) }
        changeProjects(urls, action: on ? "Add Tag" : "Remove Tag") { on ? $0.addTag(tag) : $0.removeTag(tag) }
    }

    /// Renames a tag on every project in `urls` that has it.
    func renameTag(_ old: String, to new: String, in urls: [URL]) {
        guard let new = Tags.clean(new), new != old else { return }
        savedTags = savedTags.filter { !Tags.same($0, old) } + [new]
        changeProjects(urls, action: "Rename Tag") { $0.renameTag(old, to: new) }
    }

    /// Takes a tag off every project in `urls`. The projects stay.
    func deleteTag(_ tag: String, in urls: [URL]) {
        savedTags = savedTags.filter { !Tags.same($0, tag) }
        changeProjects(urls, action: "Remove Tag") { $0.removeTag(tag) }
    }

    /// Changes projects in open windows through the window, and the others in their file.
    private func changeProjects(_ urls: [URL], action: String, _ change: (inout Project) -> Void) {
        for url in urls {
            if let session = openSessions[url.standardizedFileURL]?.session {
                session.update(action, change)
                continue
            }
            do {
                var project = try ProjectFile.read(at: url)
                let old = project
                change(&project)
                if project != old { try ProjectFile.writeProjectOnly(project, to: url) }
            } catch {
                presentError(error, title: "Murmur couldn’t change the tags of “\(url.deletingPathExtension().lastPathComponent)”")
            }
        }
        libraryVersion += 1
    }

    /// Creates a project for a media file next to the other projects and opens it.
    func importMedia(_ url: URL) {
        Task {
            do {
                let info = try await AudioDecoder.info(url)
                guard info.hasAudio else { throw AudioDecoder.DecodeError.noAudio }
                var project = Project()
                project.media = MediaRef.make(for: url, hasVideo: info.hasVideo)
                project.duration = info.duration
                project.settings.enhance = AppSettings.bool(AppSettings.enhanceNewProjects)
                let file = ProjectFile.newURL(named: url.deletingPathExtension().lastPathComponent)
                try ProjectFile.write(project, to: file)
                remember(file)
                openDocument?(file)
            } catch {
                presentError(error, title: "Couldn’t import \(url.lastPathComponent)")
            }
        }
    }

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audiovisualContent]
        panel.allowsMultipleSelection = true
        panel.message = "Choose audio or video files to transcribe"
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(importMedia)
    }

    func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
