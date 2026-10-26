import MurmurCore
import Sparkle
import SwiftUI

struct SettingsView: View {
    let updater: SPUStandardUpdaterController?

    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ModelSettings().tabItem { Label("Models", systemImage: "cpu") }
            RecordingSettings().tabItem { Label("Recording", systemImage: "record.circle") }
            AboutSettings(updater: updater).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 560)
    }
}

struct GeneralSettings: View {
    @AppStorage(AppSettings.copyFormat) private var copyFormat = TextFormat.timestamps.rawValue
    @AppStorage(AppSettings.hideFillersInExport) private var hideFillers = true
    @AppStorage(AppSettings.enhanceNewProjects) private var enhance = false
    @AppStorage(AppSettings.detectFillers) private var detectFillers = true
    @AppStorage(AppSettings.autoTitle) private var autoTitle = true
    @AppStorage(AppSettings.speakerScheme) private var scheme = SpeakerScheme.vivid.rawValue

    var body: some View {
        Form {
            Picker("Copy as", selection: $copyFormat) {
                ForEach(TextFormat.copyFormats) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Hide fillers (um, uh) when copying and exporting", isOn: $hideFillers)
            Picker("Speaker colors", selection: $scheme) {
                ForEach(SpeakerScheme.allCases) { s in
                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            ForEach(0..<5, id: \.self) { RoundedRectangle(cornerRadius: 3).fill(s.color($0)).frame(width: 14, height: 14) }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(s.title)
                            Text(s.note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(s.rawValue)
                }
            }
            .pickerStyle(.radioGroup)
            Section("New projects") {
                Toggle("Find fillers with Uhm", isOn: $detectFillers)
                Toggle("Enhance audio with Clear", isOn: $enhance)
                Toggle("Name projects and write a summary", isOn: $autoTitle)
                    .disabled(!Summarizer.isAvailable)
                if !Summarizer.isAvailable {
                    Text("Needs Apple Intelligence to be turned on in System Settings.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Projects folder") {
                HStack {
                    Text(ProjectFile.defaultFolder.path).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Show in Finder") { NSWorkspace.shared.open(ProjectFile.defaultFolder) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ModelSettings: View {
    @Environment(ModelManager.self) private var models

    var body: some View {
        Form {
            Section {
                ForEach(ModelKind.allCases) { kind in
                    HStack {
                        ModelRow(kind: kind, state: models.state(kind))
                        if models.state(kind).isReady {
                            Text(ByteCountFormatter.string(fromByteCount: models.diskSize(kind), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Remove") { models.remove(kind) }.disabled(kind.isRequired && models.isDownloading)
                        } else if !models.isBusy(kind) {
                            Button("Download") { Task { await models.download([kind]) } }
                        }
                    }
                }
            } footer: {
                Text("Models from Desert Ant Labs run on the Neural Engine and never send audio anywhere. Loading a model reports an anonymous usage count to Desert Ant Labs for licensing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { models.refresh() }
    }
}

struct RecordingSettings: View {
    @AppStorage(AppSettings.systemAudioSource) private var source = ""
    @AppStorage(AppSettings.markHotKey) private var hotKey = true
    @State private var apps: [AudioProcess] = []

    var body: some View {
        Form {
            Picker("System audio", selection: $source) {
                Text("All apps").tag("")
                ForEach(apps) { Text($0.name).tag($0.bundleID) }
                if !source.isEmpty && !apps.contains(where: { $0.bundleID == source }) {
                    Text(source).tag(source)
                }
            }
            Text("Recording only your call app keeps notification sounds and music out of the “Others” track.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("⌥⌘M marks a moment while recording, from any app", isOn: $hotKey)
                .onChange(of: hotKey) { _, _ in HotKey.shared.install() }
            Text("Headphones keep the two tracks clean. Without them Murmur removes the other side’s voices from your microphone track.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { apps = SystemAudioTap.audioProcesses() }
    }
}

struct AboutSettings: View {
    let updater: SPUStandardUpdaterController?

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Murmur").font(.title2.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""))")
                .foregroundStyle(.secondary)
            Button("Check for Updates…") { updater?.checkForUpdates(nil) }
                .disabled(updater == nil)
            if updater == nil {
                Text("Updates turn on once a release is signed for Sparkle.").font(.caption).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 6)
            Text("Speech recognition: Voz, based on NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0). Speakers, language, timing, fillers and enhancement: Who, Ear, Align, Uhm and Clear by Desert Ant Labs, used under the Desert Ant Labs Source-Available License. Titles and summaries: Apple Intelligence. Updates: Sparkle.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .padding()
    }
}
