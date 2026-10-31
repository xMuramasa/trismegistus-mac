import Foundation
import Observation

/// The daily feed runs folded into one read-only News conversation: the `cron` sessions whose final answer is a
/// `news-edition/v1` edition. Only a run's last two messages are fetched (a whole run is ~350 KB of search results),
/// and a run with an edition is never fetched again: finished runs don't change.
@MainActor @Observable
public final class NewsFeed {
    public struct Item: Sendable, Equatable, Identifiable {
        public var id: String { sessionID }
        public let sessionID: String
        /// When the run last wrote (its end, for a finished run), from the session list.
        public let publishedAt: Date?
        public let edition: NewsEdition
    }

    /// Newest first: edition date, then run time.
    public private(set) var items: [Item] = []
    /// The runs the lists show folded into the News row instead of one row each.
    public private(set) var sessionIDs: Set<String> = []

    public let rest: RelayREST
    /// Runs fetched, by id: the edition, or none with the `last_active` it had then (fetched again when that changes,
    /// so a run still going when first seen is checked again once it ends).
    @ObservationIgnored private var checked: [String: (lastActive: Double?, item: Item?)] = [:]
    @ObservationIgnored private var pending: [SessionInfo]?
    @ObservationIgnored private var isRefreshing = false

    public init(rest: RelayREST) {
        self.rest = rest
    }

    /// Call with each new session list. Fetches the runs not seen yet, newest first, publishing each edition as it
    /// arrives; a fetch that fails is tried again on the next refresh. A call during a refresh is picked up after it.
    public func refresh(_ sessions: [SessionInfo]) async {
        pending = sessions
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        while let sessions = pending {
            pending = nil
            let runs = sessions.filter { $0.source == "cron" }
                .sorted { ($0.lastActive ?? $0.startedAt ?? 0) > ($1.lastActive ?? $1.startedAt ?? 0) }
            for run in runs {
                if let seen = checked[run.id], seen.item != nil || seen.lastActive == run.lastActive { continue }
                guard let page = try? await rest.latestMessages(run.id, limit: 2) else { continue }
                let edition = page.last { $0.role == .assistant }.flatMap { NewsEdition.parse($0.content) }
                let at = (run.lastActive ?? run.startedAt).map(Date.init(timeIntervalSince1970:))
                checked[run.id] = (run.lastActive, edition.map { Item(sessionID: run.id, publishedAt: at, edition: $0) })
                if edition != nil { publish() }
            }
        }
    }

    private func publish() {
        items = checked.values.compactMap(\.item).sorted { a, b in
            (a.edition.editionDate, a.publishedAt ?? .distantPast, a.sessionID)
                > (b.edition.editionDate, b.publishedAt ?? .distantPast, b.sessionID)
        }
        sessionIDs = Set(items.map(\.sessionID))
    }
}
