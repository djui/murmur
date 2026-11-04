import Foundation

/// Tags sort projects into groups such as Interviews, 1:1s or Meetings. A project can carry any number;
/// they compare without regard to case, keep the spelling they were first given, and list alphabetically.
public enum Tags {
    /// `name` trimmed and with runs of whitespace collapsed; nil when nothing is left.
    public static func clean(_ name: String) -> String? {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    public static func same(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Cleaned, without duplicates (the first spelling wins) and in alphabetical order.
    public static func normalize<S: Sequence>(_ names: S) -> [String] where S.Element == String {
        var out: [String] = []
        for name in names {
            guard let tag = clean(name), !out.contains(where: { same($0, tag) }) else { continue }
            out.append(tag)
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

extension Project {
    /// The project's tags, normalized; empty when it has none.
    public var tagList: [String] { Tags.normalize(tags ?? []) }

    public func hasTag(_ tag: String) -> Bool { tagList.contains { Tags.same($0, tag) } }

    public mutating func addTag(_ tag: String) {
        setTags(tagList + [tag])
    }

    public mutating func removeTag(_ tag: String) {
        setTags(tagList.filter { !Tags.same($0, tag) })
    }

    /// Renames `old` to `new`, merging with a tag already spelled `new`.
    public mutating func renameTag(_ old: String, to new: String) {
        guard hasTag(old), let new = Tags.clean(new) else { return }
        setTags([new] + tagList.filter { !Tags.same($0, old) })
    }

    /// Stores `list` normalized; an empty list is stored as nil, so untagged files stay as they were.
    public mutating func setTags(_ list: [String]) {
        let list = Tags.normalize(list)
        tags = list.isEmpty ? nil : list
    }
}
