import AVFoundation
import MurmurCore
import SwiftUI
import UniformTypeIdentifiers

/// Opens a `.murmur` package and keeps it saved while the person works on it.
struct ProjectScreen: View {
    let url: URL
    @State private var session: ProjectSession?
    @State private var error: String?

    var body: some View {
        Group {
            if let session {
                ProjectView(session: session, url: url)
            } else if let error {
                ContentUnavailableView("Couldn’t Open the Project", systemImage: "exclamationmark.triangle", description: Text(error))
            } else {
                ProgressView()
            }
        }
        .task {
            do { session = try OpenProjects.shared.session(for: url) } catch { self.error = error.localizedDescription }
        }
    }
}

struct ProjectView: View {
    @Bindable var session: ProjectSession
    let url: URL
    @Environment(\.undoManager) private var undoManager
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var models = ModelManager.shared
    @State private var sheet: Sheet?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var locating = false
    /// Paragraphs picked for a mark, by id; nil when not picking.
    @State private var picking: Set<Int>?
    @State private var searching = false
    @State private var shared: ExportView.SharedFiles?

    enum Sheet: String, Identifiable {
        case export, speakers, marks, language, details, people
        var id: String { rawValue }
    }

    private var project: Project { session.project }
    private var showsVideo: Bool { project.media?.hasVideo == true && project.settings.showVideo && session.mediaURL != nil }

