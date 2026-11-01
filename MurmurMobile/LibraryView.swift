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

    var body: some View {
        List(selection: $selection) {
            ForEach(library.items) { item in
                NavigationLink(value: item.url) { row(item) }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = item }
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
                Button("Record", systemImage: "mic") { recording = true }
                Button("Open File", systemImage: "plus") { importing = true }
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
        .confirmationDialog("Delete “\(pendingDelete?.title ?? "")”?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) {
                guard let item = pendingDelete else { return }
                if selection == item.url { selection = nil }
                library.delete(item.url)
            }
        } message: {
            Text("The transcript and Murmur’s copy of the audio are deleted. This can’t be undone.")
        }
    }

    private func row(_ item: Library.Item) -> some View {
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
                    Text(item.url == library.transcribing ? "Transcribing…" : "Not finished")
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
        }
        .padding(.vertical, 2)
    }
}
