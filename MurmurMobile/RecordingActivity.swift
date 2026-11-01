import ActivityKit
import AppIntents
import Foundation

/// A recording in progress, on the Lock Screen and in the Dynamic Island. Shared by the app, which starts and
/// updates it, and the widget extension, which draws it.
struct RecordingAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the clock would have started had it never paused, so a running timer can show elapsed time.
        var startedAt: Date
        /// Elapsed seconds while paused; nil while recording.
        var pausedAt: Double?
        var marks: Int
        var voices: Int
        /// Recent loudness, 0…1, oldest first.
        var levels: [Float]

        var isPaused: Bool { pausedAt != nil }
    }

    var title: String
}

extension Notification.Name {
    /// Posted in the app when a Live Activity button is tapped; the recorder acts on it.
    static let recordingControl = Notification.Name("RecordingControl")
}

/// The Live Activity's buttons. iOS may run their intents in the widget extension rather than the app, so they
/// signal through Darwin notifications, which cross processes; the app turns them into `.recordingControl`.
enum RecordingControl: String, CaseIterable {
    case pause, mark, stop, start

    /// Set when the Record control ran in this process before the app's views were up to hear about it.
    @MainActor static var startRequested = false

    private var darwinName: CFNotificationName { CFNotificationName("com.djui.Murmur.recording.\(rawValue)" as CFString) }

    static func post(_ control: RecordingControl) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), control.darwinName, nil, nil, true)
    }

    /// In the app: relays every control to `.recordingControl` on the main queue. Call once.
    static func listen() {
        for control in allCases {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, name, _, _ in
                guard let name, let raw = (name.rawValue as String).split(separator: ".").last else { return }
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .recordingControl, object: String(raw))
                }
            }, control.darwinName.rawValue, nil, .deliverImmediately)
        }
    }
}

/// The Record control (Control Center, Lock Screen, Action button): opens Murmur and starts recording.
struct StartRecordingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Recording"
    static let description = IntentDescription("Opens Murmur and starts recording.")
    static let openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        RecordingControl.startRequested = true
        RecordingControl.post(.start)
        return .result()
    }
}

struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause or Resume Recording"
    func perform() async throws -> some IntentResult {
        RecordingControl.post(.pause)
        return .result()
    }
}

struct MarkMomentIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark This Moment"
    func perform() async throws -> some IntentResult {
        RecordingControl.post(.mark)
        return .result()
    }
}

struct StopRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Recording"
    func perform() async throws -> some IntentResult {
        RecordingControl.post(.stop)
        return .result()
    }
}