    var body: some View {
        VStack(spacing: 0) {
            if sizeClass == .regular, showsVideo {
                PlayerLayerView(player: session.player.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxHeight: 240)
                    .background(.black)
            }
            if sizeClass == .regular {
                // iPad: the score across the top, the transcript beside an inspector, as on the Mac.
                TimelineStrip(session: session)
                    .frame(height: 150 + CGFloat(min(project.speakers.count, 6)) * 13)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                PlayerBar(session: session)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                Divider().opacity(0.4)
                HStack(spacing: 0) {
                    content
                    if !project.words.isEmpty {
                        Divider()
                        InspectorView(session: session, sheet: $sheet).frame(width: 340)
                    }
                }
            } else {
                ScoreHeader(session: session, showVideo: showsVideo)
                content
            }
        }
        // iPhone: playback floats at the bottom, in thumb reach; the transcript scrolls clear of it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let picked = picking {
                PickBar(session: session, picked: picked) { picking = nil }
            } else if sizeClass != .regular {
                PlaybackBar(session: session)
            }
        }
        .navigationTitle(project.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .overlay(alignment: .top) {
            // At the top, clear of the playback dock.
            if let toast = session.toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.toast)
        .sheet(item: $sheet) { sheetContent($0) }
        .sheet(item: $shared) { ShareSheet(items: $0.urls) }
        .alert("Rename Project", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty { session.setTitle(newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(languageTitle, isPresented: Binding(get: { session.languagePrompt != nil }, set: { _ in }), titleVisibility: .visible) {
            if let prompt = session.languagePrompt {
                if prompt.appleSupports {
                    Button("Use Apple’s Transcriber") { session.answerLanguage(.apple(prompt.language)) }
                }
                Button("Transcribe with Voz Anyway") { session.answerLanguage(.voz(prompt.language)) }
                Button("Cancel", role: .cancel) { session.answerLanguage(.cancel) }
            }
        } message: {
            Text("Murmur’s transcriber doesn’t know this language. Apple’s on-device transcriber may, without speaker-quality word timing.")
        }
        .fileImporter(isPresented: $locating, allowedContentTypes: [.audiovisualContent]) { result in
            guard case .success(let source) = result else { return }
            Task {
                // Copy it in, as with any import, so it stays readable.
                let scoped = source.startAccessingSecurityScopedResource()
                defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let target = Library.mediaFolder.appendingPathComponent(source.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                guard (try? FileManager.default.copyItem(at: source, to: target)) != nil else { return }
                session.relocateMedia(to: target)
            }
        }
        .onAppear {
            #if DEBUG
            // `-sheet export|speakers|marks|language|details`, `-pick 1,2`: open that state, for screenshots.
            if let name = UserDefaults.standard.string(forKey: "sheet") { sheet = Sheet(rawValue: name) }
            if let ids = UserDefaults.standard.string(forKey: "pick") {
                picking = Set(ids.split(separator: ",").compactMap { Int($0) }.compactMap { session.paragraphs.indices.contains($0) ? session.paragraphs[$0].id : nil })
            }
            #endif
            session.undoManager = undoManager
            OpenProjects.shared.appeared(url)
            startIfReady()
        }
        .onChange(of: models.requiredReady) { startIfReady() }
        // Saving and background progress live in OpenProjects, so they carry on when this screen closes.
        .onChange(of: scenePhase) { _, phase in if phase != .active { OpenProjects.shared.saveAll() } }
        .onDisappear { OpenProjects.shared.disappeared(url) }
    }

    @ViewBuilder
    private func sheetContent(_ which: Sheet) -> some View {
        switch which {
        case .export: ExportView(session: session)
        case .speakers: SpeakersView(session: session)
        case .marks: MarksView(session: session)
        case .language: LanguageView(session: session)
        case .details: DetailsView(session: session)
        case .people:
            NavigationStack {
                InspectorView(session: session, sheet: $sheet)
                    .navigationTitle("Speakers & Marks")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sheet = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var languageTitle: String {
        guard let prompt = session.languagePrompt else { return "" }
        let name = Locale.current.localizedString(forLanguageCode: prompt.language) ?? prompt.language
        return "This sounds like \(name)"
    }

    @ViewBuilder
    private var content: some View {
        if session.isProcessing && project.words.isEmpty {
            ProcessingView(session: session)
        } else if !models.requiredReady && project.words.isEmpty {
            ContentUnavailableView {
                Label("Models Needed", systemImage: "arrow.down.circle")
            } description: {
                Text("Murmur transcribes on this device. Download its models once to start.")
            } actions: {
                if models.isDownloading {
                    ProgressView(value: models.requiredFraction).frame(width: 200)
                } else {
                    Button("Download Models") { Task { await models.downloadRequired() } }.buttonStyle(.borderedProminent)
                }
            }
        } else if session.mediaMissing {
            ContentUnavailableView {
                Label("Audio Missing", systemImage: "questionmark.folder")
            } description: {
                Text("Murmur can’t find the file this project was made from.")
            } actions: {
                Button("Locate File…") { locating = true }.buttonStyle(.borderedProminent)
            }
        } else if project.status == .failed && project.words.isEmpty {
            ContentUnavailableView {
                Label("Transcription Failed", systemImage: "exclamationmark.triangle")
            } description: {
                Text(project.failure ?? "Something went wrong.")
            } actions: {
                Button("Try Again") { session.retranscribe() }.buttonStyle(.borderedProminent)
            }
        } else {
            TranscriptList(session: session, picking: $picking, searching: $searching)
                .overlay(alignment: .top) {
                    if session.isProcessing { ProcessingBanner(session: session) }
                    else if let warning = project.languageWarning { WarningBanner(text: warning) { sheet = .language } }
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Search", systemImage: "magnifyingglass") { searching.toggle() }
                .disabled(project.words.isEmpty)
            // The common formats go straight to the share sheet; the rest are under More Options.
            Menu("Share", systemImage: "square.and.arrow.up") {
                Button("Text", systemImage: "doc.plaintext") { share(.plain) }
                Button("Text with Timestamps", systemImage: "clock") { share(.timestamps) }
                Button("Subtitles (SRT)", systemImage: "captions.bubble") { share(.srt) }
                Button("Audio", systemImage: "waveform") { shareAudio() }
                    .disabled(session.playbackURL == nil)
                Divider()
                Button("More Options…", systemImage: "slider.horizontal.3") { sheet = .export }
            }
            .disabled(project.words.isEmpty)
            Menu("More", systemImage: "ellipsis") {
                Section {
                    if sizeClass != .regular {
                        Button("Speakers & Marks", systemImage: "person.2") { sheet = .people }
                    }
                    Button("Mark Paragraphs…", systemImage: "checklist") { picking = [] }
                        .disabled(project.words.isEmpty)
                }
                Section {
                    Toggle(isOn: Binding(get: { session.isRedacting }, set: { session.setRedact($0) })) {
                        Label("Hide Personal Details", systemImage: "eye.slash")
                    }
                    .disabled(project.words.isEmpty || session.isFindingDetails)
                    Toggle(isOn: Binding(get: { project.settings.enhance }, set: { session.setEnhance($0) })) {
                        Label("Enhance Audio", systemImage: "wand.and.stars")
                    }
                    .disabled(session.isProcessing)
                    if project.media?.hasVideo == true {
                        Toggle(isOn: Binding(get: { project.settings.showVideo }, set: { _ in session.toggleVideo() })) {
                            Label("Show Video", systemImage: "film")
                        }
                    }
                }
                Section {
                    Button("Copy Transcript", systemImage: "doc.on.doc") { session.copyAll() }
                        .disabled(project.words.isEmpty)
                    Button("Rename Project…", systemImage: "pencil") { newTitle = project.displayTitle; renaming = true }
                    Button("Transcribe Again…", systemImage: "arrow.clockwise") { sheet = .language }
                        .disabled(session.isProcessing || !models.requiredReady)
                }
                Section {
                    Button("Undo", systemImage: "arrow.uturn.backward") { undoManager?.undo() }
                        .disabled(!(undoManager?.canUndo ?? false))
                    Button("Redo", systemImage: "arrow.uturn.forward") { undoManager?.redo() }
                        .disabled(!(undoManager?.canRedo ?? false))
                }
            }
        }
    }

    /// The whole transcript in one format, handed to the share sheet.
    private func share(_ format: TextFormat) {
        var p = project
        var options = AppSettings.renderOptions
        if !session.isRedacting { p.redactions = nil; options.redactionStyle = .labels }
        let url = Self.shareFolder().appendingPathComponent(Self.fileName(project.displayTitle)).appendingPathExtension(format.fileExtension)
        do {
            try Renderer.render(p, sections: nil, format: format, options: options).write(to: url, atomically: true, encoding: .utf8)
            shared = ExportView.SharedFiles(urls: [url])
        } catch {
            session.flash("Couldn’t prepare the file: \(error.localizedDescription)")
        }
    }

    /// The whole recording as .m4a, bleeped where details are hidden.
    private func shareAudio() {
        guard let source = session.playbackURL else { return }
        let url = Self.shareFolder().appendingPathComponent(Self.fileName(project.displayTitle)).appendingPathExtension("m4a")
        let clip = ClipExporter.Clip(name: project.displayTitle, start: 0, end: project.duration)
        let bleeps = session.hiddenSpans.map { $0.start...$0.end }
        session.flash("Preparing audio…")
        Task {
            do {
                let files = try await ClipExporter.export(source: source, clips: [clip], video: false, joined: true, destination: url, bleeps: bleeps)
                shared = ExportView.SharedFiles(urls: files)
            } catch {
                session.flash("Couldn’t prepare the audio: \(error.localizedDescription)")
            }
        }
    }

    private static func shareFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileName(_ title: String) -> String {
        title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
    }

    private func startIfReady() {
        guard models.requiredReady, !session.mediaMissing else { return }
        session.processIfNeeded()
    }

}

/// The video picture, without AVKit's own controls (the player bar has them).
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    final class LayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: LayerView, context: Context) { view.playerLayer.player = player }
}

struct WarningBanner: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(text, systemImage: "exclamationmark.bubble")
                .font(.footnote)
                .multilineTextAlignment(.leading)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }
}
