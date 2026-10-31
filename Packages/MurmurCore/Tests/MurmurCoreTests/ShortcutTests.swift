import Foundation
import Testing
@testable import MurmurCore

@Suite struct ShortcutTests {
    @Test func defaults() {
        let map = ShortcutMap()
        #expect(map.key(for: .playPause) == .space)
        #expect(map.keys(for: .playPause).map(\.symbol) == ["Space", "K"])
        #expect(map.action(for: .left) == .back)
        #expect(map.action(for: ShortcutKey(rawValue: "l")!) == .forward)
        #expect(map.key(for: .faster)?.symbol == "]")
        #expect(map.isDefault)
        #expect(map.stored.isEmpty)
    }

    @Test func everyDefaultKeyIsUnique() {
        let all = ShortcutAction.allCases.flatMap(\.defaultKeys)
        #expect(Set(all).count == all.count)
    }

    @Test func storesOnlyChanges() {
        var map = ShortcutMap()
        map.add(ShortcutKey(rawValue: "p")!, to: .playPause)
        #expect(map.stored == ["playPause": ["space", "k", "p"]])
        #expect(ShortcutMap(stored: map.stored) == map)
    }

    @Test func addingATakenKeyMovesIt() {
        var map = ShortcutMap()
        #expect(map.add(.space, to: .markSection) == .moved(from: .playPause))
        #expect(map.keys(for: .markSection).map(\.rawValue) == ["m", "space"])
        #expect(map.keys(for: .playPause).map(\.rawValue) == ["k"])
        #expect(map.action(for: .space) == .markSection)
        #expect(map.add(.space, to: .markSection) == .added)
    }

    @Test func removingCanLeaveNoKey() {
        var map = ShortcutMap()
        map.remove(.up, from: .previousLine)
        #expect(map.key(for: .previousLine) == nil)
        #expect(map.action(for: .up) == nil)
        #expect(ShortcutMap(stored: map.stored) == map)
    }

    @Test func reservedKeysAreRefused() {
        var map = ShortcutMap()
        let result = map.add(ShortcutKey(rawValue: "?")!, to: .playPause)
        #expect(result == .reserved)
        #expect(map.isDefault)
    }

    @Test func keyNames() {
        #expect(ShortcutKey(rawValue: "M")?.rawValue == "m")
        #expect(ShortcutKey(rawValue: "up")?.symbol == "↑")
        #expect(ShortcutKey(rawValue: "space")?.symbol == "Space")
        #expect(ShortcutKey(rawValue: "") == nil)
        #expect(ShortcutKey(rawValue: " ") == nil)
        #expect(ShortcutKey(rawValue: "ab") == nil)
        #expect(ShortcutKey(rawValue: "\t") == nil)
    }

    @Test func readsOldSingleKeySettings() {
        // How 0.1.6 stored a changed key: one string per action.
        let map = ShortcutMap(stored: ["playPause": "nonsense", "nextLine": "j", "unknown": "x"])
        #expect(map.keys(for: .playPause).isEmpty)
        #expect(map.keys(for: .nextLine).map(\.rawValue) == ["j"])
        #expect(map.keys(for: .back) == [.left])
    }

    @Test func hotKeySymbols() {
        #expect(HotKeyCombo.markMoment.symbol == "⌥⌘M")
        let all = HotKeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control], key: "a")
        #expect(all.symbol == "⌃⌥⇧⌘A")
        #expect(!HotKeyCombo(keyCode: 0, modifiers: [.shift], key: "a").isUsable)
        #expect(HotKeyCombo.markMoment.isUsable)
        let data = try! JSONEncoder().encode(HotKeyCombo.markMoment)
        #expect(try! JSONDecoder().decode(HotKeyCombo.self, from: data) == .markMoment)
    }
}
