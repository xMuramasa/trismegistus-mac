import Foundation

/// How the lists order and filter conversations: pinned first, tags with their counts.
public enum SessionListing {
    /// The pinned items and the rest, each group keeping its order.
    public static func pinnedApart<T>(_ items: [T], isPinned: (T) -> Bool) -> (pinned: [T], rest: [T]) {
        (items.filter(isPinned), items.filter { !isPinned($0) })
    }

    /// The window's chat groups (#72, design 15b): In progress on top, the items waiting for an approval and then the
    /// running ones, pinned or not; then the pinned and the rest (an unseen done or failed mark stays in its group). Each
    /// keeps the items' order (most recent first).
    public static func groups<T>(_ items: [T], attention: (T) -> ConversationKind.Attention?, isPinned: (T) -> Bool)
        -> (inProgress: [T], pinned: [T], rest: [T]) {
        let quiet = pinnedApart(items.filter { attention($0)?.isLive != true }, isPinned: isPinned)
        return (items.filter { attention($0) == .approval } + items.filter { attention($0) == .running }, quiet.pinned, quiet.rest)
    }

    /// The tags of the given sessions with how many of them carry each, most used first, then by name. Tags are
    /// merged case-insensitively under their first spelling; ids that aren't in `ids` (the relay keeps those of
    /// sessions deleted elsewhere) are ignored.
    public static func tagCounts(ids: [String], tags: [String: [String]]) -> [(tag: String, count: Int)] {
        var spelling: [String: String] = [:]
        var counts: [String: Int] = [:]
        for id in ids {
            for tag in tags[id] ?? [] {
                let k = TagRules.key(tag)
                spelling[k] = spelling[k] ?? tag
                counts[k, default: 0] += 1
            }
        }
        return counts.map { (spelling[$0.key] ?? $0.key, $0.value) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    /// What to select once the list goes from `old` to `new` ids: `selected` unless it left the list, then the
    /// conversation that took its place (the next one down, or the last), nil when none is left.
    public static func selection(_ selected: String?, from old: [String], to new: [String]) -> String? {
        guard let selected, let i = old.firstIndex(of: selected), !new.contains(selected) else { return selected }
        return new.isEmpty ? nil : new[min(i, new.count - 1)]
    }

    /// One item per thread, its newest part (see `HandoffChain`): items that another listed item continues are left out.
    public static func threads<T>(_ items: [T], id: (T) -> String, links: [String: String]) -> [T] {
        guard !links.isEmpty else { return items }
        let hidden = HandoffChain.continued(listed: Set(items.map(id)), links: links)
        return items.filter { !hidden.contains(id($0)) }
    }

    public static func hasTag(_ tag: String, in tags: [String]) -> Bool {
        tags.contains { TagRules.key($0) == TagRules.key(tag) }
    }
}
