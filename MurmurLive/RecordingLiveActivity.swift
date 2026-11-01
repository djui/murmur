import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let recordRed = Color(red: 1, green: 0.23, blue: 0.19)
private let markAmber = Color(red: 0.96, green: 0.72, blue: 0.18)

/// A recording in progress: the clock, what's been marked and heard, and buttons to pause, mark and stop,
/// on the Lock Screen and in the Dynamic Island.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        RecordDot(paused: state.isPaused)
                        Clock(state: state).font(.title3.weight(.semibold).monospacedDigit())
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Levels(levels: state.levels, paused: state.isPaused, count: 14)
                        .frame(width: 70, height: 26)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        Summary(state: state).frame(maxWidth: .infinity, alignment: .leading)
                        Controls(state: state)
                    }
                    .padding(.horizontal, 6)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    RecordDot(paused: state.isPaused)
                    Levels(levels: state.levels, paused: state.isPaused, count: 5).frame(width: 22, height: 14)
                }
            } compactTrailing: {
                Clock(state: state)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(state.isPaused ? .secondary : recordRed)
                    .frame(maxWidth: 46)
            } minimal: {
                RecordDot(paused: state.isPaused)
            }
            .keylineTint(recordRed)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<RecordingAttributes>

    var body: some View {
        let state = context.state
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                RecordDot(paused: state.isPaused)
                Text(state.isPaused ? "Paused" : "Recording").font(.headline)
                Spacer()
                Clock(state: state).font(.system(size: 30, weight: .semibold).monospacedDigit())
            }
            HStack {
                Summary(state: state)
                Spacer()
                Levels(levels: state.levels, paused: state.isPaused, count: 20).frame(width: 110, height: 20)
            }
            Controls(state: state)
        }
        .foregroundStyle(.white)
        .padding(16)
    }
}

private struct Clock: View {
    let state: RecordingAttributes.ContentState

    var body: some View {
        if let paused = state.pausedAt {
            Text(Duration.seconds(paused), format: .time(pattern: paused >= 3600 ? .hourMinuteSecond : .minuteSecond))
        } else {
            Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct RecordDot: View {
    let paused: Bool
    var body: some View {
        Circle().fill(paused ? Color.secondary : recordRed).frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

/// Marks and voices, in a line.
private struct Summary: View {
    let state: RecordingAttributes.ContentState
    var body: some View {
        HStack(spacing: 10) {
            Label("\(state.marks)", systemImage: "bookmark.fill").foregroundStyle(markAmber)
                .accessibilityLabel("\(state.marks) moments marked")
            if state.voices > 0 {
                Label("\(state.voices)", systemImage: "person.2.fill").foregroundStyle(.white.opacity(0.75))
                    .accessibilityLabel("\(state.voices) voices so far")
            }
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
        .labelStyle(.titleAndIcon)
    }
}

private struct Levels: View {
    let levels: [Float]
    let paused: Bool
    let count: Int
    var body: some View {
        GeometryReader { g in
            let recent = Array(levels.suffix(count))
            let w = g.size.width / CGFloat(max(1, count))
            HStack(alignment: .center, spacing: w * 0.35) {
                ForEach(recent.indices, id: \.self) { i in
                    Capsule().fill(paused ? Color.white.opacity(0.35) : recordRed)
                        .frame(width: w * 0.65, height: max(2, CGFloat(recent[i]) * g.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
        .accessibilityHidden(true)
    }
}

private struct Controls: View {
    let state: RecordingAttributes.ContentState
    var body: some View {
        HStack(spacing: 10) {
            PauseButton(state: state, compact: false)
            MarkButton(compact: false)
            StopButton(compact: false)
        }
    }
}

private struct PauseButton: View {
    let state: RecordingAttributes.ContentState
    let compact: Bool
    var body: some View {
        Button(intent: PauseRecordingIntent()) {
            control(state.isPaused ? "Resume" : "Pause", state.isPaused ? "record.circle" : "pause.fill", compact: compact)
        }
        .tint(.white.opacity(0.22))
    }
}

private struct MarkButton: View {
    let compact: Bool
    var body: some View {
        Button(intent: MarkMomentIntent()) { control("Mark", "bookmark.fill", compact: compact) }
            .tint(markAmber)
            .foregroundStyle(.black)
    }
}

private struct StopButton: View {
    let compact: Bool
    var body: some View {
        Button(intent: StopRecordingIntent()) { control("Stop", "stop.fill", compact: compact) }
            .tint(recordRed)
    }
}

@ViewBuilder
private func control(_ title: String, _ icon: String, compact: Bool) -> some View {
    if compact {
        Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 36, height: 30)
            .accessibilityLabel(title)
    } else {
        Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 30)
    }
}
