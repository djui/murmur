import AppKit
import Carbon.HIToolbox
import MurmurCore

/// Keys that work while recording, whichever app is in front: ⌥⌘M (unless changed in Settings) marks a
/// moment, ⌥⌘P pauses or resumes. Pausing is only registered while a recording runs, so the
/// combination stays free for other apps (Finder's path bar) the rest of the time.
@MainActor
final class HotKey {
    static let shared = HotKey()
    private var markRef: EventHotKeyRef?
    private var pauseRef: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private static let signature = OSType(0x4D524D52) // "MRMR"
    private static let markID: UInt32 = 1, pauseID: UInt32 = 2
    /// ⌥⌘P.
    static let pauseCombo = HotKeyCombo(keyCode: UInt32(kVK_ANSI_P), modifiers: [.option, .command], key: "P")
    static var pauseSymbol: String { pauseCombo.symbol }

    private var enabled: Bool { UserDefaults.standard.bool(forKey: AppSettings.markHotKey) }

    /// Returns false when the mark combination couldn't be registered, usually because another app has it.
    @discardableResult
    func install() -> Bool {
        uninstall()
        guard enabled else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let pressed = id.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let recorder = AppState.shared.recorder
                    guard recorder.isActive else { return }
                    if pressed == HotKey.pauseID { recorder.togglePause() } else { recorder.addMark() }
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        let combo = ShortcutStore.shared.markMoment
        let status = RegisterEventHotKey(combo.keyCode, Self.carbonModifiers(combo.modifiers),
                                         EventHotKeyID(signature: Self.signature, id: Self.markID),
                                         GetApplicationEventTarget(), 0, &markRef)
        updatePause()
        return status == noErr
    }

    /// Registers ⌥⌘P while a recording runs and releases it otherwise. Called when the recording state changes.
    func updatePause() {
        let wanted = enabled && handler != nil && AppState.shared.recorder.isActive
        if wanted, pauseRef == nil {
            let combo = Self.pauseCombo
            RegisterEventHotKey(combo.keyCode, Self.carbonModifiers(combo.modifiers),
                                EventHotKeyID(signature: Self.signature, id: Self.pauseID),
                                GetApplicationEventTarget(), 0, &pauseRef)
        } else if !wanted, let pauseRef {
            UnregisterEventHotKey(pauseRef)
            self.pauseRef = nil
        }
    }

    func uninstall() {
        if let markRef { UnregisterEventHotKey(markRef) }
        if let pauseRef { UnregisterEventHotKey(pauseRef) }
        if let handler { RemoveEventHandler(handler) }
        markRef = nil
        pauseRef = nil
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
