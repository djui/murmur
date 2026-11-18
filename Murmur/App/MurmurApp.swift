import AppKit
import MurmurCore
import Sparkle
import SwiftUI

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var app = AppState.shared
    @State private var models = ModelManager.shared

    init() { AppSettings.register() }

    var body: some Scene {
        Window("Library", id: "library") {
            LibraryView()
                .environment(app)
                .environment(models)
                .modifier(SceneBridge())
        }
        .defaultSize(width: 980, height: 640)
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .commands { MurmurCommands(updater: appDelegate.updater) }

        DocumentGroup(newDocument: { ProjectDocument() }) { file in
            MainView(document: file.document, fileURL: file.fileURL)
                .environment(app)
                .environment(models)
                .modifier(SceneBridge())
        }
        .defaultSize(width: 1280, height: 860)

        Window("Recording", id: "recording") {
            RecordingWindow()
                .environment(app)
        }
        .defaultSize(width: 1040, height: 680)
        .keyboardShortcut("r", modifiers: [.command, .option])

        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsWindow()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .keyboardShortcut("/", modifiers: .command)

        Settings {
            SettingsView(updater: appDelegate.updater)
                .environment(app)
                .environment(models)
        }

        MenuBarExtra(isInserted: Binding(get: { app.recorder.isActive }, set: { _ in })) {
            RecordingMenu().environment(app)
        } label: {
            RecordingMenuLabel(recorder: app.recorder)
        }
    }
}

/// Hands the scene's open actions to `AppState`, for code outside views.
struct SceneBridge: ViewModifier {
    @Environment(\.openDocument) private var openDocument
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            let open = openDocument
            AppState.shared.openDocument = { url in
                Task {
                    do { try await open(at: url) } catch {
                        AppState.shared.presentError(error, title: "Couldn’t open \(url.lastPathComponent)")
                    }
                }
            }
            let window = openWindow
            AppState.shared.openWindow = { id in window(id: id) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Sparkle runs only once the build carries an update-signing key (`SUPublicEDKey`).
    lazy var updater: SPUStandardUpdaterController? = {
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return nil }
        return SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // One project per window: no Show Tab Bar, Merge All Windows and the like.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if HeadlessRunner.runIfRequested() {
            NSApp.setActivationPolicy(.prohibited)
            NSApp.windows.forEach { $0.close() }
            return
        }
        Appearance.current.apply()
        _ = updater
        HotKey.shared.install()
        RecordingController.recover()
        Task {
            await ModelManager.shared.updateOutdated()
            await ModelManager.shared.prepareDownloaded()
        }
        #if DEBUG
        if let mode = UserDefaults.standard.string(forKey: "previewRecorder") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { AppState.shared.recorder.preview(strip: mode == "strip") }
        }
        #endif
        // `-import <file>` creates and opens a project at launch (scripting and testing).
        if let path = UserDefaults.standard.string(forKey: "import") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                AppState.shared.importMedia(URL(fileURLWithPath: path))
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppState.shared.openWindow?("library") }
        return true
    }
}

struct MurmurCommands: Commands {
    let updater: SPUStandardUpdaterController?
    @FocusedValue(\.session) private var session
    @AppStorage(AppSettings.showInspector) private var showInspector = true
    @AppStorage(AppSettings.timelineLayout) private var timelineLayout = TimelineLayout.top.rawValue

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Recording") { AppState.shared.recorder.start() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Import Audio or Video…") { AppState.shared.presentImportPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater?.checkForUpdates(nil) }
                .disabled(updater == nil)
        }
        CommandGroup(after: .toolbar) {
            Button(showInspector ? "Hide Inspector" : "Show Inspector") { showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(session == nil)
            Toggle("Vertical Timeline", isOn: Binding(
                get: { timelineLayout == TimelineLayout.left.rawValue },
                set: { timelineLayout = ($0 ? TimelineLayout.left : .top).rawValue }))
        }
        CommandMenu("Recording") { RecordingCommands() }
        CommandMenu("Transcript") {
            Button(ShortcutStore.shared.titled("Play / Pause", .playPause)) { session?.player.toggle() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(session == nil || session?.mediaMissing == true)
            Button(session?.pendingStart != nil ? "End Section" : "Mark Section") { session?.toggleMarkSection() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Back to Current Position") { session?.jumpRequest += 1 }
                .keyboardShortcut("j", modifiers: .command)
                .disabled(session == nil)
            Button("Find…") { session?.findRequest += 1 }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(session == nil)
            Divider()
            Button("Zoom In") { session?.zoom *= 2 }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(session == nil)
            Button("Zoom Out") { session?.zoom /= 2 }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(session == nil)
            Button("Zoom to Fit") { session?.zoom = 1 }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(session == nil)
            Divider()
            Button("Copy Transcript") { session?.copyAll() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(session == nil)
            Button("Copy Selection") { session?.copySelection() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(session?.selection == nil)
            Button("Export…") { session?.showExport = true }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(session == nil)
            Divider()
            Button("Trim Start to Playhead") { session?.trimStart() }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(session == nil || session?.mediaMissing == true)
            Button("Trim End to Playhead") { session?.trimEnd() }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(session == nil || session?.mediaMissing == true)
            Button("Trim to Selection") { session?.trimToSelection() }
                .disabled(session?.selection == nil)
            Button("Remove Trim") { session?.removeTrim() }
                .disabled(session?.project.trim == nil)
            Divider()
            Button("Transcribe Again") { session?.retranscribe() }
                .disabled(session == nil || session?.isProcessing == true)
        }
    }
}

struct SessionKey: FocusedValueKey { typealias Value = ProjectSession }

extension FocusedValues {
    var session: ProjectSession? {
        get { self[SessionKey.self] }
        set { self[SessionKey.self] = newValue }
    }
}

/// The Recording menu: the strip's controls, for while a recording runs. Pause's ⌥⌘P and the mark key
/// also work from any app (see `HotKey`); here they show and work while Murmur is in front.
/// A view, so the menu follows the recorder as it changes.
private struct RecordingCommands: View {
    private let store = ShortcutStore.shared

    var body: some View {
        let recorder = AppState.shared.recorder
        let running = recorder.state == .recording || recorder.state == .paused
        Button(recorder.state == .paused ? "Resume" : "Pause") { recorder.togglePause() }
            .keyboardShortcut(HotKey.pauseCombo.shortcut)
            .disabled(!running)
        Button("Mark Moment") { recorder.addMark() }
            .keyboardShortcut(store.markMoment.shortcut)
            .disabled(!running)
        Button("Write a Note") { CompactPanelController.shared.show(); recorder.writeNote() }
            .disabled(!running)
        Divider()
        Button("Show Compact Window") { CompactPanelController.shared.show() }
            .disabled(!running)
        Button("Shrink to Strip") { CompactPanelController.shared.show(); CompactPanelController.shared.setStrip(true) }
            .disabled(!running || recorder.strip)
        Divider()
        Button("Stop and Finish") { recorder.stop() }
            .disabled(!running)
    }
}

extension HotKeyCombo {
    /// The same keys as a menu shortcut, so the menu shows them.
    var shortcut: KeyboardShortcut? {
        guard let character = key.lowercased().first else { return nil }
        var flags: EventModifiers = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: flags)
    }
}
