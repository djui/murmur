import Combine
import MurmurCore
import SwiftUI

/// The projects open in this run of the app. A project's session outlives its screen while it is
/// transcribing: the work keeps saving, and opening the project again shows the same run (and any
/// question it is waiting on) instead of starting a second one.
@MainActor
final class OpenProjects {
    static let shared = OpenProjects()

    private var sessions: [URL: ProjectSession] = [:]
    private var saving: [URL: AnyCancellable] = [:]
    private var visible: Set<URL> = []

    func session(for url: URL) throws -> ProjectSession {
        if let session = sessions[url] { return session }
        let contents = try ProjectFile.read(try FileWrapper(url: url))
        let document = ProjectDocument()
        document.project = contents.project
        document.peaks = contents.peaks
        let session = ProjectSession(document: document, fileURL: url)
        sessions[url] = session
        saving[url] = document.objectWillChange
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.save(url) }
        watch(session, url)
        return session
    }

    /// Where a project should open, when it is opened from a search result.
    private var seeks: [URL: Double] = [:]

    func seek(_ url: URL, to time: Double) { seeks[url] = time }

    /// The time a project was asked to open at, once.
    func takeSeek(_ url: URL) -> Double? { seeks.removeValue(forKey: url) }

    func appeared(_ url: URL) { visible.insert(url) }

    func disappeared(_ url: URL) {
        visible.remove(url)
        sessions[url]?.player.pause()
        save(url)
        closeIfIdle(url)
    }

    func saveAll() { sessions.keys.forEach(save) }

    func save(_ url: URL) {
        guard let session = sessions[url] else { return }
        do {
            try ProjectFile.write(session.document.project, peaks: session.document.peaks, to: url)
            Library.shared.reload()
        } catch {
            session.flash("Couldn’t save: \(error.localizedDescription)")
        }
    }

    /// Closes a project nobody is looking at once it has nothing left to do.
    private func closeIfIdle(_ url: URL) {
        guard !visible.contains(url), let session = sessions[url], !session.isProcessing else { return }
        sessions[url] = nil
        saving[url] = nil
    }

    /// Follows a session's processing wherever its screen is: the library rows, the system's
    /// background progress, keeping the screen awake, and closing it when done off screen.
    private func watch(_ session: ProjectSession, _ url: URL) {
        withObservationTracking {
            _ = session.isProcessing
            _ = session.steps
            _ = session.languagePrompt
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self, self.sessions[url] === session else { return }
                self.changed(session, url)
                self.watch(session, url)
            }
        }
    }

    private func changed(_ session: ProjectSession, _ url: URL) {
        let library = Library.shared
        let wasProcessing = library.transcribing.contains(url)
        if session.isProcessing { library.transcribing.insert(url) } else { library.transcribing.remove(url) }
        if session.languagePrompt != nil { library.asking.insert(url) } else { library.asking.remove(url) }

        if session.isProcessing, !wasProcessing {
            ContinuedProcessing.begin(project: session.project.displayTitle)
        }
        if session.isProcessing, let running = session.steps.first(where: { $0.state == .running }) {
            ContinuedProcessing.update(fraction: Self.fraction(session.steps), detail: running.title)
        }
        if !session.isProcessing, wasProcessing {
            if library.transcribing.isEmpty { ContinuedProcessing.end(success: session.project.status == .ready) }
            save(url)
            closeIfIdle(url)
        }
        UIApplication.shared.isIdleTimerDisabled = !library.transcribing.isEmpty
    }

    static func fraction(_ steps: [PipelineStep]) -> Double {
        guard !steps.isEmpty else { return 0 }
        let done = steps.reduce(0.0) { sum, step in
            switch step.state {
            case .done, .skipped: sum + 1
            case .running: sum + (step.fraction ?? 0)
            default: sum
            }
        }
        return done / Double(steps.count)
    }
}
