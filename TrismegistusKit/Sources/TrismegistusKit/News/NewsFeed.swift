import Foundation
import Observation

/// The News conversation. With a reader (#24) its editions come from the news reader: the summaries, newest first,
/// refreshed on demand and every 10 minutes, and each full edition fetched when shown and cached by id. Without one,
/// from the daily feed runs (#19). Either way the feed runs are found and folded into the News row: the `cron` sessions
/// whose final answer is a `news-edition/v1` edition. Only a run's last two messages are fetched (a whole run is
/// ~350 KB of search results), and a run with an edition is never fetched again: finished runs don't change.
@MainActor @Observable
public final class NewsFeed {
    public struct Item: Sendable, Equatable, Identifiable {
        /// The reader's edition id, or the run's session id.
        public let id: String
        /// When the run wrote it: the reader's `run_at`, or the run's last activity from the session list.
        public let publishedAt: Date?
        /// A summary from the reader (no stories: see `edition(for:)`), or the run's whole edition.
        public let edition: NewsEdition
    }

    /// Newest first: edition date, then run time.
    public var items: [Item] { reader == nil ? runItems : readerItems }
    /// The runs the lists show folded into the News row instead of one row each.
    public private(set) var sessionIDs: Set<String> = []
    /// Nil disables the reader: the editions come from the runs.
    public private(set) var reader: NewsReaderClient?
    /// The last reader call failed; the items and editions it had stay.
    public private(set) var readerError: NewsReaderError?

    public let rest: RelayREST
    private var runItems: [Item] = []
    private var readerItems: [Item] = []
    /// Full editions from the reader, by id.
    private var editions: [String: NewsEdition] = [:]
    /// Sections per feed from `/api/feeds`.
    @ObservationIgnored private var feeds: [String: [NewsEdition.Section]] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    /// The reader whose summaries are being fetched.
    @ObservationIgnored private var listing: URL?
    /// Runs fetched, by id: the edition, or none with the `last_active` it had then (fetched again when that changes,
    /// so a run still going when first seen is checked again once it ends).
    @ObservationIgnored private var checked: [String: (lastActive: Double?, item: Item?)] = [:]
    @ObservationIgnored private var pending: [SessionInfo]?
    @ObservationIgnored private var isRefreshing = false

    public init(rest: RelayREST) {
        self.rest = rest
        // Ends once the feed is dropped (a disconnect replaces it).
        Task { [weak self] in
            while (try? await Task.sleep(for: .seconds(600))) != nil {
                guard let self else { return }
                await self.refreshEditions()
            }
        }
    }

    /// The reader to use; a different URL starts over, the same one keeps what was fetched.
    public func setReader(_ reader: NewsReaderClient?) {
        let changed = reader?.baseURL != self.reader?.baseURL
        self.reader = reader
        guard changed else { return }
        readerItems = []
        editions = [:]
        feeds = [:]
        readerError = nil
    }

    /// The whole edition: the reader's once `load` fetched it (nil until then), a run's as it came.
    public func edition(for item: Item) -> NewsEdition? {
        reader == nil ? item.edition : editions[item.id]
    }

    /// Fetches the reader's edition summaries (and its feeds' sections, once). A call during one for the same reader
    /// is dropped; one for a new reader (the URL edited in Settings) goes ahead.
    public func refreshEditions() async {
        guard let reader, listing != reader.baseURL else { return }
        listing = reader.baseURL
        defer { if listing == reader.baseURL { listing = nil } }
        do throws(NewsReaderError) {
            // Sections are a nicety: without them the built-in table orders the stories.
            if feeds.isEmpty, let list = try? await reader.feeds() {
                feeds = Dictionary(list.map { ($0.id, $0.sections) }, uniquingKeysWith: { a, _ in a }).filter { !$0.value.isEmpty }
                for (id, edition) in editions { editions[id] = sectioned(edition) }
            }
            let list = try await reader.editions()
            guard reader.baseURL == self.reader?.baseURL else { return }
            readerItems = Self.newestFirst(list.compactMap { e in e.id.map { Item(id: $0, publishedAt: e.runAt, edition: e) } })
            readerError = nil
        } catch {
            if reader.baseURL == self.reader?.baseURL { readerError = error }
        }
    }

    /// Fetches a reader edition not fetched yet; a failure is tried again on the next call.
    public func load(_ id: String) async {
        guard let reader, editions[id] == nil, !loading.contains(id) else { return }
        loading.insert(id)
        defer { loading.remove(id) }
        do throws(NewsReaderError) {
            let edition = try await reader.edition(id)
            guard reader.baseURL == self.reader?.baseURL else { return }
            editions[id] = sectioned(edition)
        } catch {
            if reader.baseURL == self.reader?.baseURL { readerError = error }
        }
    }

    private func sectioned(_ edition: NewsEdition) -> NewsEdition {
        var edition = edition
        if let sections = feeds[edition.feed] { edition.sections = sections }
        return edition
    }

    /// Call with each new session list: refreshes the reader's summaries, then fetches the runs not seen yet, newest
    /// first, publishing each edition as it arrives; a fetch that fails is tried again on the next refresh. A call
    /// during a refresh is picked up after it.
    public func refresh(_ sessions: [SessionInfo]) async {
        await refreshEditions()
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
                checked[run.id] = (run.lastActive, edition.map { Item(id: run.id, publishedAt: at, edition: $0) })
                if edition != nil { publish() }
            }
        }
    }

    private func publish() {
        runItems = Self.newestFirst(checked.values.compactMap(\.item))
        sessionIDs = Set(runItems.map(\.id))
    }

    private static func newestFirst(_ items: [Item]) -> [Item] {
        items.sorted { a, b in
            (a.edition.editionDate, a.publishedAt ?? .distantPast, a.id) > (b.edition.editionDate, b.publishedAt ?? .distantPast, b.id)
        }
    }
}
