import Foundation

/// Which tab of the Chat list a conversation is in, by Hermes' `source` (#48). `rawValue` is what the window and the
/// popover keep in `@AppStorage("chat.kind")`.
public enum ConversationKind: Hashable, Sendable, RawRepresentable {
    case app, telegram, terminal, oneShot, cron
    /// Any other source (a new messaging platform), by its raw name.
    case other(String)
    /// Every kind: the MORE menu's last entry.
    case all

    /// The kind of a conversation from `source`; never `.all`. A missing source reads as `other("unknown")`.
    public init(source: String?) {
        switch source {
        case "api_server": self = .app
        case "telegram": self = .telegram
        case "cli", "tui": self = .terminal
        case "oneshot": self = .oneShot
        case "cron": self = .cron
        case let name? where !name.isEmpty: self = .other(name)
        default: self = .other("unknown")
        }
    }

    public init?(rawValue: String) {
        switch rawValue {
        case "app": self = .app
        case "telegram": self = .telegram
        case "terminal": self = .terminal
        case "oneshot": self = .oneShot
        case "cron": self = .cron
        case "all": self = .all
        case _ where rawValue.hasPrefix("source:") && rawValue.count > 7: self = .other(String(rawValue.dropFirst(7)))
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .app: "app"
        case .telegram: "telegram"
        case .terminal: "terminal"
        case .oneShot: "oneshot"
        case .cron: "cron"
        case .other(let name): "source:\(name)"
        case .all: "all"
        }
    }

    /// The three kinds with a tab of their own; the rest are in the MORE menu.
    public static let tabs: [ConversationKind] = [.app, .telegram, .terminal]

    public var isInMore: Bool { !Self.tabs.contains(self) }

    public var name: String {
        switch self {
        case .app: "App"
        case .telegram: "Telegram"
        case .terminal: "Terminal"
        case .oneShot: "One-shots"
        case .cron: "Cron"
        case .other(let name): name
        case .all: "All"
        }
    }

    /// The empty tab's line.
    public var emptyText: String {
        switch self {
        case .app: "No conversations from the app"
        case .telegram: "No conversations from Telegram"
        case .terminal: "No conversations from the terminal"
        case .oneShot: "No one-shot conversations"
        case .cron: "No conversations from cron"
        case .other(let name): "No conversations from \(name)"
        case .all: "No conversations"
        }
    }

    public func includes(_ source: String?) -> Bool { self == .all || self == Self(source: source) }

    /// What a conversation, a kind or the whole list has to say (#66): an approval waits, a run is going, a run failed or
    /// finished unseen. The strongest wins: approval > running > failed > done.
    public enum Attention: Int, Sendable, Comparable {
        case done = 1, failed, running, approval

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        public init?(isWaitingForApproval: Bool, isRunning: Bool, unseen: Unseen.Mark? = nil) {
            if isWaitingForApproval {
                self = .approval
            } else if isRunning {
                self = .running
            } else if let unseen {
                self = unseen == .failed ? .failed : .done
            } else {
                return nil
            }
        }

        /// A waiting approval or a live run: the In progress group.
        public var isLive: Bool { self >= .running }
    }

    /// The counts and attention marks of a list: one entry per kind in the list (`item`, per listed conversation).
    public struct Summary: Sendable, Equatable {
        public struct Entry: Sendable, Equatable {
            public var count = 0
            public var attention: Attention?
        }

        private var entries: [ConversationKind: Entry] = [:]
        public let total: Entry

        public init(_ items: [(source: String?, attention: Attention?)]) {
            var total = Entry()
            for item in items {
                entries[ConversationKind(source: item.source), default: Entry()].add(item.attention)
                total.add(item.attention)
            }
            self.total = total
        }

        /// A kind's entry; `.all` is the whole list.
        public subscript(kind: ConversationKind) -> Entry { kind == .all ? total : entries[kind] ?? Entry() }

        /// The MORE menu: One-shots and Cron always, the other sources present by name, then All.
        public var more: [ConversationKind] {
            let others = entries.keys.compactMap { kind -> String? in if case .other(let name) = kind { name } else { nil } }
            return [.oneShot, .cron] + others.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.map(ConversationKind.other) + [.all]
        }

        /// The kind to show for a stored choice: an `.other` source that has left the list falls back to the app.
        public func resolving(_ kind: ConversationKind) -> ConversationKind {
            if case .other = kind, !more.contains(kind) { .app } else { kind }
        }

        /// What the MORE chip shows: the strongest mark among the entries it holds (not All, which repeats the tabs).
        public var moreAttention: Attention? {
            more.filter { $0 != .all }.compactMap { self[$0].attention }.max()
        }
    }
}

private extension ConversationKind.Summary.Entry {
    mutating func add(_ attention: ConversationKind.Attention?) {
        count += 1
        if let attention { self.attention = max(self.attention ?? attention, attention) }
    }
}

extension ConversationKind {
    /// The text of `2 more in TELEGRAM ›`: how many of `matches` (sources of the conversations matching the filter)
    /// are in another kind, for the first kind with some. Nil when the current kind has matches or none are elsewhere.
    public static func elsewhere(_ matches: [String?], current: ConversationKind) -> (kind: ConversationKind, count: Int)? {
        guard current != .all, !matches.contains(where: current.includes) else { return nil }
        let counts = Dictionary(grouping: matches, by: { ConversationKind(source: $0) }).mapValues(\.count)
        guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.rawValue > $1.key.rawValue }) else { return nil }
        return (best.key, best.value)
    }
}
