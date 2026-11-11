import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// Message search (#76): the REST call, the store's debounce, supersede and grouping, find's stepping, and the earlier
/// pages a hit can need.
@MainActor @Suite struct SearchTests {
    /// The relay's answer for `q=android`: two hits in one conversation, one in another (newest first).
    nonisolated static let page = #"""
        {"results":[
          {"session_id":"api_1","message_id":907,"role":"assistant","timestamp":1793000300.5,"snippet":"…using the Android 37 image Android Studio","marks":[[12,7],[28,7]],"session_title":"Android app","session_source":"api_server"},
          {"session_id":"cli_2","message_id":55,"role":"user","timestamp":1793000200,"snippet":"does android build?","marks":[[5,7],[90,3]],"session_title":null,"session_source":"cli"},
          {"session_id":"api_1","message_id":901,"role":"user","timestamp":1793000100,"snippet":"android?","marks":[[0,7]],"session_title":"Android app","session_source":"api_server"},
          {"session_id":"bad"}
        ],"more":true}
        """#

    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: relayURL, token: fakeToken, http: http), http)
    }

    @Test func searchCallsTheRelayAndDecodesHits() async throws {
        let (api, http) = rest { _ in (200, Self.page) }
        let page = try await api.search("c++ android", limit: 50)
        #expect(page.more)
        #expect(page.results.map(\.messageID) == [907, 55, 901]) // the malformed one is skipped
        #expect(page.results[0].marks == [NSRange(location: 12, length: 7), NSRange(location: 28, length: 7)])
        #expect(page.results[1].marks == [NSRange(location: 5, length: 7)]) // past the snippet's end: dropped
        #expect(page.results[1].sessionTitle == nil && page.results[1].sessionSource == "cli")
        let url = try #require(http.requests.current.first?.url)
        #expect(url.path == "/api/search")
        #expect(url.query == "q=c%2B%2B%20android&limit=50")
    }

    @Test func groupsByConversationNewestFirst() throws {
        let page = try Wire.decode(SearchPage.self, from: Data(Self.page.utf8))
        let groups = MessageSearch.group(page.results)
        #expect(groups.map(\.id) == ["api_1", "cli_2"])
        #expect(groups.map(\.count) == [2, 1])
        #expect(groups[0].newest.messageID == 907)
    }

    /// Typing `a`, `an`, `and`, `andr` searches once, 300 ms after the last keystroke, for `andr`.
    @Test func debouncesAndStartsAtTwoCharacters() async {
        let clock = TestClock()
        let (api, http) = rest { _ in (200, Self.page) }
        let search = MessageSearch(rest: api, sleep: { try await clock.sleep(for: $0) })
        search.update(" a ")
        #expect(search.phase == .idle && search.query == "a")
        search.update("an")
        #expect(search.phase == .searching)
        search.update("and")
        search.update("andr")
        await clock.fire(MessageSearch.debounce)
        await http.requests.wait { $0.count == 1 }
        await waitFor { search.phase == .results }
        #expect(http.requests.current.count == 1)
        #expect(http.requests.current[0].url?.query == "q=andr&limit=50")
        #expect(search.conversations.map(\.id) == ["api_1", "cli_2"] && search.more)
        // Back to one character: titles only, nothing asked.
        search.update("a")
        #expect(search.phase == .idle && search.conversations.isEmpty)
    }

    /// Typing on after results keeps the cards until the next answer replaces them (Hermes' review: clearing them per
    /// keystroke made the list flash empty while typing).
    @Test func cardsStayWhileTheNextSearchRuns() async {
        let clock = TestClock()
        let (api, http) = rest { _ in (200, Self.page) }
        let search = MessageSearch(rest: api, sleep: { try await clock.sleep(for: $0) })
        search.update("andr")
        await clock.fire(MessageSearch.debounce)
        await waitFor { search.phase == .results }
        search.update("andro")
        #expect(search.phase == .searching)
        #expect(search.conversations.map(\.id) == ["api_1", "cli_2"] && search.more)
        await clock.fire(MessageSearch.debounce)
        await http.requests.wait { $0.count == 2 }
        await waitFor { search.phase == .results }
        #expect(search.query == "andro")
    }

    /// A newer search cancels the older; the relay answers the older 409 busy, which never shows.
    @Test func theNewestSearchWins() async {
        let clock = TestClock()
        let http = GatedHTTP()
        let api = RelayREST(baseURL: relayURL, token: fakeToken, http: http)
        let search = MessageSearch(rest: api, sleep: { try await clock.sleep(for: $0) })
        search.update("old")
        await clock.fire(MessageSearch.debounce)
        await http.requests.wait { $0.count == 1 } // in flight, held at the gate
        search.update("zebra")
        #expect(search.phase == .searching)
        await clock.fire(MessageSearch.debounce)
        await http.requests.wait { $0.count == 2 }
        await waitFor { search.phase != .searching }
        #expect(search.phase == .none && search.query == "zebra")
        http.open.mutate { $0 = true } // the old one's 409 busy arrives late
        await http.answered.wait { $0 == 2 }
        await waitFor { false }
        #expect(search.phase == .none)
    }

    @Test func helperDownAndFailures() async {
        let clock = TestClock()
        let (down, _) = rest { _ in (503, #"{"error":{"code":"hermes_unavailable","message":"search needs the agents helper"}}"#) }
        let search = MessageSearch(rest: down, sleep: { try await clock.sleep(for: $0) })
        search.update("android")
        await clock.fire(MessageSearch.debounce)
        await waitFor { search.phase != .searching }
        #expect(search.phase == .unavailable)

        let (broken, _) = rest { _ in (502, #"{"error":{"code":"hermes_error","message":"search failed"}}"#) }
        let other = MessageSearch(rest: broken, sleep: { try await clock.sleep(for: $0) })
        other.update("android")
        await clock.fire(MessageSearch.debounce)
        await waitFor { other.phase != .searching }
        #expect(other.phase == .failed("search failed"))
    }

    @Test func findStepsWrapAndKeepTheirPlace() {
        var steps = FindSteps(counts: [("h-1", 2), ("h-2", 0), ("h-3", 1)])
        #expect(steps.total == 3 && steps.position == 1)
        #expect(steps.match == .init(itemID: "h-1", index: 0))
        steps.next()
        #expect(steps.currentIndex(in: "h-1") == 1 && steps.currentIndex(in: "h-3") == nil)
        steps.next()
        #expect(steps.match == .init(itemID: "h-3", index: 0))
        steps.next() // wraps to the first
        #expect(steps.position == 1)
        steps.previous() // and back to the last
        #expect(steps.position == 3)
        // A new row before it (the transcript grew) keeps the current match on its row.
        let grown = FindSteps(counts: [("h-0", 1), ("h-1", 2), ("h-3", 1)], keeping: steps)
        #expect(grown.match == .init(itemID: "h-3", index: 0) && grown.position == 4)
        // A hit opened: its row's first match.
        var opened = FindSteps(counts: [("h-1", 2), ("h-3", 1)])
        let found = opened.select(itemID: "h-3")
        #expect(found && opened.position == 3)
        let missing = opened.select(itemID: "h-9")
        #expect(!missing && opened.position == 3)
        var none = FindSteps(counts: [("h-1", 0)])
        none.next()
        #expect(none.position == nil && none.total == 0)
    }

    /// The window has the last messages (here 3 to 5); a hit in message 2 fetches the pages before them.
    @Test func loadsEarlierPagesUntilTheHit() async throws {
        func page(_ ids: ClosedRange<Int>) -> String {
            #"{"data":["# + ids.map { #"{"id":\#($0),"role":"user","content":"m\#($0)"}"# }.joined(separator: ",") + "]}"
        }
        let (all, window) = (page(1...5), page(3...5))
        let http = FakeHTTP { r in (200, r.url?.query?.contains("offset=0") == true ? all : window) }
        let clock = TestClock()
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: FakeTransport(), sleep: { try await clock.sleep(for: $0) })
        let store = SessionStore(client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http))
        await store.open("s1")
        #expect(store.sessions["s1"]?.history.map(\.id) == ["3", "4", "5"])
        #expect(await store.loadEarlier("s1", through: "2"))
        #expect(store.sessions["s1"]?.history.map(\.id) == ["1", "2", "3", "4", "5"])
        let query = try #require(http.requests.current.last?.url?.query)
        #expect(query == "limit=\(SessionStore.earlierPage)&offset=0&order=oldest")
        // Loaded already: nothing fetched. A reload of the window's page keeps the earlier ones.
        let asked = http.requests.current.count
        #expect(await store.loadEarlier("s1", through: "4"))
        #expect(http.requests.current.count == asked)
        await store.loadHistory("s1")
        #expect(store.sessions["s1"]?.history.map(\.id) == ["1", "2", "3", "4", "5"])
        #expect(ChatTimeline.items(store.sessions["s1"]!, compact: false).first?.id == "h-1")
    }

    /// Polls the main actor until `check` holds (the store's task finishes on it).
    private func waitFor(_ check: () -> Bool) async {
        for _ in 0..<1000 where !check() { await Task.yield() }
    }
}

/// Holds searches for `old` until `open`, then answers them 409 busy (the relay's answer to a superseded search); the
/// others get no results at once.
final class GatedHTTP: HTTPTransport {
    let requests = Watched<[URLRequest]>([])
    let open = Watched(false)
    let answered = Watched(0)

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.mutate { $0.append(request) }
        let old = request.url?.query?.hasPrefix("q=old") == true
        if old { await open.wait { $0 } }
        defer { answered.mutate { $0 += 1 } }
        let (status, body) = old
            ? (409, #"{"error":{"code":"busy","message":"a newer search replaced this one"}}"#) : (200, #"{"results":[],"more":false}"#)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}
