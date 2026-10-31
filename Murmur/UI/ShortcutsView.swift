import AppKit
import MurmurCore
import SwiftUI

/// The single-key shortcuts people chose, saved in user defaults.
@Observable
@MainActor
final class ShortcutStore {
    static let shared = ShortcutStore()

    private(set) var map = ShortcutMap(stored: UserDefaults.standard.dictionary(forKey: AppSettings.shortcuts) as? [String: String] ?? [:])

    func symbol(_ action: ShortcutAction) -> String { map.key(for: action).symbol }

    @discardableResult
    func set(_ key: ShortcutKey, for action: ShortcutAction) -> Bool {
        var next = map
        guard next.set(key, for: action) else { return false }
        map = next
        save()
        return true
    }

    func reset() {
        map = ShortcutMap()
        save()
    }

    private func save() { UserDefaults.standard.set(map.stored, forKey: AppSettings.shortcuts) }
}

extension ShortcutKey {
    init?(_ press: KeyPress) {
        switch press.key {
        case .space: self = .space
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        case .upArrow: self = .up
        case .downArrow: self = .down
        default: self.init(rawValue: press.characters)
        }
    }

    init?(_ event: NSEvent) {
        switch event.keyCode {
        case 49: self = .space
        case 123: self = .left
        case 124: self = .right
        case 125: self = .down
        case 126: self = .up
        default: self.init(rawValue: event.characters ?? "")
        }
    }
}

/// Every shortcut in one place: Help › Keyboard Shortcuts (⌘/), or ? in a project window.
struct ShortcutsWindow: View {
    @Environment(\.openSettings) private var openSettings
    private let store = ShortcutStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Playback") {
                row(ShortcutAction.playPause.title, store.symbol(.playPause))
                row("Back or forward 5 seconds", store.symbol(.back), store.symbol(.forward))
                row("Back or forward 1 second", "⇧" + store.symbol(.back), "⇧" + store.symbol(.forward))
                row("Previous or next line", store.symbol(.previousLine), store.symbol(.nextLine))
                row("Back to current position", "⌘J")
            }
            section("Transcript") {
                row("Mark section, at its start and end", store.symbol(.markSection))
                row("Clear selection", "esc")
                row("Find in transcript", "⌘F")
                row("Copy transcript · selection", "⇧⌘C", "⌥⌘C")
                row("Export", "⌘E")
            }
            section("Timeline") {
                row("Zoom in · out · fit", "⌘=", "⌘−", "⌘0")
            }
            section("Recording") {
                row("New recording", "⇧⌘R")
                row("Mark a moment, from any app", "⌥⌘M")
            }
            Divider().padding(.top, 14)
            HStack {
                Text("Single keys work when you're not typing.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Change Shortcuts…") {
                    UserDefaults.standard.set(SettingsTab.shortcuts.rawValue, forKey: AppSettings.settingsTab)
                    openSettings()
                }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 18)
        .frame(width: 440)
    }

    func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.top, 14).padding(.bottom, 2)
            rows()
        }
    }

    func row(_ title: String, _ keys: String...) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 4) { ForEach(keys, id: \.self) { ShortcutCap(key: $0) } }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

/// A key as it looks on the keyboard, sized for a list.
struct ShortcutCap: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// Settings › Shortcuts: click a key, then press the new one.
struct ShortcutSettings: View {
    @State private var recording: ShortcutAction?
    @State private var note: String?
    private let store = ShortcutStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        KeyRecorder(action: action, recording: $recording, note: $note)
                    } label: {
                        Text(action.title)
                        if action == .back || action == .forward {
                            Text("With ⇧, 1 second")
                        }
                    }
                }
            } footer: {
                HStack(alignment: .top) {
                    Text(note ?? "Esc cancels. If the key already does something else, the two swap.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { recording = nil; note = nil; store.reset() }
                        .disabled(store.map.isDefault)
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("Shortcuts with ⌘ come from the menus. Change them in System Settings › Keyboard › Keyboard Shortcuts › App Shortcuts.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows an action's key; while recording, the next key pressed becomes the new one.
struct KeyRecorder: View {
    let action: ShortcutAction
    @Binding var recording: ShortcutAction?
    @Binding var note: String?
    @State private var monitor: Any?
    private let store = ShortcutStore.shared

    var isRecording: Bool { recording == action }

    var body: some View {
        Button { recording = isRecording ? nil : action } label: {
            Text(isRecording ? "Press a key…" : store.symbol(action))
                .font(.system(size: 12))
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
                .frame(width: 110, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 2 : 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(action.title): \(store.symbol(action))")
        .onChange(of: isRecording) { _, on in on ? listen() : stop() }
        .onDisappear { recording = nil; stop() }
    }

    // A key-down monitor rather than focus: it catches the key wherever focus is in the window.
    func listen() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            record(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    func record(_ event: NSEvent) {
        if event.keyCode == 53 { recording = nil; return } // esc
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
            note = "Keys with ⌘, ⌃ or ⌥ are set in System Settings, below."
            return
        }
        guard let key = ShortcutKey(event) else { return }
        let other = store.map.action(for: key)
        guard store.set(key, for: action) else {
            note = "? opens the list of shortcuts, so it can't be changed."
            return
        }
        if let other, other != action {
            note = "\(key.symbol) was \(other.title.lowercased()); that now uses \(store.symbol(other))."
        } else {
            note = nil
        }
        recording = nil
    }
}
