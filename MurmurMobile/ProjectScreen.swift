import AVFoundation
import Combine
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
            do {
                let wrapper = try FileWrapper(url: url)
                let contents = try ProjectFile.read(wrapper)
                let document = ProjectDocument()
                document.project = contents.project
                document.peaks = contents.peaks
                session = ProjectSession(document: document, fileURL: url)
            } catch {
                self.error = error.localizedDescription
            }
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

    enum Sheet: String, Identifiable {
        case export, speakers, marks, language, details
        var id: String { rawValue }
    }

    private var project: Project { session.project }

    var body: some View {
        VStack(spacing: 0) {
            if project.media?.hasVideo == true, project.settings.showVideo, session.mediaURL != nil {
                PlayerLayerView(player: session.player.player)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxHeight: 240)
                    .background(.black)
            }
            TimelineStrip(session: session)
                // A taller score where there is room (iPad).
                .frame(height: (sizeClass == .regular ? 150 : 96) + CGFloat(min(project.speakers.count, 6)) * 13)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            PlayerBar(session: session)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Divider().opacity(0.4)
            content
        }
        .navigationTitle(project.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) {
            if let toast = session.toast {
                Text(toast)
                    .font(.subheadline)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(in: .capsule)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: session.toast)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .export: ExportView(session: session)
            case .speakers: SpeakersView(session: session)
            case .marks: MarksView(session: session)
            case .language: LanguageView(session: session)
            case .details: DetailsView(session: session)
            }
        }
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
            session.undoManager = undoManager
            startIfReady()
        }
        .onChange(of: models.requiredReady) { startIfReady() }
        .onChange(of: session.isProcessing) { _, processing in
            UIApplication.shared.isIdleTimerDisabled = processing
            Library.shared.transcribing = processing ? url : nil
            if processing { ContinuedProcessing.begin(project: project.displayTitle) }
            else { ContinuedProcessing.end(success: project.status == .ready) }
        }
        .onChange(of: session.steps) { _, steps in
            guard session.isProcessing else { return }
            ContinuedProcessing.update(fraction: Self.fraction(steps), detail: steps.first { $0.state == .running }?.title ?? "Transcribing")
        }
        .onReceive(session.document.objectWillChange.debounce(for: .seconds(1), scheduler: RunLoop.main)) { _ in save() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
        .onDisappear {
            save()
            session.player.pause()
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
            TranscriptList(session: session)
                .overlay(alignment: .top) {
                    if session.isProcessing { ProcessingBanner(session: session) }
                    else if let warning = project.languageWarning { WarningBanner(text: warning) { sheet = .language } }
                }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Share", systemImage: "square.and.arrow.up") { sheet = .export }
                .disabled(project.words.isEmpty)
            Menu("More", systemImage: "ellipsis") {
                Section {
                    Button("Speakers", systemImage: "person.2") { sheet = .speakers }
                    Button("Marks", systemImage: "bookmark") { sheet = .marks }
                    if project.summary != nil || project.language != nil {
                        Button("Details", systemImage: "info.circle") { sheet = .details }
                    }
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

    private func startIfReady() {
        guard models.requiredReady, !session.mediaMissing else { return }
        session.processIfNeeded()
    }

    private func save() {
        do {
            try ProjectFile.write(session.document.project, peaks: session.document.peaks, to: url)
            Library.shared.reload()
        } catch {
            session.flash("Couldn’t save: \(error.localizedDescription)")
        }
    }

    static func fraction(_ steps: [PipelineStep]) -> Double {
        guard !steps.isEmpty else { return 0 }
        let done = steps.reduce(0.0) { sum, step in
            switch step.state {
            case .done, .skipped: sum + 1
            case .running: sum + (step.fraction ?? 0)
            default: sum
            }
        }
        return done / Double(steps.count)
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
