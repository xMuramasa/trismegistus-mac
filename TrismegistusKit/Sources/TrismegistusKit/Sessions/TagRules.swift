import Foundation

/// The relay's tag rules (relay/internal/server/tags.go normalizeTags), checked here first so a bad tag never leaves
/// the Mac: 1-32 characters after trimming, no control characters, at most 10 per session, case-insensitive.
public enum TagRules {
    public static let maxTags = 10
    public static let maxLength = 32

    public enum Violation: Error, Sendable, Equatable {
        case empty, tooLong, controlCharacters, tooMany

        public var message: String {
            switch self {
            case .empty: "A tag can't be empty."
            case .tooLong: "A tag is at most \(TagRules.maxLength) characters."
            case .controlCharacters: "A tag can't contain control characters."
            case .tooMany: "At most \(TagRules.maxTags) tags per conversation."
            }
        }
    }

    /// Case-insensitive key: two tags with the same key are the same tag.
    public static func key(_ tag: String) -> String { tag.lowercased() }

    /// The tag as the relay stores it, or why it can't be.
    public static func validate(_ tag: String) throws(Violation) -> String {
        let t = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { throw .empty }
        if t.unicodeScalars.count > maxLength { throw .tooLong }
        if t.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) { throw .controlCharacters }
        return t
    }

    /// The whole set, trimmed and deduplicated (the first spelling stays), as the relay would store it.
    public static func normalize(_ tags: [String]) throws(Violation) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for tag in tags {
            let t = try validate(tag)
            if seen.insert(key(t)).inserted { out.append(t) }
        }
        if out.count > maxTags { throw .tooMany }
        return out
    }

    /// `tags` plus `new`; the same list if it is already there (any case).
    public static func adding(_ new: String, to tags: [String]) throws(Violation) -> [String] {
        try normalize(tags + [new])
    }

    public static func removing(_ tag: String, from tags: [String]) -> [String] {
        tags.filter { key($0) != key(tag) }
    }
}
