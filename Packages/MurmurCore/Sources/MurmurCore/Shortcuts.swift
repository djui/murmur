import Foundation

/// The things a single key does in a project window, without ⌘. People can change these keys;
/// shortcuts with ⌘ come from the menus and are changed in System Settings instead.
public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case playPause, back, forward, previousLine, nextLine, slower, faster, markSection

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .playPause: "Play or pause"
        case .back: "Back 5 seconds"
        case .forward: "Forward 5 seconds"
        case .previousLine: "Previous line"
        case .nextLine: "Next line"
        case .slower: "Play slower"
        case .faster: "Play faster"
        case .markSection: "Mark section"
        }
    }

    /// J, K and L work as in video editors, next to Space and the arrows.
    public var defaultKeys: [ShortcutKey] {
        switch self {
        case .playPause: [.space, .k("k")]
        case .back: [.left, .k("j")]
        case .forward: [.right, .k("l")]
        case .previousLine: [.up]
        case .nextLine: [.down]
        case .slower: [.k("[")]
        case .faster: [.k("]")]
        case .markSection: [.k("m")]
        }
    }
}

/// One key, stored by name: `space`, an arrow (`left`, `right`, `up`, `down`), or a single character.
public struct ShortcutKey: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public static let space = ShortcutKey(named: "space")
    public static let left = ShortcutKey(named: "left")
    public static let right = ShortcutKey(named: "right")
    public static let up = ShortcutKey(named: "up")
    public static let down = ShortcutKey(named: "down")

    static let names: [String: String] = ["space": "Space", "left": "←", "right": "→", "up": "↑", "down": "↓"]

    private init(named name: String) { rawValue = name }

    static func k(_ character: String) -> ShortcutKey { ShortcutKey(rawValue: character)! }

    /// Letters are kept lowercase, so M and ⇧M are the same key.
    public init?(rawValue: String) {
        if Self.names[rawValue] != nil { self.rawValue = rawValue; return }
        guard rawValue.count == 1, let c = rawValue.first, !c.isWhitespace, !c.isNewline,
              c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        self.rawValue = rawValue.lowercased()
    }

    /// How the key reads on a key cap: "Space", "←", "M".
    public var symbol: String { Self.names[rawValue] ?? rawValue.uppercased() }
}

/// Which keys do what. An action can have several keys, or none; a key does at most one thing.
/// Only actions whose keys differ from the defaults are stored.
public struct ShortcutMap: Equatable, Sendable {
    private var keys: [ShortcutAction: [ShortcutKey]]

    /// `?` opens the list of shortcuts, so it can't be given to anything else.
    public static let reserved: Set<String> = ["?"]

    public enum AddResult: Equatable, Sendable {
        case added
        /// The key did something else before, and now does this instead.
        case moved(from: ShortcutAction)
        case reserved
    }

    /// `stored` maps an action to its keys; a single string (how one key per action was stored) also works.
    public init(stored: [String: Any] = [:]) {
        keys = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultKeys) })
        for action in ShortcutAction.allCases {
            let raw: [String]
            switch stored[action.rawValue] {
            case let list as [String]: raw = list
            case let one as String: raw = [one]
            default: continue
            }
            keys[action] = []
            for key in raw.compactMap(ShortcutKey.init(rawValue:)) { add(key, to: action) }
        }
    }

    public var stored: [String: [String]] {
        var out: [String: [String]] = [:]
        for action in ShortcutAction.allCases where keys(for: action) != action.defaultKeys {
            out[action.rawValue] = keys(for: action).map(\.rawValue)
        }
        return out
    }

    public func keys(for action: ShortcutAction) -> [ShortcutKey] { keys[action] ?? [] }

    /// The first key, for hints and menus; nil when the action has none.
    public func key(for action: ShortcutAction) -> ShortcutKey? { keys(for: action).first }

    public func action(for key: ShortcutKey) -> ShortcutAction? {
        ShortcutAction.allCases.first { keys(for: $0).contains(key) }
    }

    /// Gives `key` to `action` as one more key, taking it from whatever had it.
    @discardableResult
    public mutating func add(_ key: ShortcutKey, to action: ShortcutAction) -> AddResult {
        guard !Self.reserved.contains(key.rawValue) else { return .reserved }
        let previous = self.action(for: key)
        if previous == action { return .added }
        if let previous { keys[previous]?.removeAll { $0 == key } }
        keys[action, default: []].append(key)
        return previous.map { .moved(from: $0) } ?? .added
    }

    public mutating func remove(_ key: ShortcutKey, from action: ShortcutAction) {
        keys[action]?.removeAll { $0 == key }
    }

    public var isDefault: Bool { stored.isEmpty }
}

/// A key with ⌘, ⌥ or ⌃ that works from any app, like the one that marks a moment while recording.
public struct HotKeyCombo: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The hardware key code (kVK_…), which doesn't change with the keyboard layout.
    public var keyCode: UInt32
    public var modifiers: Modifiers
    /// What the key shows, like "M".
    public var key: String

    public init(keyCode: UInt32, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key.uppercased()
    }

    /// ⌥⌘M.
    public static let markMoment = HotKeyCombo(keyCode: 46, modifiers: [.option, .command], key: "M")

    /// In the order macOS menus use: ⌃⌥⇧⌘.
    public var symbol: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    /// Shift alone would take a plain letter away from every other app.
    public var isUsable: Bool { !modifiers.isDisjoint(with: [.command, .option, .control]) && !key.isEmpty }
}
