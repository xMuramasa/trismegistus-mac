import Foundation
import Observation

/// Every listed conversation's tool calls from the Hermes history, kept in a file so only new messages are fetched:
/// a session is fetched from the count it was cached at (`order=oldest&offset=`), and only when the list says it has
/// more messages than that; sessions without tool calls are never fetched.
@MainActor @Observable
public final class CommandLog {
    struct SessionLog: Codable, Equatable {
        /// Messages fetched: the next page's offset.
        var count = 0
        var entries: [TerminalEntry] = []
    }

    static let pageSize = 200

    /// The cached calls by session id, oldest first.
    private(set) var logs: [String: SessionLog] = [:]

    public let rest: RelayREST
    private let cacheURL: URL?
    @ObservationIgnored private var syncing: Set<String> = []
    @ObservationIgnored private var pending: [SessionInfo]?
    @ObservationIgnored private var isRefreshing = false

    /// Without a cacheURL nothing is kept between launches.
    public init(rest: RelayREST, cacheURL: URL? = nil) {
        self.rest = rest
        self.cacheURL = cacheURL
        // An unreadable or older cache is dropped: everything is fetched again.
        if let cacheURL, let data = try? Data(contentsOf: cacheURL) {
            logs = (try? JSONDecoder().decode([String: SessionLog].self, from: data)) ?? [:]
        }
    }

    /// One conversation's calls, oldest first.
    public func entries(of sessionID: String) -> [TerminalEntry] { logs[sessionID]?.entries ?? [] }

    /// Every conversation's calls, newest first (a message's later calls first: their ids are lower).
    public var all: [TerminalEntry] { logs.values.flatMap(\.entries).sorted { ($0.time, -$0.id) > ($1.time, -$1.id) } }

    /// Call with each new session list: forgets the sessions no longer listed and fetches the new messages of those
    /// that grew, most recent first. A call during a refresh is picked up after it.
    public func refresh(_ sessions: [SessionInfo]) async {
        pending = sessions
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var changed = false
        while let sessions = pending {
            pending = nil
            let listed = Set(sessions.map(\.id))
            if logs.keys.contains(where: { !listed.contains($0) }) {
                logs = logs.filter { listed.contains($0.key) }
                changed = true
            }
            let byRecency = sessions.sorted { ($0.lastActive ?? $0.startedAt ?? 0) > ($1.lastActive ?? $1.startedAt ?? 0) }
            for s in byRecency where (s.toolCallCount ?? 1) > 0 && s.messageCount != (logs[s.id]?.count ?? 0) {
                if await fetch(s.id, expected: s.messageCount) { changed = true }
            }
        }
        if changed { await save() }
    }

    /// Fetches one session's messages after the cached ones, whatever the list says: the terminal pane, every few
    /// seconds while it shows a conversation that may be running elsewhere.
    public func sync(_ sessionID: String) async {
        if await fetch(sessionID, expected: nil) { await save() }
    }

    /// Returns whether the session's log changed. A failed page keeps the pages before it; the rest is fetched next time.
    private func fetch(_ id: String, expected: Int?) async -> Bool {
        guard syncing.insert(id).inserted else { return false }
        defer { syncing.remove(id) }
        let before = logs[id]
        var log = before ?? SessionLog()
        // Fewer messages than cached: the history was rewritten (compressed), start over.
        if let expected, expected < log.count { log = SessionLog() }
        while let page = try? await rest.messages(id, offset: log.count, limit: Self.pageSize) {
            log.entries = await Self.entries(fromHistory: page.messages, sessionID: id, after: log.entries)
            log.count += page.count
            logs[id] = log
            if page.count < Self.pageSize { break }
        }
        return logs[id] != before
    }

    /// Off the main actor: a page of long outputs takes a while to read, and the window may be animating a pane.
    @concurrent nonisolated private static func entries(
        fromHistory messages: [HistoryMessage], sessionID: String, after previous: [TerminalEntry]
    ) async -> [TerminalEntry] {
        TerminalTranscript.entries(fromHistory: messages, sessionID: sessionID, after: previous)
    }

    private func save() async {
        guard let cacheURL else { return }
        await Self.write(logs, to: cacheURL)
    }

    // shortcut: rewrites the whole file after each refresh (a few MB at most, other tools' results are cut); a refresh
    // and a pane sync saving at once may land out of order, which only makes the next launch fetch a page again.
    @concurrent nonisolated private static func write(_ logs: [String: SessionLog], to cacheURL: URL) async {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
    }
}
