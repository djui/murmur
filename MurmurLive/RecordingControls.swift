import AppIntents
import SwiftUI
import WidgetKit

/// Record: for Control Center, the Lock Screen and the Action button. Opens Murmur recording.
struct RecordControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.djui.Murmur.record") {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Record", systemImage: "record.circle")
            }
        }
        .displayName("Record")
        .description("Starts a recording in Murmur.")
    }
}

/// Mark this moment of the recording in progress, without opening Murmur.
struct MarkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.djui.Murmur.mark") {
            ControlWidgetButton(action: MarkMomentIntent()) {
                Label("Mark Moment", systemImage: "bookmark.fill")
            }
        }
        .displayName("Mark Moment")
        .description("Marks the last 20 seconds of the recording in Murmur.")
    }
}
