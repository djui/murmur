import Testing
@testable import MurmurCore

@Suite struct ShortcutTests {
    @Test func defaults() {
        let map = ShortcutMap()
        #expect(map.key(for: .playPause) == .space)
        #expect(map.action(for: .left) == .back)
        #expect(map.key(for: .markSection).symbol == "M")
        #expect(map.isDefault)
        #expect(map.stored.isEmpty)
    }

    @Test func storesOnlyChanges() {
        var map = ShortcutMap()
        map.set(ShortcutKey(rawValue: "k")!, for: .playPause)
        #expect(map.stored == ["playPause": "k"])
        #expect(ShortcutMap(stored: map.stored) == map)
    }

    @Test func takingAKeySwaps() {
        var map = ShortcutMap()
        map.set(.space, for: .markSection)
        #expect(map.key(for: .markSection) == .space)
        #expect(map.key(for: .playPause).rawValue == "m")
        #expect(map.action(for: .space) == .markSection)
    }

    @Test func reservedKeysAreRefused() {
        var map = ShortcutMap()
        let taken = map.set(ShortcutKey(rawValue: "?")!, for: .playPause)
        #expect(!taken)
        #expect(map.key(for: .playPause) == .space)
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

    @Test func ignoresBadStoredValues() {
        let map = ShortcutMap(stored: ["playPause": "nonsense", "nextLine": "j", "unknown": "x"])
        #expect(map.key(for: .playPause) == .space)
        #expect(map.key(for: .nextLine).rawValue == "j")
    }
}
