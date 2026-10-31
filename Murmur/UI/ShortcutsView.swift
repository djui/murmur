import AppKit
import MurmurCore
import SwiftUI

/// The keys people chose, saved in user defaults: single keys for project windows, and the
/// key that marks a moment from any app while recording.
@Observable
@MainActor
final class ShortcutStore {
    static let shared = ShortcutStore()

    private(set) var map = ShortcutMap(stored: UserDefaults.standard.dictionary(forKey: AppSettings.shortcuts) ?? [:])
    private(set) var markMoment: HotKeyCombo = UserDefaults.standard.data(forKey: AppSettings.markMomentKey)
        .flatMap { try? JSONDecoder().decode(HotKeyCombo.self, from: $0) } ?? .markMoment

    /// The first key, for hints; "none" when the action has no key.
    func symbol(_ action: ShortcutAction) -> String { map.key(for: action)?.symbol ?? "none" }

    func symbols(_ action: ShortcutAction) -> [String] { map.keys(for: action).map(\.symbol) }

    /// "Play or pause (Space)", or just the title when the action has no key.
    func titled(_ title: String, _ action: ShortcutAction) -> String {
        map.key(for: action).map { "\(title) (\($0.symbol))" } ?? title
    }

    @discardableResult
    func add(_ key: ShortcutKey, to action: ShortcutAction) -> ShortcutMap.AddResult {
        var next = map
        let result = next.add(key, to: action)
        map = next
        save()
        return result
    }

    func remove(_ key: ShortcutKey, from action: ShortcutAction) {
        map.remove(key, from: action)
        save()
    }

    func reset() {
        map = ShortcutMap()
        save()
    }

    /// Registers the new combination; returns false, keeping the old one, when another app has it.
    func setMarkMoment(_ combo: HotKeyCombo) -> Bool {
        let old = markMoment
        markMoment = combo
        guard HotKey.shared.install() else {
            markMoment = old
            HotKey.shared.install()
            return false
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: AppSettings.markMomentKey)
        return true
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
                row(.playPause)
                row("Back or forward 5 seconds", store.symbols(.back) + store.symbols(.forward))
                row("Back or forward 1 second", (store.map.key(for: .back).map { ["⇧" + $0.symbol] } ?? [])
                    + (store.map.key(for: .forward).map { ["⇧" + $0.symbol] } ?? []))
                row("Previous or next line", store.symbols(.previousLine) + store.symbols(.nextLine))
                row("Slower or faster", store.symbols(.slower) + store.symbols(.faster))
                row("Back to current position", ["⌘J"])
            }
            section("Transcript") {
                row("Mark section, at its start and end", store.symbols(.markSection))
                row("Clear selection", ["esc"])
                row("Find in transcript", ["⌘F"])
                row("Copy transcript · selection", ["⇧⌘C", "⌥⌘C"])
                row("Export", ["⌘E"])
            }
            section("Timeline") {
                row("Zoom in · out · fit", ["⌘=", "⌘−", "⌘0"])
            }
            section("Recording") {
                row("New recording", ["⇧⌘R"])
                row("Mark a moment, from any app", [store.markMoment.symbol])
                row("In the recording window: pause or resume", ["Space"])
                row("In the recording window: mark a moment · stop", ["M", "⌘."])
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
        .frame(width: 460)
    }

