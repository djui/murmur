import MurmurCore
import SwiftUI

private var meColor: Color { Palette.speaker(0) }

struct LevelBar: View {
    let level: Float
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well)
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(1, level)))
            }
        }
        .frame(height: 4)
        .animation(.linear(duration: 0.1), value: level)
    }
}

struct RecordingDot: View {
    let paused: Bool
    var body: some View {
        Circle().fill(paused ? Color.secondary : Palette.recording)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Palette.recording.opacity(paused ? 0 : 0.25), lineWidth: 6))
    }
}

struct LiveLinesView: View {
    let lines: [LiveLine]
    let marks: [Mark]
    var compact = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: compact ? 10 : 12) {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(line.isMe ? "Me" : "Others")
                                    .font(.system(size: compact ? 11.5 : 12, weight: .semibold))
                                    .foregroundStyle(line.isMe ? meColor : .secondary)
                                Text(Timecode.short(line.start)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                if marks.contains(where: { $0.end - 5 >= line.start - 1 && $0.end - 5 <= line.start + 20 }) {
                                    Text("Marked").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.markText)
                                        .padding(.horizontal, 4)
                                        .background(RoundedRectangle(cornerRadius: 3).fill(Palette.mark.opacity(0.18)))
                                }
                            }
                            Text(line.text)
                                .font(.system(size: compact ? 13 : 14))
                                .foregroundStyle(line.tentative ? .secondary : .primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .id(line.id)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: lines) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            // Resizing the window keeps the newest line in view.
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }
}

/// "MacBook Pro Speakers · echo cancelled": the microphone is hearing the call and the system is taking it out.
struct EchoCancelledLine: View {
    let speakers: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "speaker.wave.2")
            Text("\(speakers) · \(Text("echo cancelled").foregroundStyle(Color.accentColor).fontWeight(.semibold))")
                .lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Your speakers are on, so the microphone hears the call. Murmur cancels it while recording; headphones avoid it.")
    }
}

/// Stop: white on red, readable whether or not the window is focused.
struct StopButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "stop.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7).fill(Palette.recording.opacity(isEnabled ? 1 : 0.4)))
        }
        .buttonStyle(.plain)
    }
}

