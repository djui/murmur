import MurmurCore
import SwiftUI

/// The project window: timeline on top, transcript and sidebar below.
struct MainView: View {
    @ObservedObject var document: ProjectDocument
    let fileURL: URL?
    @State private var session: ProjectSession
    @Environment(\.undoManager) private var undoManager
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
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
            // First uses retire the how-to hints everywhere.
            .onChange(of: session.selection != nil) { _, selected in
                if selected { UserDefaults.standard.set(true, forKey: AppSettings.hasSelected) }
            }
            .onChange(of: session.project.marks.count) { old, new in
                if new > old { UserDefaults.standard.set(true, forKey: AppSettings.hasMarked) }
            }
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
        // Only what sends the project somewhere; settings live next to what they change.
        ToolbarItemGroup(placement: .primaryAction) {
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
        if (NSApp.keyWindow ?? NSApp.mainWindow)?.firstResponder is NSTextView { return .ignored }
        if press.key == .escape { session.selection = nil; session.cancelPendingSection(); return .handled }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }
        if press.characters == "?" { openWindow(id: "shortcuts"); return .handled }
        guard let key = ShortcutKey(press), let action = ShortcutStore.shared.map.action(for: key) else { return .ignored }
        // Shift makes the skips finer.
        let step: Double = press.modifiers.contains(.shift) ? 1 : 5
        if session.mediaMissing, [.playPause, .back, .forward].contains(action) {
            session.flash("Locate \(URL(fileURLWithPath: session.project.media?.path ?? "").lastPathComponent) to play it")
            return .handled
        }
        switch action {
        case .playPause: session.player.toggle()
        case .back: session.player.skip(by: -step)
        case .forward: session.player.skip(by: step)
        case .previousLine: session.jumpToLine(-1)
        case .nextLine: session.jumpToLine(1)
        case .slower, .faster:
            session.player.changeRate(by: action == .slower ? -1 : 1)
            session.flash("Speed \(PlayerModel.label(session.player.rate))")
        case .markSection: session.toggleMarkSection()
        }
        return .handled
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
        .glassEffect(.regular, in: .capsule)
    }
}
