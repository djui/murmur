import MurmurCore
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Binding var selection: URL?
    @State private var library = Library.shared
    @State private var importing = false
    @State private var recording = false
    @State private var settings = false
    @State private var busy = false
    @State private var pendingDelete: Library.Item?
    @State private var voiceMemos = false

    var body: some View {
        List(selection: $selection) {
            ForEach(library.items) { item in
                NavigationLink(value: item.url) { row(item) }
                    // Not a destructive role: that removes the row at once, before the person confirms.
                    .swipeActions {
                        Button("Delete", systemImage: "trash") { pendingDelete = item }.tint(.red)
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
                    }
                    // On the row, so the confirmation points at the project it deletes.
                    .confirmationDialog("Delete this project?", isPresented: Binding(get: { pendingDelete?.url == item.url },
                                                                                   set: { if !$0 { pendingDelete = nil } }),
                                        titleVisibility: .visible) {
                        Button("Delete Project", role: .destructive) {
                            if selection == item.url { selection = nil }
                            library.delete(item.url)
                        }
                    } message: {
                        Text("“\(item.title)” and Murmur’s copy of its audio are deleted. This can’t be undone.")
                    }
            }
        }
        .overlay {
            if library.items.isEmpty {
                ContentUnavailableView {
                    Label { Text("No Projects") } icon: { VoicesMark().frame(width: 52, height: 36) }
                } description: {
                    Text("Transcripts with speakers, made on this device. Nothing you open is uploaded.")
                } actions: {
                    Button("Open File…") { importing = true }.buttonStyle(.borderedProminent)
                    Button("Record") { recording = true }
                }
            }
        }
        .navigationTitle("Murmur")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { settings = true }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu("New", systemImage: "plus") {
                    Button("Open File…", systemImage: "doc") { importing = true }
                    Button("Record", systemImage: "mic") { recording = true }
                    Button("From Voice Memos…", systemImage: "waveform") { voiceMemos = true }
                }
            }
        }
        .overlay { if busy { ProgressView().controlSize(.large) } }
        .refreshable { library.reload() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audiovisualContent]) { result in
            guard case .success(let url) = result else { return }
            busy = true
            Task {
                do { selection = try await library.importMedia(url) } catch { library.error = error.localizedDescription }
                busy = false
            }
        }
        .sheet(isPresented: $recording) {
            RecordView { url in selection = url }
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .alert("From Voice Memos", isPresented: $voiceMemos) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In Voice Memos, open a recording, tap Share and choose Murmur. It opens here and is transcribed on this device.")
        }
        #if DEBUG
        // `-show settings|record|import` opens that screen at launch, for screenshots.
        .onAppear {
            switch UserDefaults.standard.string(forKey: "show") {
            case "settings": settings = true
            case "record": recording = true
            case "import": importing = true
            default: break
            }
        }
        #endif
    }

    private func row(_ item: Library.Item) -> some View {
        let scheme = SpeakerScheme.current
        return HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title).font(.headline).lineLimit(2)
            HStack(spacing: 6) {
                Text(item.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                Text("·")
                Text(Timecode.short(item.duration)).monospacedDigit()
                switch item.status {
                case .ready where item.speakers > 0:
                    Text("·")
                    Text("\(item.speakers) \(item.speakers == 1 ? "speaker" : "speakers")")
                case .processing:
                    Text("·")
                    Text(library.asking.contains(item.url) ? "Waiting for your answer"
                         : library.transcribing.contains(item.url) ? "Transcribing…" : "Not finished")
                case .new:
                    Text("·")
                    Text("Not transcribed yet")
                case .failed:
                    Text("·")
                    Text("Failed").foregroundStyle(.red)
                default: EmptyView()
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            // Who did the talking, at a glance; the bar's label carries it for VoiceOver.
            if item.status == .ready, item.talk.count > 1 {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(item.talk, id: \.index) { t in
                            Capsule().fill(scheme.color(t.index)).frame(width: max(4, (g.size.width - CGFloat(item.talk.count) * 2) * t.share))
                        }
                    }
                }
                .frame(height: 5)
                .padding(.top, 4)
                .accessibilityElement()
                .accessibilityLabel(item.talk.map { "\($0.name) \(Int(($0.share * 100).rounded())) percent" }.joined(separator: ", "))
            }
        }
        }
        .padding(.vertical, 2)
    }
}
