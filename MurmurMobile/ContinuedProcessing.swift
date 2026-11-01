import BackgroundTasks
import Foundation

/// Keeps a transcription going when the person leaves the app: iOS shows its progress in the system UI
/// and lets the work finish instead of suspending the app after a few seconds.
@MainActor
enum ContinuedProcessing {
    /// One at a time: only the open project transcribes.
    private static let identifier = "com.djui.Murmur.transcribe"
    private static var task: BGContinuedProcessingTask?
    private static var pending: (fraction: Double, title: String)?
    private static var registered = false
    private static var active = false

    static func register() {
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated {
                guard let task = task as? BGContinuedProcessingTask else { return }
                guard active else { task.setTaskCompleted(success: false); return }
                self.task = task
                task.progress.totalUnitCount = 1000
                // If iOS takes the time back, the work is suspended with the app and carries on when
                // Murmur is in front again; a project left mid-way is transcribed again when opened.
                task.expirationHandler = { MainActor.assumeIsolated { self.task = nil } }
                if let pending { update(fraction: pending.fraction, detail: pending.title) }
            }
        }
    }

    static func begin(project: String) {
        guard registered, !active else { return }
        active = true
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Transcribing", subtitle: project)
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request) } catch { active = false }
    }

    static func update(fraction: Double, detail: String) {
        pending = (fraction, detail)
        guard let task else { return }
        task.progress.completedUnitCount = Int64(max(0, min(1, fraction)) * 1000)
        task.updateTitle("Transcribing", subtitle: detail)
    }

    static func end(success: Bool) {
        task?.setTaskCompleted(success: success)
        task = nil
        pending = nil
        active = false
    }
}
