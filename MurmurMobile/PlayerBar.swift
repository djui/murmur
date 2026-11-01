import MurmurCore
import SwiftUI

/// Time, transport, speed and the mark button.
struct PlayerBar: View {
    let session: ProjectSession

    var body: some View {
        let player = session.player
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Timecode.short(player.time))
                    .font(.system(.title3, design: .monospaced).weight(.medium))
                    .foregroundStyle(Color.primary)
                Text(Timecode.short(session.project.duration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }
            .monospacedDigit()
            .frame(minWidth: 72, alignment: .leading)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 4)

            Button { player.skip(by: -15) } label: { Image(systemName: "gobackward.15") }
                .accessibilityLabel("Back 15 seconds")
                .frame(width: 48, height: 44)
            Button { player.toggle() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 56, height: 56)
                    .background(Color.accentColor, in: .circle)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .padding(.horizontal, 4)
            .disabled(session.mediaURL == nil)
            Button { player.skip(by: 15) } label: { Image(systemName: "goforward.15") }
                .accessibilityLabel("Forward 15 seconds")
                .frame(width: 48, height: 44)

            Spacer(minLength: 4)

            Menu {
                Picker("Speed", selection: Binding(get: { player.rate }, set: { player.rate = $0 })) {
                    ForEach(PlayerModel.rates, id: \.self) { Text(PlayerModel.label($0)).tag($0) }
                }
            } label: {
                Text(PlayerModel.label(player.rate))
                    .font(.system(.subheadline, design: .monospaced))
                    .frame(minWidth: 40, minHeight: 44)
            }
            .accessibilityLabel("Playback speed")

            Button {
                session.toggleMarkSection()
            } label: {
                Image(systemName: session.pendingStart == nil ? "bookmark" : "bookmark.fill")
                    .foregroundStyle(session.pendingStart == nil ? Color.accentColor : Color.mark)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(session.pendingStart == nil ? "Start a mark" : "End the mark")
            .disabled(session.project.words.isEmpty)
        }
        .font(.title3)
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}
