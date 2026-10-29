import AppKit
import Foundation
import MurmurCore
import Observation
import SwiftUI

/// User preferences, read with `@AppStorage(AppSettings.x)` in views and `AppSettings.value` elsewhere.
enum AppSettings {
    static let copyFormat = "copyFormat"
    static let hideFillersInExport = "hideFillersInExport"
    static let enhanceNewProjects = "enhanceNewProjects"
    static let detectFillers = "detectFillers"
    static let autoTitle = "autoTitle"
    static let systemAudioSource = "systemAudioSource"
    static let markHotKey = "markHotKey"
    static let skippedOnboarding = "skippedOnboarding"
    static let knownProjects = "knownProjects"
    static let speakerScheme = "speakerScheme"
    static let hideRecorderFromSharing = "hideRecorderFromSharing"
    static let redactionStyle = "redactionStyle"

    static func register() {
        UserDefaults.standard.register(defaults: [
            copyFormat: TextFormat.timestamps.rawValue,
            hideFillersInExport: true,
            enhanceNewProjects: false,
            detectFillers: true,
            autoTitle: true,
            systemAudioSource: "",
            markHotKey: true,
            hideRecorderFromSharing: true,
            redactionStyle: RedactionStyle.labels.rawValue,
        ])
    }

    static var copyFormatValue: TextFormat {
        TextFormat(rawValue: UserDefaults.standard.string(forKey: copyFormat) ?? "") ?? .timestamps
    }

    static func bool(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    static var redactionStyleValue: RedactionStyle {
        RedactionStyle(rawValue: UserDefaults.standard.string(forKey: redactionStyle) ?? "") ?? .labels
    }

    /// Copy and export options that follow the user's settings.
    static var renderOptions: RenderOptions {
        RenderOptions(hideFillers: bool(hideFillersInExport), redactionStyle: redactionStyleValue)
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
