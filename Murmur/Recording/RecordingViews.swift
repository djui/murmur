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
            .onChange(of: lines) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
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
                    .buttonStyle(.borderless).help("Shrink to a strip")
                Button { CompactPanelController.shared.expand() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .buttonStyle(.borderless).help("Open the full recording window")
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            Divider()
            HStack(spacing: 14) {
                HStack(spacing: 6) { Text("Me").foregroundStyle(meColor); LevelBar(level: recorder.micLevel, color: meColor) }
                HStack(spacing: 6) { Text("Others").foregroundStyle(.secondary); LevelBar(level: recorder.systemLevel, color: .secondary) }
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            if let warning = recorder.warning {
                Text(warning).font(.system(size: 11)).foregroundStyle(.orange).padding(10)
            }
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
            Divider()
            HStack(spacing: 6) {
                Button { recorder.addMark() } label: {
                    Label { Text("Mark ") + Text("⌥⌘M").foregroundStyle(.secondary) } icon: {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.mark).frame(width: 8, height: 8)
                    }
                }
                .buttonStyle(PillStyle())
                Button { recorder.togglePause() } label: { Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill") }
                    .buttonStyle(PillStyle())
                    .help(recorder.state == .paused ? "Resume" : "Pause")
                Spacer()
                Button { recorder.stop() } label: { Label("Stop", systemImage: "stop.fill") }
                    .buttonStyle(.borderedProminent)
                    .tint(.primary)
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
            .padding(.bottom, 10)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// The panel shrunk to one line.
struct StripView: View {
    @Bindable var recorder: RecordingController

    var body: some View {
        HStack(spacing: 10) {
            RecordingDot(paused: recorder.state == .paused)
            Text(Timecode.short(recorder.elapsed)).font(.system(size: 14, weight: .medium, design: .monospaced))
            HStack(spacing: 2) {
                ForEach(Array(recorder.micHistory.suffix(13).enumerated()), id: \.offset) { i, v in
                    Capsule().fill(Color.secondary).frame(width: 2.5, height: max(3, CGFloat(max(v, recorder.systemHistory.suffix(13)[recorder.systemHistory.count - 13 + i])) * 22))
                }
            }
            .frame(width: 52, height: 24)
            if let line = recorder.lines.last {
                (Text(line.isMe ? "Me " : "Others ").fontWeight(.semibold).foregroundStyle(line.isMe ? meColor : .secondary) + Text(line.text))
                    .font(.system(size: 13)).lineLimit(1).truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
            Button { recorder.addMark() } label: { RoundedRectangle(cornerRadius: 3).fill(Palette.mark).frame(width: 10, height: 10) }
                .buttonStyle(.borderless).help("Mark this moment (⌥⌘M)")
            Button { CompactPanelController.shared.setStrip(false) } label: { Image(systemName: "text.alignleft") }
                .buttonStyle(.borderless).help("Show the transcript panel")
            Button { recorder.stop() } label: {
                Image(systemName: "stop.fill").foregroundStyle(.white).frame(width: 28, height: 28).background(Circle().fill(Color.primary))
            }
            .buttonStyle(.plain).help("Stop recording")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
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
                    Button { recorder.addMark() } label: { Text("Mark moment ") + Text("⌥⌘M").foregroundStyle(.secondary) }
                        .buttonStyle(PillStyle())
                    Button(recorder.state == .paused ? "Resume" : "Pause") { recorder.togglePause() }.buttonStyle(PillStyle())
                    Button { dismissWindow(id: "recording"); CompactPanelController.shared.show() } label: {
                        Label("Compact", systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                    .buttonStyle(PillStyle())
                    Button { recorder.stop(); dismissWindow(id: "recording") } label: { Label("Stop and finish", systemImage: "stop.fill") }
                        .buttonStyle(.borderedProminent).tint(.primary)
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
