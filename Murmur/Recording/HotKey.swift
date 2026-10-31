import AppKit
import Carbon.HIToolbox
import MurmurCore

/// Marks a moment while recording, whichever app is in front. ⌥⌘M unless changed in Settings.
@MainActor
final class HotKey {
    static let shared = HotKey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// Returns false when the combination couldn't be registered, usually because another app has it.
    @discardableResult
    func install() -> Bool {
        uninstall()
        guard UserDefaults.standard.bool(forKey: AppSettings.markHotKey) else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let recorder = AppState.shared.recorder
                    if recorder.isActive { recorder.addMark() }
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        let combo = ShortcutStore.shared.markMoment
        let id = EventHotKeyID(signature: OSType(0x4D524D52), id: 1) // "MRMR"
        let status = RegisterEventHotKey(combo.keyCode, Self.carbonModifiers(combo.modifiers), id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func uninstall() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }

    static func carbonModifiers(_ modifiers: HotKeyCombo.Modifiers) -> UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}