    func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.top, 14).padding(.bottom, 2)
            rows()
        }
    }

    func row(_ action: ShortcutAction) -> some View { row(action.title, store.symbols(action)) }

    func row(_ title: String, _ keys: [String]) -> some View {
        HStack {
            Text(title)
            Spacer()
            HStack(spacing: 4) {
                if keys.isEmpty { Text("none").foregroundStyle(.tertiary) }
                ForEach(Array(keys.enumerated()), id: \.offset) { ShortcutCap(key: $0.element) }
            }
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

/// Settings › Shortcuts: each action's keys; × removes one, + records another.
struct ShortcutSettings: View {
    @State private var recording: ShortcutAction?
    @State private var note: String?
    private let store = ShortcutStore.shared

    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        HStack(spacing: 6) {
                            ForEach(store.map.keys(for: action), id: \.self) { key in
                                KeyChip(title: key.symbol) {
                                    recording = nil
                                    store.remove(key, from: action)
                                    note = nil
                                }
                            }
                            KeyRecorder(action: action, recording: $recording, note: $note)
                        }
                    } label: {
                        Text(action.title)
                        if action == .back || action == .forward { Text("With ⇧, 1 second") }
                    }
                }
            } footer: {
                HStack(alignment: .top) {
                    Text(note ?? "Click + and press a key to add it. A key that did something else moves here. Esc cancels.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") { recording = nil; note = nil; store.reset() }
                        .disabled(store.map.isDefault)
                }
            }
            Section("Recording") {
                LabeledContent("Mark a moment, from any app") { HotKeyRecorder() }
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

/// One key of an action, with a button that takes it away.
struct KeyChip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(title).font(.system(size: 12))
            Button(action: remove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Remove \(title)")
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

/// Listens for the next key down anywhere in the window while `active`, instead of relying on focus.
@MainActor
final class KeyListener {
    private var monitor: Any?

    func start(_ handle: @escaping (NSEvent) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// The + after an action's keys; while recording, the next key pressed is added.
struct KeyRecorder: View {
    let action: ShortcutAction
    @Binding var recording: ShortcutAction?
    @Binding var note: String?
    @State private var listener = KeyListener()
    private let store = ShortcutStore.shared

    var isRecording: Bool { recording == action }

    var body: some View {
        Button { recording = isRecording ? nil : action } label: {
            Group {
                if isRecording { Text("Press a key…") } else { Image(systemName: "plus") }
            }
            .font(.system(size: 12))
            .foregroundStyle(isRecording ? Color.accentColor : .secondary)
            .frame(minWidth: 24)
            .padding(.horizontal, isRecording ? 8 : 0)
            .frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add a key for \(action.title.lowercased())")
        .onChange(of: isRecording) { _, on in on ? listener.start(record) : listener.stop() }
        .onDisappear { recording = nil; listener.stop() }
    }

    func record(_ event: NSEvent) {
        if event.keyCode == 53 { recording = nil; return } // esc
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
            note = "Keys with ⌘, ⌃ or ⌥ are set in System Settings, below."
            return
        }
        guard let key = ShortcutKey(event) else { return }
        switch store.add(key, to: action) {
        case .reserved:
            note = "? opens the list of shortcuts, so it can't be changed."
            return
        case .moved(let other):
            note = "\(key.symbol) was \(other.title.lowercased()); it now does \(action.title.lowercased())."
        case .added:
            note = nil
        }
        recording = nil
    }
}

/// Records the key that marks a moment from any app; it needs ⌘, ⌥ or ⌃.
struct HotKeyRecorder: View {
    @State private var isRecording = false
    @State private var note: String?
    @State private var listener = KeyListener()
    private let store = ShortcutStore.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button { isRecording.toggle() } label: {
                    Text(isRecording ? "Press keys…" : store.markMoment.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(isRecording ? Color.accentColor : .primary)
                        .frame(minWidth: 90)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isRecording ? 2 : 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark a moment: \(store.markMoment.symbol). Click to change.")
                if store.markMoment != .markMoment {
                    Button("Reset") { note = nil; _ = store.setMarkMoment(.markMoment) }
                }
            }
            if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
        }
        .onChange(of: isRecording) { _, on in on ? listener.start(record) : listener.stop() }
        .onDisappear { isRecording = false; listener.stop() }
    }

    func record(_ event: NSEvent) {
        if event.keyCode == 53 { isRecording = false; return } // esc
        var modifiers: HotKeyCombo.Modifiers = []
        if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
        if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
        if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
        if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
        let key = (event.charactersIgnoringModifiers ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        guard combo.isUsable, key.count == 1 else {
            note = "Hold ⌘, ⌥ or ⌃ and press a letter, number or symbol."
            return
        }
        note = store.setMarkMoment(combo) ? nil : "\(combo.symbol) is taken by another app. Try another."
        isRecording = false
    }
}
