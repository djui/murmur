import ActivityKit
import Foundation

/// Starts, updates and ends the recording's Live Activity.
@MainActor
enum LiveRecording {
    private static var activity: Activity<RecordingAttributes>?

    static func start(title: String, state: RecordingAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()
        activity = try? Activity.request(attributes: RecordingAttributes(title: title), content: .init(state: state, staleDate: nil))
    }

    static func update(_ state: RecordingAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    static func end() {
        for running in Activity<RecordingAttributes>.activities {
            Task { await running.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }

    /// The activity's state for a recorder, the level history thinned to what the activity draws.
    static func state(of recorder: MicRecorder) -> RecordingAttributes.ContentState {
        let levels = stride(from: 0, to: recorder.history.count, by: 4).map { i in
            min(1, recorder.history[i..<min(i + 4, recorder.history.count)].max() ?? 0)
        }
        return .init(startedAt: Date().addingTimeInterval(-recorder.elapsed),
                     pausedAt: recorder.state == .paused ? recorder.elapsed : nil,
                     marks: recorder.marks.count, voices: recorder.voiceCount, levels: levels)
    }

    #if DEBUG
    static func demo(paused: Bool) {
        let levels: [Float] = (0..<40).map { i in Float(0.25 + 0.6 * abs(sin(Double(i) * 0.55)) * (i % 7 == 0 ? 0.4 : 1)) }
        start(title: "Team sync", state: .init(startedAt: Date().addingTimeInterval(-754), pausedAt: paused ? 754 : nil,
                                               marks: 2, voices: 3, levels: levels))
    }
    #endif
}