/// The compact floating panel.
struct CompactRecorderView: View {
    @Bindable var recorder: RecordingController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                RecordingDot(paused: recorder.state == .paused)
                Text(Timecode.short(recorder.elapsed)).font(.system(size: 15, weight: .medium, design: .monospaced))
                Text(recorder.state == .starting ? "Starting…" : recorder.state == .finishing ? "Finishing…" : "Recording")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button { CompactPanelController.shared.setStrip(true) } label: { Image(systemName: "minus") }
                    .buttonStyle(IconButtonStyle()).help("Shrink to a strip")
                    .accessibilityLabel("Shrink to a strip")
                Button { CompactPanelController.shared.expand() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(IconButtonStyle()).help("Open the full recording window")
                    .accessibilityLabel("Open the full recording window")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(WindowDragArea())
            Divider()
            HStack(spacing: 14) {
                HStack(spacing: 6) { Text("Me").foregroundStyle(meColor); LevelBar(level: recorder.micLevel, color: meColor) }
                HStack(spacing: 6) { Text("Others").foregroundStyle(.secondary); LevelBar(level: recorder.systemLevel, color: .secondary) }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, recorder.echoCancelledOn == nil ? 8 : 4)
            if let speakers = recorder.echoCancelledOn {
                EchoCancelledLine(speakers: speakers)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }
            Divider()
            if let warning = recorder.warning {
                Text(warning).font(.system(size: 11)).foregroundStyle(.orange).padding(10)
            }
            // The live transcript sits on the opaque window color: the glass around it floats over
            // other apps, and words must not compete with whatever is behind the panel.
            Group {
                if recorder.liveAvailable {
                    LiveLinesView(lines: recorder.lines, marks: recorder.marks)
                        .overlay {
                            if recorder.lines.isEmpty {
                                Text("Listening… the transcript appears a few seconds behind.")
                                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                            }
                        }
                } else {
                    Text("Recording without a live transcript: the speech model isn’t downloaded yet.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding().frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            HStack(spacing: 6) {
                MarkPill(recorder: recorder)
                Button { recorder.togglePause() } label: {
                    Label(recorder.state == .paused ? "Resume" : "Pause", systemImage: recorder.state == .paused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(PillStyle())
                Spacer()
                StopButton(title: "Stop") { recorder.stop() }
                    .disabled(recorder.state == .finishing || recorder.state == .starting)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            HStack(spacing: 6) {
                let hidden = AppSettings.bool(AppSettings.hideRecorderFromSharing)
                Image(systemName: hidden ? "eye.slash" : "eye")
                Text(hidden ? "Hidden from screen sharing" : "Visible in screen sharing")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
            .background(WindowDragArea())
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// A mark just added, shown for a moment so a click or ⌥⌘M visibly did something.
@Observable
@MainActor
final class MarkFlash {
    private(set) var mark: Mark?
    private var hide: Task<Void, Never>?

    func show(_ mark: Mark?) {
        guard let mark else { return }
        withAnimation(.snappy(duration: 0.2)) { self.mark = mark }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.mark = nil }
        }
    }
}

/// Mark, with the number of marks so far; turns amber with the time for a moment when a mark is made.
struct MarkPill: View {
    let recorder: RecordingController
    @State private var flash = MarkFlash()

    var body: some View {
        Button { recorder.addMark() } label: {
            Label {
                // Narrow windows drop the shortcut first, then the word, never the count or the time.
                ViewThatFits(in: .horizontal) {
                    label(word: true, shortcut: true)
                    label(word: true, shortcut: false)
                    label(word: false, shortcut: false)
                }
            } icon: {
                if flash.mark != nil {
                    Image(systemName: "checkmark").foregroundStyle(Palette.markText)
                } else {
                    RoundedRectangle(cornerRadius: 2).fill(Palette.mark).frame(width: 8, height: 8)
                }
            }
        }
        .buttonStyle(PillStyle())
        .overlay(RoundedRectangle(cornerRadius: 7).fill(Palette.mark.opacity(flash.mark == nil ? 0 : 0.18)).allowsHitTesting(false))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.mark.opacity(flash.mark == nil ? 0 : 1)).allowsHitTesting(false))
        .help("Mark this moment (\(ShortcutStore.shared.markMoment.symbol) from any app)")
        .accessibilityLabel("Mark this moment, \(recorder.marks.count) marked")
        .onChange(of: recorder.marks.count) { old, new in if new > old { flash.show(recorder.marks.last) } }
    }

    func label(word: Bool, shortcut: Bool) -> some View {
        let key = Text(shortcut ? " " + ShortcutStore.shared.markMoment.symbol : "").foregroundStyle(.secondary)
        let count = Text(recorder.marks.isEmpty ? "" : "\(recorder.marks.count)").monospacedDigit().foregroundStyle(Palette.markText)
        return Group {
            if let mark = flash.mark {
                Text("\(word ? "Marked " : "")\(Text(Timecode.short(mark.end - 5)).monospacedDigit())").foregroundStyle(Palette.markText)
            } else if word {
                Text("Mark\(recorder.marks.isEmpty ? "" : " ")\(count)\(key)")
            } else {
                recorder.marks.isEmpty ? Text("Mark") : count
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// A small icon button that is easy to hit: a 24 pt target with a hover and a pressed fill.
struct IconButtonStyle: ButtonStyle {
    var width: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, width: width)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let width: CGFloat
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(hovering || configuration.isPressed ? .primary : .secondary)
            .frame(width: width, height: 24)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : hovering ? 0.08 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovering = $0 }
    }
}

/// The panel shrunk to one line.
struct StripView: View {
    @Bindable var recorder: RecordingController
    @State private var flash = MarkFlash()
    @State private var width: CGFloat = 640

    var body: some View {
        HStack(spacing: 10) {
            RecordingDot(paused: recorder.state == .paused)
            Text(Timecode.short(recorder.elapsed)).font(.system(size: 14, weight: .medium, design: .monospaced))
            if width >= 520 { HStack(spacing: 2) {
                ForEach(Array(recorder.micHistory.suffix(13).enumerated()), id: \.offset) { i, v in
                    Capsule().fill(Color.secondary).frame(width: 2.5, height: max(3, CGFloat(max(v, recorder.systemHistory.suffix(13)[recorder.systemHistory.count - 13 + i])) * 22))
                }
            }
            .frame(width: 52, height: 24) }
            if let mark = flash.mark {
                Label("Marked at \(Timecode.short(mark.end - 5))", systemImage: "checkmark")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.markText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            } else if let line = recorder.lines.last {
                Text("\(Text(line.isMe ? "Me " : "Others ").fontWeight(.semibold).foregroundStyle(line.isMe ? meColor : .secondary))\(line.text)")
                    .font(.system(size: 13)).lineLimit(1).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
            Button { recorder.addMark() } label: {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Palette.mark).frame(width: 10, height: 10)
                        .scaleEffect(flash.mark == nil ? 1 : 1.4)
                    if !recorder.marks.isEmpty {
                        Text("\(recorder.marks.count)").font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.markText)
                    }
                }
            }
            .buttonStyle(IconButtonStyle(width: recorder.marks.isEmpty ? 28 : 40))
            .help("Mark this moment (\(ShortcutStore.shared.markMoment.symbol))")
            .accessibilityLabel("Mark this moment, \(recorder.marks.count) marked")
            Button { CompactPanelController.shared.setStrip(false) } label: { Image(systemName: "text.alignleft") }
                .buttonStyle(IconButtonStyle()).help("Show the transcript panel")
                .accessibilityLabel("Show the transcript panel")
            Button { recorder.stop() } label: {
                Image(systemName: "stop.fill").foregroundStyle(.white).frame(width: 28, height: 28).background(Circle().fill(Palette.recording))
            }
            .buttonStyle(.plain).help("Stop recording")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WindowDragArea())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: recorder.marks.count) { old, new in if new > old { flash.show(recorder.marks.last) } }
        .glassEffect(.regular, in: .capsule)
        .clipShape(Capsule())
    }
}

/// The full recording window.
struct RecordingWindow: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        let recorder = app.recorder
        VStack(spacing: 0) {
            if recorder.isActive {
                HStack(spacing: 12) {
                    RecordingDot(paused: recorder.state == .paused)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recorder.title).font(.system(size: 13, weight: .semibold))
                        Text("Saved continuously to \(ProjectFile.defaultFolder.lastPathComponent)/Recordings · two tracks")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Text(Timecode.short(recorder.elapsed)).font(.system(size: 22, weight: .medium, design: .monospaced)).padding(.leading, 14)
                    Spacer()
                    Button { recorder.addMark() } label: { Text("Mark moment \(Text("M").foregroundStyle(.secondary))") }
                        .buttonStyle(PillStyle())
                        .help("Mark this moment (M here, \(ShortcutStore.shared.markMoment.symbol) from any app)")
                    Button(recorder.state == .paused ? "Resume" : "Pause") { recorder.togglePause() }.buttonStyle(PillStyle())
                        .help(recorder.state == .paused ? "Resume (Space)" : "Pause (Space)")
                    Button { dismissWindow(id: "recording"); CompactPanelController.shared.show() } label: {
                        Label("Compact", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(PillStyle())
                    StopButton(title: "Stop and finish") { recorder.stop(); dismissWindow(id: "recording") }
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop and open the recording as a project (⌘.)")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                Divider()
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            track("Me", "mic", recorder.micHistory, meColor)
                            track("Others", "system", recorder.systemHistory, .secondary)
                            Text("Last 35 seconds · the full timeline appears when you stop")
                                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.leading, 132)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        Divider()
                        HStack {
                            Text("Live transcript").font(.system(size: 13, weight: .semibold))
                            Text("a few seconds behind · other people are told apart when you stop")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        LiveLinesView(lines: recorder.lines, marks: recorder.marks, compact: false)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Sources").font(.system(size: 13, weight: .semibold))
                        source("Microphone", "→ Me", "Default input", recorder.micLevel, meColor)
                        if let speakers = recorder.echoCancelledOn { EchoCancelledLine(speakers: speakers) }
                        source("System audio", "→ Others", recorder.systemSourceName, recorder.systemLevel, .secondary)
                        if let warning = recorder.warning { Text(warning).font(.system(size: 11)).foregroundStyle(.orange) }
                        Text("Marked moments").font(.system(size: 13, weight: .semibold)).padding(.top, 6)
                        ForEach(recorder.marks) { mark in
                            HStack {
                                RoundedRectangle(cornerRadius: 2).fill(Palette.mark).frame(width: 8, height: 8)
                                Text(mark.name).font(.system(size: 12))
                            }
                        }
                        Spacer()
                        Text("On stop: speakers are told apart on the system track, word timing is tightened, and the recording opens as a project.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .frame(width: 280)
                    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.35))
                }
            } else {
                ContentUnavailableView {
                    Label("Not recording", systemImage: "record.circle")
                } description: {
                    Text("Record your microphone and the sound of your call app, with a live transcript.")
                } actions: {
                    Button("New Recording") { recorder.start() }.buttonStyle(.borderedProminent)
                }
            }
        }
        .frame(minWidth: 820, minHeight: 520)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down) { press in
            // Space pauses or resumes, M marks a moment; ⌘. on the Stop button finishes.
            let recorder = app.recorder
            guard recorder.isActive, press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
            if press.key == .space { recorder.togglePause(); return .handled }
            if press.characters.lowercased() == "m" { recorder.addMark(); return .handled }
            return .ignored
        }
    }

    func track(_ name: String, _ kind: String, _ history: [Float], _ color: Color) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(name).fontWeight(.semibold)
                Text("· \(kind)").foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .frame(width: 120, alignment: .leading)
            Canvas { ctx, size in
                let w = size.width / CGFloat(history.count)
                for (i, v) in history.enumerated() {
                    let h = max(2, CGFloat(v) * (size.height - 4))
                    ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * w, y: (size.height - h) / 2, width: max(1, w - 2), height: h), cornerRadius: 1),
                             with: .color(v > 0.02 ? color : Palette.silence))
                }
            }
            .frame(height: 44)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.well.opacity(0.6)))
        }
    }

    func source(_ title: String, _ target: String, _ device: String, _ level: Float, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(title).fontWeight(.semibold); Spacer(); Text(target).foregroundStyle(.secondary) }
            Text(device).foregroundStyle(.secondary)
            LevelBar(level: level, color: color)
        }
        .font(.system(size: 12))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}

struct RecordingMenu: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let recorder = app.recorder
        Text("Recording · \(Timecode.short(recorder.elapsed))")
        Button("Mark Moment") { recorder.addMark() }
        Button(recorder.state == .paused ? "Resume" : "Pause") { recorder.togglePause() }
        Divider()
        Button("Show Compact Window") { CompactPanelController.shared.show() }
        Button("Open Full Window") { CompactPanelController.shared.expand() }
        Divider()
        Button("Stop and Finish") { recorder.stop() }
    }
}

struct RecordingMenuLabel: View {
    let recorder: RecordingController

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: recorder.state == .paused ? "pause.circle.fill" : "record.circle.fill")
            Text(Timecode.short(recorder.elapsed)).monospacedDigit()
        }
    }
}
