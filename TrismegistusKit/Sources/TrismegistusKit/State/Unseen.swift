import Foundation

/// Runs that ended while nobody looked (#66): a done or failed mark per conversation, local to this Mac, until the
/// conversation is opened. Failed outranks done and stays when a later run finishes. A pure value the app persists.
public struct Unseen: Codable, Sendable, Equatable {
    public enum Mark: Int, Codable, Sendable, Comparable {
        case done = 1, failed

        public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// A conversation that changed this long after the last tracked moment counts as changed while the app was quit.
    public static let catchUpSlack: TimeInterval = 5

    public private(set) var marks: [String: Mark] = [:]
    /// The last moment the app was known to follow the relay; nil until the first launch has caught up.
    public private(set) var trackedUntil: Date?

    public init() {}

    /// The strongest mark among the conversations.
    public var strongest: Mark? { marks.values.max() }

    /// The strongest mark among `ids` (a thread's parts).
    public func mark(_ ids: some Sequence<String>) -> Mark? {
        ids.compactMap { marks[$0] }.max()
    }

    /// A run in `session` ended with `status`. Returns what it says (done or failed) when nobody watched it: the caller
    /// sounds it. A cancelled run, or one watched while it ended, leaves nothing.
    @discardableResult
    public mutating func runEnded(session: String, status: RunStatus, watched: Bool) -> Mark? {
        let mark: Mark
        switch status {
        case .completed: mark = .done
        case .failed: mark = .failed
        default: return nil
        }
        guard !watched else { return nil }
        add(mark, to: session)
        return mark
    }

    /// The conversation was opened: its thread's parts lose their marks.
    public mutating func viewed(_ ids: some Sequence<String>) {
        for id in ids { marks[id] = nil }
    }

    /// After a time the app couldn't follow (quit, asleep, disconnected), at the first list load: app conversations
    /// (`api_server`) active since the last tracked moment changed meanwhile and get a done mark, unless watched or
    /// still running (their run's end marks them when it comes). The first launch ever marks nothing. Call
    /// `tracked(at:)` after it.
    public mutating func catchUp(_ list: [SessionInfo], watched: Set<String> = [], running: Set<String> = []) {
        guard let trackedUntil else { return }
        let since = trackedUntil.timeIntervalSince1970 + Self.catchUpSlack
        for info in list where info.source == "api_server" && (info.lastActive ?? 0) > since
            && !watched.contains(info.id) && !running.contains(info.id) {
            add(.done, to: info.id)
        }
    }

    /// `trackedUntil` this far behind `now` means the app stopped following for a while (it moves every 30 s while
    /// connected): the next list load catches up on that gap too.
    public static let gap: TimeInterval = 75

    /// Whether the app lost track after the launch's catch-up (asleep, disconnected) and should catch up again.
    public func lostTrack(at now: Date) -> Bool {
        guard let trackedUntil else { return false }
        return now.timeIntervalSince(trackedUntil) > Self.gap
    }

    /// The app followed the relay up to `date`.
    public mutating func tracked(at date: Date) {
        trackedUntil = date
    }

    /// Drops the marks of conversations that left the list.
    public mutating func prune(keeping ids: Set<String>) {
        marks = marks.filter { ids.contains($0.key) }
    }

    private mutating func add(_ mark: Mark, to id: String) {
        marks[id] = max(marks[id] ?? mark, mark)
    }
}

/// Keeps run sounds apart (#66): at most one finished or failed sound per `spacing`; approval sounds always play and
/// don't hold the gate.
public struct SoundGate: Sendable {
    public static let spacing: TimeInterval = 2

    private var last: Date?

    public init() {}

    /// Whether a sound may play at `now`; an allowed run sound closes the gate for `spacing`.
    public mutating func allows(approval: Bool, at now: Date) -> Bool {
        if approval { return true }
        if let last, now.timeIntervalSince(last) < Self.spacing { return false }
        last = now
        return true
    }
}
