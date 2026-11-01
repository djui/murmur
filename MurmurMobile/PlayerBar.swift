import MurmurCore
import SwiftUI

/// Time, transport, speed and the mark button. Ink on glass: play is a solid circle in the text
/// colour, the rest are plain glyphs in ink, so the bar reads as buttons without shouting.
struct PlayerBar: View {
    let session: ProjectSession

    var body: some View {
        let player = session.player
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Timecode.short(player.time)).font(.headline.monospacedDigit())
                Text("−" + Timecode.short(max(0, session.project.duration - player.time)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Timecode.short(player.time)) of \(Timecode.short(session.project.duration))")

            Spacer(minLength: 0)

            skip(-15)
            Button { player.toggle() } label: {
                // A concrete colour: glass would dim the semantic primary into grey.
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 58, height: 58)
                    .background(Color(uiColor: .label), in: .circle)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .padding(.horizontal, 6)
            .disabled(session.mediaURL == nil)
            skip(15)

            Spacer(minLength: 0)

            Menu {
                Picker("Speed", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {
                    ForEach(PlayerModel.rates, id: \.self) { Text(PlayerModel.label($0)).tag($0) }
                }
            } label: {
                Text(PlayerModel.label(player.rate))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .frame(minWidth: 44, minHeight: 34)
                    .background(Color(.tertiarySystemFill), in: .capsule)
                    .frame(minHeight: 44)
            }
            .accessibilityLabel("Playback speed")

            let marking = session.pendingStart != nil
            Button { session.toggleMarkSection() } label: {
                Image(systemName: marking ? "bookmark.fill" : "bookmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(marking ? Color.mark : .primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(marking ? "End the mark" : "Start a mark")
            .disabled(session.project.words.isEmpty)
            .padding(.leading, 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private func skip(_ seconds: Double) -> some View {
        Button { session.player.skip(by: seconds) } label: {
            // The whole square takes the tap, not only the glyph.
            Image(systemName: seconds < 0 ? "gobackward.15" : "goforward.15")
                .font(.title2.weight(.medium))
                .frame(width: 50, height: 52)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(seconds < 0 ? "Back 15 seconds" : "Forward 15 seconds")
    }
}
