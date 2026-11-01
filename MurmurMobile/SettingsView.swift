import MurmurCore
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var models = ModelManager.shared
    @AppStorage(AppSettings.speakerScheme) private var scheme = SpeakerScheme.vivid.rawValue
    @AppStorage(AppSettings.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(AppSettings.copyFormat) private var copyFormat = TextFormat.timestamps.rawValue
    @AppStorage(AppSettings.redactionStyle) private var redactionStyle = RedactionStyle.labels.rawValue
    @AppStorage(AppSettings.hideFillersInExport) private var hideFillers = true
    @AppStorage(AppSettings.detectFillers) private var detectFillers = true
    @AppStorage(AppSettings.enhanceNewProjects) private var enhance = false
    @AppStorage(AppSettings.autoTitle) private var autoTitle = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Look") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker(selection: $scheme) {
                        ForEach(SpeakerScheme.allCases) { s in
                            HStack {
                                Text(s.title)
                                Spacer()
                                HStack(spacing: 3) {
                                    ForEach(0..<5, id: \.self) { RoundedRectangle(cornerRadius: 3).fill(s.color($0)).frame(width: 14, height: 14) }
                                }
                            }
                            .tag(s.rawValue)
                        }
                    } label: {
                        Text("Speaker colors")
                    }
                    .pickerStyle(.navigationLink)
                }
                Section {
                    Toggle("Find um and uh", isOn: $detectFillers)
                    Toggle("Enhance audio of new projects", isOn: $enhance)
                    Toggle("Name projects and write a summary", isOn: $autoTitle)
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Names and summaries use Apple Intelligence where this device has it.")
                }
                Section("Copy and Share") {
                    Picker("Copy as", selection: $copyFormat) {
                        ForEach(TextFormat.copyFormats) { Text($0.title).tag($0.rawValue) }
                    }
                    Picker("Hidden details read", selection: $redactionStyle) {
                        ForEach(RedactionStyle.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    Toggle("Leave out um and uh", isOn: $hideFillers)
                }
                Section {
                    ForEach(ModelKind.allCases) { kind in ModelRow(kind: kind) }
                } header: {
                    Text("Models")
                } footer: {
                    Text("Downloaded from Hugging Face and kept on this device. Voz, Who, Ear and Align are needed to transcribe; the others download when first used.")
                }
                Section {
                    Text("Speech recognition by Voz (NVIDIA Parakeet TDT 0.6B v3, CC BY 4.0) and the other models by Desert Ant Labs. Nothing you open or record leaves this device.")
                        .font(.footnote).foregroundStyle(.secondary)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct ModelRow: View {
    let kind: ModelKind
    @State private var models = ModelManager.shared
    @State private var size: Int64 = 0

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(kind.title)").font(.body)
                Text("\(kind.engine) · \(kind.detail)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            switch models.state(kind) {
            case .ready, .preparing:
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            case .downloading(let f):
                ProgressView(value: f).frame(width: 60)
            case .missing, .failed:
                Button("Get") { Task { await models.download([kind]) } }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
        .swipeActions {
            if models.state(kind).isReady {
                Button("Remove", role: .destructive) { models.remove(kind) }
            }
        }
        .task(id: models.state(kind)) { size = models.diskSize(kind) }
    }
}
