import AppKit
import MurmurCore
import SwiftUI

struct LibraryItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let title: String
    let file: String
    let date: Date
    let duration: Double
    let speakers: Int
    let language: String?
    let isRecording: Bool
    let mediaMissing: Bool
    let status: Project.Status
    let text: String

    static func load(paths: [String]) async -> [LibraryItem] {
        await Task.detached(priority: .userInitiated) {
            var urls = Set(paths.map { URL(fileURLWithPath: $0) })
            let folder = ProjectFile.defaultFolder
            if let found = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                urls.formUnion(found.filter { $0.pathExtension == "murmur" })
            }
            return urls.compactMap { url -> LibraryItem? in
                guard let p = try? ProjectFile.read(at: url) else { return nil }
                return LibraryItem(
                    url: url, title: p.displayTitle,
                    file: p.media.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "",
                    date: p.createdAt, duration: p.duration, speakers: p.speakers.count, language: p.language,
                    isRecording: p.media?.isRecording ?? false,
                    mediaMissing: p.media != nil && p.media?.resolvedURL() == nil,
                    status: p.status,
                    text: Merge.join(p.words.prefix(4000)).lowercased())
            }
            .sorted { $0.date > $1.date }
        }.value
    }
}

struct LibraryView: View {
    @Environment(AppState.self) private var app
    @Environment(ModelManager.self) private var models
    @Environment(\.openDocument) private var openDocument
    @AppStorage(AppSettings.speakerScheme) private var scheme = SpeakerScheme.vivid.rawValue

    enum Filter: String, CaseIterable, Identifiable {
        case recent = "Recent", recordings = "Recordings", imported = "Imported files", missing = "Media missing"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .recent: "clock"
            case .recordings: "record.circle"
            case .imported: "doc.badge.plus"
            case .missing: "exclamationmark.triangle"
            }
        }
    }

    @State private var filter: Filter? = .recent
    @State private var items: [LibraryItem] = []
    @State private var query = ""
    @State private var selection: Set<URL> = []
    @State private var showOnboarding = false
    @State private var dropTargeted = false

    var shown: [LibraryItem] {
        let q = query.lowercased()
        return items.filter { item in
            switch filter ?? .recent {
            case .recent: true
            case .recordings: item.isRecording
            case .imported: !item.isRecording
            case .missing: item.mediaMissing
            }
        }
        .filter { q.isEmpty || $0.title.lowercased().contains(q) || $0.text.contains(q) }
    }

    func count(_ f: Filter) -> Int {
        switch f {
        case .recent: items.count
        case .recordings: items.filter(\.isRecording).count
        case .imported: items.filter { !$0.isRecording }.count
        case .missing: items.filter(\.mediaMissing).count
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $filter) {
                Section("Library") {
                    ForEach(Filter.allCases) { f in
                        Label(f.rawValue, systemImage: f.icon)
                            .badge(count(f))
                            .tag(f)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
            .safeAreaInset(edge: .bottom) {
                Text("Projects are .murmur files you can keep anywhere. This list remembers where they are.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(12)
            }
        } detail: {
            detail
        }
        .navigationTitle(filter?.rawValue ?? "Library")
        .searchable(text: $query, placement: .toolbar, prompt: "Search titles and transcripts")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { app.presentImportPanel() } label: { Label("Import File…", systemImage: "square.and.arrow.down") }
                Button { app.recorder.start() } label: { Label("New Recording", systemImage: "record.circle") }
                    .help("Record the microphone and system audio, with a live transcript")
            }
        }
        .task(id: app.libraryVersion) { items = await LibraryItem.load(paths: app.knownProjects) }
        .onAppear {
            if !models.requiredReady && !AppSettings.bool(AppSettings.skippedOnboarding) { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding) { FirstLaunchView().environment(models) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            app.libraryVersion += 1
        }
    }

    @ViewBuilder var detail: some View {
        VStack(spacing: 0) {
            if !models.requiredReady {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("Murmur needs its speech models (≈ 515 MB) before it can transcribe.")
                    Spacer()
                    Button("Download…") { showOnboarding = true }
                }
                .font(.system(size: 12))
                .padding(10)
                .background(Color.accentColor.opacity(0.08))
            } else if models.isPreparing {
                HStack(spacing: 10) {
                    ProgressView(value: Double(models.preparedCount), total: Double(max(1, models.preparingTotal)))
                        .frame(width: 80)
                    Text(models.isFirstPreparation
                         ? "Getting the speech models ready for this Mac's Neural Engine (\(models.preparedCount) of \(models.preparingTotal)). Files you open now wait for this."
                         : "Loading the speech models (\(models.preparedCount) of \(models.preparingTotal)).")
                    Spacer()
                }
                .font(.system(size: 12))
                .padding(10)
                .background(Color.accentColor.opacity(0.08))
            }
            if shown.isEmpty {
                ContentUnavailableView {
                    Label(items.isEmpty ? "No projects yet" : "Nothing here", systemImage: "waveform")
                } description: {
                    Text(items.isEmpty ? "Drop an audio or video file here, or start a recording." : "No projects match.")
                } actions: {
                    HStack {
                        Button("Import File…") { app.presentImportPanel() }
                        Button("New Recording") { app.recorder.start() }.buttonStyle(.borderedProminent)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                table
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(8)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let media = urls.filter { $0.pathExtension != "murmur" }
            media.forEach(app.importMedia)
            urls.filter { $0.pathExtension == "murmur" }.forEach { open($0) }
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
    }

    var table: some View {
        Table(shown, selection: $selection) {
            TableColumn("Title") { item in
                HStack(spacing: 10) {
                    Text(item.isRecording ? "REC" : URL(fileURLWithPath: item.file).pathExtension.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.isRecording ? Palette.recording : .secondary)
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 8).fill(item.isRecording ? Palette.recording.opacity(0.1) : Palette.well))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(item.mediaMissing ? "Media missing — open to locate the file" : item.status == .failed ? "Not transcribed" : item.file)
                            .font(.system(size: 11, weight: item.mediaMissing ? .semibold : .regular))
                            .foregroundStyle(item.mediaMissing ? .orange : .secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
            }
            TableColumn("Date") { Text($0.date, format: .dateTime.day().month(.abbreviated).hour().minute()).foregroundStyle(.secondary) }
                .width(min: 110, ideal: 130)
            TableColumn("Length") { Text(Timecode.short($0.duration)).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                .width(70)
            TableColumn("Speakers") { item in
                HStack(spacing: 3) {
                    ForEach(0..<min(item.speakers, 5), id: \.self) { Circle().fill(SpeakerScheme(rawValue: scheme)?.color($0) ?? Palette.speaker($0)).frame(width: 8, height: 8) }
                    Text("\(item.speakers)").foregroundStyle(.secondary).padding(.leading, 3)
                }
            }
            .width(100)
            TableColumn("Language") { Text(languageName($0.language)).foregroundStyle(.secondary) }.width(90)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            Button("Open") { urls.forEach(open) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
            Divider()
            Button("Remove from Library") { urls.forEach(app.forget) }
        } primaryAction: { urls in
            urls.forEach(open)
        }
    }

    func open(_ url: URL) {
        app.remember(url)
        Task { try? await openDocument(at: url) }
    }
}
