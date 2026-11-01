import MurmurCore
import SwiftUI

/// Recording: level, time, live transcript, moment marks, pause and stop.
struct RecordView: View {
    let onFinish: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = MicRecorder()
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                controls
            }
            .navigationTitle(recorder.isActive ? recorder.title : "New Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(recorder.isActive ? "Discard" : "Cancel", role: recorder.isActive ? .destructive : .cancel) {
                        if recorder.isActive { confirmDiscard = true } else { dismiss() }
                    }
                    .disabled(recorder.state == .finishing)
                }
            }
            .confirmationDialog("Discard this recording?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard Recording", role: .destructive) { recorder.discard(); dismiss() }
            }
            .alert("Couldn’t record", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recorder.error ?? "")
            }
        }
        .interactiveDismissDisabled(recorder.isActive || recorder.state == .finishing)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            recorder.discard()
        }
        // Stopped from the Lock Screen: open what was recorded.
        .onChange(of: recorder.stoppedFromLockScreen) { _, url in
            if let url { onFinish(url) }
            dismiss()
        }
    }

    /// Stops, opens the new project, and closes the recorder; from the Stop button or the Lock Screen.
    private func finish() {
        guard recorder.isActive else { return }
        Task {
            if let url = await recorder.stop() { onFinish(url) }
            dismiss()
        }
    }

    @ViewBuilder
    private var transcript: some View {
        if recorder.state == .idle {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "mic").font(.system(size: 44, weight: .light)).foregroundStyle(.secondary)
                Text("Put your iPhone where everyone can be heard.")
                    .font(.headline).multilineTextAlignment(.center)
                Text("Murmur keeps recording with the screen locked. Voices are told apart as you go and settled once you stop.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.horizontal, 32)
        } else if recorder.state == .starting {
            VStack(spacing: 10) {
                Spacer()
                ProgressView()
                Text("Getting the microphone ready…").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if !recorder.liveAvailable {
            ContentUnavailableView("Recording", systemImage: "waveform",
                                   description: Text(recorder.liveFailed
                                       ? "The live transcript couldn’t start. The recording is fine and is transcribed when you stop."
                                       : "The live transcript appears once Murmur’s models are downloaded. The recording is transcribed when you stop."))
        } else if recorder.lines.isEmpty {
            ContentUnavailableView("Listening…", systemImage: "waveform", description: Text("Words appear here as they are spoken."))
        } else {
            ScrollViewReader { proxy in
                List(recorder.lines) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        if recorder.voiceCount > 0 {
                            VoiceLabel(voice: line.voice)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(Timecode.short(line.start))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(line.text)
                                .foregroundStyle(line.tentative ? .secondary : .primary)
                        }
                    }
                    .listRowSeparator(.hidden)
                    .id(line.id)
                }
                .listStyle(.plain)
                .onChange(of: recorder.lines) { _, lines in
                    if let last = lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            LevelMeter(history: recorder.history, active: recorder.state == .recording)
                .frame(height: 44)
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.recordRed)
                    .frame(width: 12, height: 12)
                    .opacity(recorder.state == .recording ? 1 : 0.25)
                    .accessibilityHidden(true)
                Text(Timecode.short(recorder.elapsed))
                    .font(.system(size: 44, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(recorder.state == .paused ? .secondary : .primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(recorder.state == .paused ? "Paused at \(Timecode.short(recorder.elapsed))" : "Recorded \(Timecode.short(recorder.elapsed))")
            // Always laid out, so the controls stay put when the first moment is marked.
            HStack(spacing: 14) {
                if recorder.voiceCount > 0 && recorder.state != .paused {
                    Label("\(recorder.voiceCount) \(recorder.voiceCount == 1 ? "voice" : "voices") so far", systemImage: "person.2")
                        .foregroundStyle(.secondary)
                }
                Label(recorder.state == .paused ? "Paused" : "\(recorder.marks.count) \(recorder.marks.count == 1 ? "moment" : "moments") marked",
                      systemImage: recorder.state == .paused ? "pause.fill" : "bookmark.fill")
                    .foregroundStyle(recorder.state == .paused ? Color.secondary : Color.mark)
                    .opacity(recorder.state == .paused || !recorder.marks.isEmpty ? 1 : 0)
            }
            .font(.footnote)
            HStack(spacing: 36) {
                Button {
                    recorder.togglePause()
                } label: {
                    Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                        .font(.title2).frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
                .clipShape(.circle)
                .accessibilityLabel(recorder.state == .paused ? "Resume" : "Pause")
                .disabled(!recorder.isActive)

                Button {
                    if recorder.isActive {
                        finish()
                    } else {
                        Task { await recorder.start() }
                    }
                } label: {
                    ZStack {
                        Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 3).frame(width: 76, height: 76)
                        if recorder.isActive {
                            RoundedRectangle(cornerRadius: 6).fill(Color.recordRed).frame(width: 30, height: 30)
                        } else {
                            Circle().fill(Color.recordRed).frame(width: 62, height: 62)
                        }
                    }
                    .animation(.snappy, value: recorder.isActive)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(recorder.isActive ? "Stop and transcribe" : "Start recording")
                .disabled(recorder.state == .starting || recorder.state == .finishing)

                Button {
                    recorder.addMark()
                } label: {
                    Image(systemName: "bookmark").font(.title2).frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
                .clipShape(.circle)
                .accessibilityLabel("Mark this moment")
                .accessibilityHint("Keeps the last 20 seconds as a mark")
                .disabled(!recorder.isActive)
            }
            .sensoryFeedback(.impact, trigger: recorder.marks.count)
            .sensoryFeedback(.start, trigger: recorder.state == .recording)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .overlay { if recorder.state == .finishing { ProgressView("Saving…").padding().glassEffect(in: .rect(cornerRadius: 14)) } }
    }
}

/// A line's provisional voice: muted and underlined with dashes, because the next pass of Who may
/// change it; the real speakers, in full colour, come with the transcription after the recording stops.
struct VoiceLabel: View {
    let voice: Int?

    var body: some View {
        if let voice {
            Text(MicRecorder.voiceName(voice))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SpeakerScheme.current.color(voice).mix(with: .secondary, by: 0.35))
                .underline(pattern: .dash)
                .accessibilityLabel("Probably \(MicRecorder.voiceName(voice))")
        } else {
            Text("Listening…").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
        }
    }
}

/// The last nine seconds of input level as bars.
struct LevelMeter: View {
    let history: [Float]
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let step = size.width / CGFloat(history.count)
            for (i, value) in history.enumerated() {
                let h = max(2, CGFloat(value) * size.height)
                let rect = CGRect(x: CGFloat(i) * step + step * 0.2, y: (size.height - h) / 2, width: step * 0.6, height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: step * 0.3),
                             with: .color(active ? Color.recordRed.opacity(0.4 + 0.6 * Double(i) / Double(history.count)) : .secondary.opacity(0.4)))
            }
        }
        .accessibilityHidden(true)
    }
}
