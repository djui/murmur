import MurmurCore
import SwiftUI

/// The project window: timeline on top, transcript and sidebar below.
struct MainView: View {
    @ObservedObject var document: ProjectDocument
    let fileURL: URL?
    @State private var session: ProjectSession
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var app
    @AppStorage(AppSettings.speakerScheme) private var scheme = SpeakerScheme.vivid.rawValue

    init(document: ProjectDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
        _session = State(initialValue: ProjectSession(document: document, fileURL: fileURL))
    }

    var body: some View {
        content
            .id(scheme)
            .frame(minWidth: 900, minHeight: 620)
            .navigationTitle(session.project.displayTitle)
            .navigationSubtitle(subtitle)
            .toolbar { toolbar }
            .sheet(item: $session.languagePrompt) { prompt in
                LanguagePromptView(prompt: prompt) { session.answerLanguage($0) }
            }
            .sheet(isPresented: $session.showExport) { ExportSheet(session: session) }
            .overlay(alignment: .bottom) {
                if let toast = session.toast { Toast(message: toast) }
            }
            .animation(.easeOut(duration: 0.2), value: session.toast)
            .focusedSceneValue(\.session, session)
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in handleKey(press) }
            .task {
                session.undoManager = undoManager
                if let fileURL { app.remember(fileURL) }
                session.processIfNeeded()
            }
            .onChange(of: undoManager) { _, u in session.undoManager = u }
    }

    @ViewBuilder var content: some View {
        if session.isProcessing && session.project.words.isEmpty {
            ProcessingView(session: session)
        } else {
            VStack(spacing: 0) {
                TimelinePanel(session: session)
                Divider()
                HSplitView {
                    TranscriptView(session: session)
                        .frame(minWidth: 480, maxWidth: .infinity)
                    SidebarView(session: session)
                        .frame(minWidth: 270, idealWidth: 310, maxWidth: 420)
                }
            }
            .overlay(alignment: .top) {
                if session.isProcessing {
                    ProcessingBanner(session: session).padding(.top, 8)
                }
            }
        }
    }

    var subtitle: String {
        let p = session.project
        var parts: [String] = []
        if let media = p.media { parts.append(URL(fileURLWithPath: media.path).lastPathComponent) }
        if p.duration > 0 { parts.append(Timecode.short(p.duration)) }
        if !p.speakers.isEmpty { parts.append("\(p.speakers.count) \(p.speakers.count == 1 ? "speaker" : "speakers")") }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(get: { session.project.settings.enhance }, set: { session.setEnhance($0) })) {
                Label("Enhance", systemImage: "waveform.badge.magnifyingglass")
            }
            .help("Clean up the audio for playback, transcription and export (Clear)")
            Toggle(isOn: Binding(get: { session.isRedacting }, set: { session.setRedact($0) })) {
                Label("Redact", systemImage: session.isFindingDetails ? "hourglass" : "eye.slash")
            }
            .help("Hide names, phone numbers, addresses and other personal details in the transcript, copies, exports and clips (Redact)")
            LanguageMenu(session: session, title: languageName(session.project.language))
            Menu {
                ForEach(TextFormat.copyFormats) { format in
                    Button {
                        UserDefaults.standard.set(format.rawValue, forKey: AppSettings.copyFormat)
                        session.copyAll()
                    } label: {
                        if AppSettings.copyFormatValue == format { Label(format.title, systemImage: "checkmark") } else { Text(format.title) }
                    }
                }
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            } primaryAction: {
                session.copyAll()
            }
            .help("Copy the transcript (\(AppSettings.copyFormatValue.title))")
            Button { session.showExport = true } label: { Label("Export", systemImage: "square.and.arrow.up") }
                .help("Export text, subtitles or clips")
        }
    }

    func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Leave typing alone: text fields get their keys first when focused.
        if session.editing { return .ignored }
        if NSApp.keyWindow?.firstResponder is NSTextView { return .ignored }
        switch press.key {
        case .space: session.player.toggle(); return .handled
        case .leftArrow: session.player.skip(by: press.modifiers.contains(.shift) ? -1 : -5); return .handled
        case .rightArrow: session.player.skip(by: press.modifiers.contains(.shift) ? 1 : 5); return .handled
        case .escape: session.selection = nil; session.cancelPendingSection(); return .handled
        default: break
        }
        guard press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
        switch press.characters.lowercased() {
        case "m": session.toggleMarkSection(); return .handled
        default: return .ignored
        }
    }
}

/// Shows the language and offers to transcribe again in another one.
struct LanguageMenu: View {
    let session: ProjectSession
    let title: String

    static let common = ["en", "de", "fr", "es", "it", "pt", "nl", "pl", "sv", "da", "fi", "ru", "uk", "cs", "ja", "zh", "ko"]

    var body: some View {
        Menu {
            Section("Transcribe again as") {
                ForEach(Self.common, id: \.self) { code in
                    Button(languageName(code)) { session.retranscribe(language: code) }
                }
            }
            Divider()
            Button("Detect Again") { session.retranscribe() }
        } label: {
            Label(title, systemImage: "translate")
        }
        .disabled(session.isProcessing || session.mediaMissing)
        .help("Spoken language")
    }
}

struct ProcessingBanner: View {
    let session: ProjectSession

    var body: some View {
        let running = session.steps.first { $0.state == .running }
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(running.map { "\($0.title)…" } ?? "Processing…").font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
    }
}
