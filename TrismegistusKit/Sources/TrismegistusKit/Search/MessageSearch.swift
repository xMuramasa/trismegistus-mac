import Foundation
import Observation

/// One message that matched a search (`GET /api/search`): yours or Hermes' answer, never a tool call.
public struct SearchHit: Decodable, Sendable, Equatable {
    public var sessionID: String
    /// Hermes' message id: the chat's row is `h-<messageID>`.
    public var messageID: Int64
    public var role: String
    /// Unix seconds.
    public var timestamp: Double
    /// About 60 characters before the first match and 120 after, whitespace collapsed, `…` where cut.
    public var snippet: String
    /// Every match in `snippet`, in UTF-16 code units (ranges on `snippet as NSString`).
    public var marks: [NSRange]
    public var sessionTitle: String?
    /// `api_server`, `telegram`, `cron`, `cli`, …
    public var sessionSource: String?

    public var date: Date { Date(timeIntervalSince1970: timestamp) }

    public init(
        sessionID: String, messageID: Int64, role: String = "assistant", timestamp: Double, snippet: String,
        marks: [NSRange] = [], sessionTitle: String? = nil, sessionSource: String? = nil
    ) {
        self.sessionID = sessionID
        self.messageID = messageID
        self.role = role
        self.timestamp = timestamp
        self.snippet = snippet
        self.marks = marks
        self.sessionTitle = sessionTitle
        self.sessionSource = sessionSource
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", messageID = "message_id", role, timestamp, snippet, marks
        case sessionTitle = "session_title", sessionSource = "session_source"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(String.self, forKey: .sessionID)
        messageID = try c.decode(Int64.self, forKey: .messageID)
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? "assistant"
        timestamp = try c.decodeIfPresent(Double.self, forKey: .timestamp) ?? 0
        snippet = try c.decodeIfPresent(String.self, forKey: .snippet) ?? ""
        // Marks outside the snippet are dropped: the card sets them on the text as they come.
        let length = (snippet as NSString).length
        marks = ((try? c.decodeIfPresent([[Int]].self, forKey: .marks)) ?? []).compactMap { pair in
            guard pair.count == 2, pair[0] >= 0, pair[1] > 0, pair[0] + pair[1] <= length else { return nil }
            return NSRange(location: pair[0], length: pair[1])
        }
        sessionTitle = try? c.decodeIfPresent(String.self, forKey: .sessionTitle)
        sessionSource = try? c.decodeIfPresent(String.self, forKey: .sessionSource)
    }
}

/// One page of search results; `more`: there were more matches than the limit.
public struct SearchPage: Decodable, Sendable, Equatable {
    public var results: [SearchHit]
    public var more: Bool

    enum CodingKeys: String, CodingKey { case results, more }

    public init(results: [SearchHit], more: Bool = false) {
        self.results = results
        self.more = more
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        results = (try c.decodeIfPresent(Lossy<SearchHit>.self, forKey: .results))?.items ?? []
        more = try c.decodeIfPresent(Bool.self, forKey: .more) ?? false
    }
}

/// A conversation with hits: its newest one (the card's preview and time) and how many there were.
public struct SearchConversation: Sendable, Equatable, Identifiable {
    public var newest: SearchHit
    public var count: Int
    public var id: String { newest.sessionID }
}

/// Searching inside every conversation from the chat list's filter (#76): from 2 characters (trimmed), 300 ms after the
/// last keystroke, at most 50 results; the newest request wins (an older one the relay answers 409 `busy` is dropped).
/// The results come grouped by conversation, newest hit first.
@MainActor @Observable
public final class MessageSearch {
    public enum Phase: Sendable, Equatable {
        /// Fewer than 2 characters: titles only.
        case idle
        case searching
        case results
        /// Nothing says it.
        case none
        /// The agents helper on optiplex is down (503 `hermes_unavailable`).
        case unavailable
        case failed(String)
    }

    /// Flip: other numbers here (Hermes' picks, #76).
    nonisolated public static let minLength = 2
    nonisolated public static let debounce: Duration = .milliseconds(300)
    nonisolated public static let limit = 50

    public private(set) var phase = Phase.idle
    /// The trimmed text the phase and the results are for.
    public private(set) var query = ""
    public private(set) var conversations: [SearchConversation] = []
    /// More matches than `limit`: only the newest are shown.
    public private(set) var more = false

    @ObservationIgnored private let rest: RelayREST
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    public init(rest: RelayREST, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.rest = rest
        self.sleep = sleep
    }

    /// The filter's text changed: searches it after the pause, cancelling the search before it.
    public func update(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q != query else { return } // a space typed after a word asks nothing new
        task?.cancel()
        generation += 1
        query = q
        guard q.count >= Self.minLength else {
            conversations = []
            more = false
            phase = .idle
            return
        }
        // The cards found so far stay until the new answer replaces them: clearing them on every keystroke made the
        // list flash empty while typing. The field's spinner says a search is running.
        phase = .searching
        let (rest, sleep, generation) = (rest, sleep, generation)
        task = Task { [weak self] in
            do { try await sleep(Self.debounce) } catch { return }
            let result: Result<SearchPage, any Error>
            do { result = .success(try await rest.search(q, limit: Self.limit)) } catch { result = .failure(error) }
            self?.finish(result, generation: generation)
        }
    }

    private func finish(_ result: Result<SearchPage, any Error>, generation: Int) {
        guard generation == self.generation else { return } // superseded: its 409 busy or its results are stale
        switch result {
        case .success(let page):
            conversations = Self.group(page.results)
            more = page.more
            phase = conversations.isEmpty ? .none : .results
        case .failure(let error as RelayAPIError) where error.code == .hermesUnavailable:
            (conversations, more) = ([], false)
            phase = .unavailable
        case .failure(let error):
            (conversations, more) = ([], false)
            phase = .failed(SessionStore.message(for: error))
        }
    }

    /// One entry per conversation in the order of its newest hit (the results come newest first).
    public static func group(_ hits: [SearchHit]) -> [SearchConversation] {
        var order: [String] = []
        var groups: [String: SearchConversation] = [:]
        for hit in hits {
            if groups[hit.sessionID] == nil {
                order.append(hit.sessionID)
                groups[hit.sessionID] = SearchConversation(newest: hit, count: 0)
            }
            groups[hit.sessionID]?.count += 1
        }
        return order.compactMap { groups[$0] }
    }
}
