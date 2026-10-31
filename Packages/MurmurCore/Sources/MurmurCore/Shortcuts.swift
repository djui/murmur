import Foundation

/// The things a single key does in a project window, without ⌘. People can change these keys;
/// shortcuts with ⌘ come from the menus and are changed in System Settings instead.
public enum ShortcutAction: String, CaseIterable, Identifiable, Sendable {
    case playPause, back, forward, previousLine, nextLine, markSection

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .playPause: "Play or pause"
        case .back: "Back 5 seconds"
        case .forward: "Forward 5 seconds"
        case .previousLine: "Previous line"
        case .nextLine: "Next line"
        case .markSection: "Mark section"
        }
    }

    public var defaultKey: ShortcutKey {
        switch self {
        case .playPause: .space
        case .back: .left
        case .forward: .right
        case .previousLine: .up
        case .nextLine: .down
        case .markSection: ShortcutKey(rawValue: "m")!
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

/// Which key does what. Only keys that differ from the defaults are stored.
public struct ShortcutMap: Equatable, Sendable {
    private var keys: [ShortcutAction: ShortcutKey]

    /// `?` opens the list of shortcuts, so it can't be given to anything else.
    public static let reserved: Set<String> = ["?"]

    public init(stored: [String: String] = [:]) {
        keys = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultKey) })
        for action in ShortcutAction.allCases {
            if let raw = stored[action.rawValue], let key = ShortcutKey(rawValue: raw) { set(key, for: action) }
        }
    }

    public var stored: [String: String] {
        var out: [String: String] = [:]
        for (action, key) in keys where key != action.defaultKey { out[action.rawValue] = key.rawValue }
        return out
    }

    public func key(for action: ShortcutAction) -> ShortcutKey { keys[action] ?? action.defaultKey }

    public func action(for key: ShortcutKey) -> ShortcutAction? {
        ShortcutAction.allCases.first { keys[$0] == key }
    }

    /// Gives `key` to `action`. An action that had the key gets `action`'s old one, so no key is lost.
    /// Returns false for a reserved key.
    @discardableResult
    public mutating func set(_ key: ShortcutKey, for action: ShortcutAction) -> Bool {
        guard !Self.reserved.contains(key.rawValue) else { return false }
        let old = self.key(for: action)
        if let other = self.action(for: key), other != action { keys[other] = old }
        keys[action] = key
        return true
    }

    public var isDefault: Bool { stored.isEmpty }
}
