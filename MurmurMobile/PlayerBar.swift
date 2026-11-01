import MurmurCore
import SwiftUI

/// Speed, back, play or pause, forward, mark: five buttons mirrored around play, which sits on the centre line.
/// The time lives with the waveform (`TimeLabel` in the score header). Ink on glass: play is a solid circle in the
/// text colour, the rest plain glyphs in ink, so the bar reads as buttons without shouting.
struct PlayerBar: View {
    let session: ProjectSession

    var body: some View {
        HStack(spacing: 0) {
            SpeedChip(session: session).frame(maxWidth: .infinity)
            Transport(session: session)
            MarkButton(session: session).frame(maxWidth: .infinity)
        }
    }
}

/// The time, and under it the time left or the length; tap to switch.
struct TimeLabel: View {
    let session: ProjectSession
    var inline = false
    @AppStorage(AppSettings.showTimeLeft) private var showTimeLeft = true

    var body: some View {
        let player = session.player
        let duration = session.project.duration
        let other = showTimeLeft ? "−" + Timecode.short(max(0, duration - player.time)) : Timecode.short(duration)
        Button { withAnimation(.snappy) { showTimeLeft.toggle() } } label: {
            Group {
                if inline {
                    HStack(spacing: 6) {
                        Text(Timecode.short(player.time)).font(.subheadline.weight(.semibold).monospacedDigit())
                        Text(other).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Timecode.short(player.time)).font(.headline.monospacedDigit())
                        Text(other).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel("\(Timecode.short(player.time)) of \(Timecode.short(duration))")
        .accessibilityHint(showTimeLeft ? "Shows the length instead of the time left" : "Shows the time left instead of the length")
    }
}

/// Back, play or pause, forward. The skip glyphs turn when tapped; the step is set in Settings.
struct Transport: View {
    let session: ProjectSession
    var large = false
    @AppStorage(AppSettings.skipSeconds) private var skipSeconds = 15

    var body: some View {
        let player = session.player
        HStack(spacing: large ? 18 : 0) {
            SkipButton(session: session, seconds: -Double(skipSeconds))
            Button { player.toggle() } label: {
                // A concrete colour: glass would dim the semantic primary into grey.
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(large ? .title : .title2)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: large ? 64 : 58, height: large ? 64 : 58)
                    .background(Color(uiColor: .label), in: .circle)
                    .contentShape(Circle())
            }
            .buttonStyle(PressScale())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .padding(.horizontal, 6)
            .disabled(session.mediaURL == nil)
            SkipButton(session: session, seconds: Double(skipSeconds))
        }
        .foregroundStyle(.primary)
    }
}

private struct SkipButton: View {
    let session: ProjectSession
    let seconds: Double
    @State private var taps = 0

    /// The symbols drawn for the rotate effect: the arrow turns on its own layer, the number stays put.
    private var symbol: String {
        let n = Int(abs(seconds))
        let way = seconds < 0 ? "counterclockwise" : "clockwise"
        return [5, 10, 15, 30].contains(n) ? "\(n).arrow.trianglehead.\(way)" : "arrow.trianglehead.\(way)"
    }

    var body: some View {
        Button {
            session.player.skip(by: seconds)
            taps += 1
        } label: {
            // The whole square takes the tap, not only the glyph; the arrow turns the way it jumps.
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .symbolEffect(.rotate.byLayer, options: .speed(1.5), value: taps)
                .frame(width: 50, height: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Back \(Int(-seconds)) seconds" : "Forward \(Int(seconds)) seconds")
    }
}

struct SpeedChip: View {
    let session: ProjectSession

    var body: some View {
        let player = session.player
        Menu {
            Picker("Speed", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {
                ForEach(PlayerModel.rates, id: \.self) { Text(PlayerModel.label($0)).tag($0) }
            }
        } label: {
            Text(PlayerModel.label(player.rate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 34)
                .background(Color(.tertiarySystemFill), in: .capsule)
                .frame(minHeight: 44)
        }
        .foregroundStyle(.primary)
        .animation(.snappy, value: player.rate)
        .accessibilityLabel("Playback speed")
    }
}

struct MarkButton: View {
    let session: ProjectSession

    var body: some View {
        let marking = session.pendingStart != nil
        Button { session.toggleMarkSection() } label: {
            Image(systemName: marking ? "bookmark.fill" : "bookmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(marking ? Color.mark : .primary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: session.project.marks.count)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(marking ? "End the mark" : "Start a mark")
        .disabled(session.project.words.isEmpty)
    }
}

/// Shrinks a little while pressed.
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}
