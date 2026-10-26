import MurmurCore
import SwiftUI

/// First launch: download the models Murmur needs.
struct FirstLaunchView: View {
    @Environment(ModelManager.self) private var models
    @Environment(\.dismiss) private var dismiss

    var required: [ModelKind] { ModelKind.allCases.filter(\.isRequired) }
    var totalMB: Int { required.compactMap(\.approxMB).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                Text("Getting Murmur ready").font(.system(size: 20, weight: .bold))
                Text("Murmur transcribes on this Mac. The speech and speaker models download once, then work offline. Nothing you open is uploaded.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                ForEach(required) { kind in
                    ModelRow(kind: kind, state: models.state(kind))
                    Divider()
                }
                HStack {
                    Text(models.isDownloading ? "Downloading…" : models.requiredReady ? "All set" : "One-time download")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("≈ \(totalMB) MB").fontWeight(.semibold)
                }
                .font(.system(size: 12))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))

            VStack(alignment: .leading, spacing: 8) {
                Text("Optional, downloaded when you turn them on").font(.system(size: 12, weight: .semibold))
                HStack {
                    chip("Hide fillers", "Uhm")
                    chip("Enhance audio", "Clear")
                    chip("Titles and summaries", "Apple Intelligence")
                }
                Text("Microphone and system-audio permission are asked the first time you record.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.top, 16)

            Spacer(minLength: 18)
            HStack {
                Text("Stored in Application Support · removable in Settings").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                if !models.requiredReady {
                    Button("Later") {
                        UserDefaults.standard.set(true, forKey: AppSettings.skippedOnboarding)
                        dismiss()
                    }
                }
                if models.requiredReady {
                    Button("Continue") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Button("Download (\(totalMB) MB)") { Task { await models.downloadRequired() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(models.isDownloading)
                }
            }
        }
        .padding(28)
        .frame(width: 600)
    }

    func chip(_ title: String, _ engine: String) -> some View {
        (Text(title) + Text(" · \(engine)").foregroundStyle(.secondary))
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(Capsule().strokeBorder(Color(nsColor: .separatorColor)))
    }
}

struct ModelRow: View {
    let kind: ModelKind
    let state: ModelState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                (Text(kind.title).fontWeight(.semibold) + Text(" · \(kind.engine)").foregroundStyle(.secondary))
                    .font(.system(size: 13))
                Text(kind.detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Group {
                switch state {
                case .ready: Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .downloading(let f): ProgressView(value: f).frame(width: 120)
                case .preparing: HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Preparing…") }
                case .failed(let message): Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).lineLimit(1)
                case .missing: Text(kind.approxMB.map { "\($0) MB" } ?? "—").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .frame(maxWidth: 200, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Shown in the project window until the first words arrive.
struct ProcessingView: View {
    let session: ProjectSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Text((session.project.media.map { URL(fileURLWithPath: $0.path).pathExtension.uppercased() } ?? "REC"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Palette.well))
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.project.displayTitle).font(.system(size: 15, weight: .semibold))
                    Text(session.project.duration > 0 ? Timecode.short(session.project.duration) : "Reading…")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if !session.peaks.isEmpty {
                Canvas { ctx, size in
                    let count = max(1, Int(size.width / 4))
                    for i in 0..<count {
                        let a = Double(i) / Double(count) * session.project.duration
                        let b = Double(i + 1) / Double(count) * session.project.duration
                        let h = max(2, CGFloat(Peaks.loudness(Peaks.peak(in: session.peaks, from: a, to: b))) * (size.height - 4))
                        ctx.fill(Path(roundedRect: CGRect(x: CGFloat(i) * 4, y: (size.height - h) / 2, width: 2, height: h), cornerRadius: 1),
                                 with: .color(Color.accentColor.opacity(0.5)))
                    }
                }
                .frame(height: 44)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Palette.well))
                Text("The waveform appears first, so you can start listening while the words arrive.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(session.steps) { step in
                    HStack(spacing: 10) {
                        icon(step).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(step.title).font(.system(size: 13, weight: step.state == .pending ? .regular : .semibold))
                                .foregroundStyle(step.state == .pending ? .secondary : .primary)
                            Text(step.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let s = step.seconds {
                            Text(String(format: "%.1f s", s)).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder func icon(_ step: PipelineStep) -> some View {
        switch step.state {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
        case .running:
            if let f = step.fraction { ProgressView(value: f).progressViewStyle(.circular).controlSize(.small) }
            else { ProgressView().controlSize(.small) }
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .pending: Image(systemName: "circle").foregroundStyle(.tertiary)
        }
    }
}

/// Asked when the spoken language is one the main transcriber doesn't know.
struct LanguagePromptView: View {
    let prompt: LanguagePrompt
    let answer: (LanguageChoice) -> Void

    enum Option: Hashable { case apple, other, voz }
    @State private var option: Option
    @State private var other = "en"

    init(prompt: LanguagePrompt, answer: @escaping (LanguageChoice) -> Void) {
        self.prompt = prompt
        self.answer = answer
        _option = State(initialValue: prompt.appleSupports ? .apple : .other)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This sounds like \(languageName(prompt.language))").font(.system(size: 16, weight: .bold))
            Text("Detected by Ear with \(Int(prompt.confidence * 100))% confidence. Murmur’s main transcriber covers 25 European languages, and \(languageName(prompt.language)) isn’t one of them.")
                .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $option) {
                VStack(alignment: .leading) {
                    Text("Use Apple’s on-device transcriber").fontWeight(.semibold)
                    Text(prompt.appleSupports ? "Supports \(languageName(prompt.language)). Speakers and timing still work."
                                              : "Doesn’t support \(languageName(prompt.language)) either.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .tag(Option.apple)
                .disabled(!prompt.appleSupports)
                VStack(alignment: .leading) {
                    HStack {
                        Text("It’s another language").fontWeight(.semibold)
                        Picker("", selection: $other) {
                            ForEach(LanguageMenu.common, id: \.self) { Text(languageName($0)).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                    Text("For example when the recording starts with music or a different speaker.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .tag(Option.other)
                VStack(alignment: .leading) {
                    Text("Transcribe with Murmur’s transcriber anyway").fontWeight(.semibold)
                    Text("Expect wrong words if Ear is right.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .tag(Option.voz)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel") { answer(.cancel) }.keyboardShortcut(.cancelAction)
                Button("Continue") {
                    switch option {
                    case .apple: answer(.apple(prompt.language))
                    case .other: answer(.voz(other))
                    case .voz: answer(.voz(prompt.language))
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
