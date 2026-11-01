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
    /// Search through every transcript: a button at the top opens a field at the bottom.
    @State private var searching = false
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @FocusState private var searchFocused: Bool

    var body: some View {
        // The project list stays underneath the results: on iPhone the split view only opens a project
        // while the list bound to its selection is on screen.
        ZStack {
            projects
                .opacity(showsResults ? 0 : 1)
                .accessibilityHidden(showsResults)
            if showsResults {
                SearchResultsView(query: query, hits: hits) { hit in
                    OpenProjects.shared.seek(hit.url, to: hit.start)
                    selection = hit.url
                }
            }
        }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            hits = LibrarySearch.hits(query, in: library.items)
        }
        // The bottom: the record button, or the search field while searching.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if searching { searchBar } else { recordBar }
        }
        .animation(.snappy, value: searching)
        .navigationTitle("Murmur")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") { settings = true }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Search", systemImage: "magnifyingglass") {
                    searching = true
                    searchFocused = true
                }
                .disabled(library.items.isEmpty)
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
            // The red button means record: it starts at once, as in Voice Memos.
            RecordView(autoStart: true) { url in selection = url }
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .alert("From Voice Memos", isPresented: $voiceMemos) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("In Voice Memos, open a recording, tap Share and choose Murmur. It opens here and is transcribed on this device.")
        }
        #if DEBUG
        // `-show settings|record|import` opens that screen at launch, `-search <words>` searches, for screenshots.
        .onAppear {
            if let words = UserDefaults.standard.string(forKey: "search"), !words.isEmpty {
                searching = true
                query = words
            }
            switch UserDefaults.standard.string(forKey: "show") {
            case "settings": settings = true
            case "record": recording = true
            case "import": importing = true
            default: break
            }
        }
        #endif
    }

    private var showsResults: Bool { searching && !query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var projects: some View {
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
                    Label { Text("No Recordings") } icon: { VoicesMark().frame(width: 52, height: 36) }
                } description: {
                    Text("Tap the red button to record, or open an audio or video file. Everything stays on this device.")
                } actions: {
                    Button { importing = true } label: {
                        Label("Open a File", systemImage: "doc").font(.headline).padding(.horizontal, 8).frame(minHeight: 40)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
    }

    /// Voice Memos' layout: the big red button centred on a bar along the bottom.
    private var recordBar: some View {
        RecordButton { recording = true }
            .frame(maxWidth: .infinity)
            .padding(.top, 12).padding(.bottom, 4)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search all transcripts", text: $query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14).frame(height: 46)
            .glassEffect(in: .capsule)
            // Closes search, as in Voice Memos; it clears the text too, so the field needs no clear button.
            Button {
                query = ""
                searching = false
                searchFocused = false
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 46, height: 46)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close Search")
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
