import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// NewsFeed against FakeHTTP serving each run's `limit=2&order=latest` page.
@MainActor @Suite struct NewsFeedTests {
    /// The final answer of each fake run; a missing id answers 500.
    nonisolated static let answers: [String: String] = [
        "cron_aaa_1": edition(feed: "ai", date: "2026-10-31"),
        "cron_ccc_1": "```json\n" + edition(feed: "chile", date: "2026-10-31") + "\n```",
        "cron_ddd_1": edition(feed: "cyber", date: "2026-10-30"),
        "cron_eee_1": "I couldn't write the edition: web_search is rate-limited.",
    ]

    nonisolated static func edition(feed: String, date: String) -> String {
        #"{"schema":"news-edition/v1","feed":"\#(feed)","edition_date":"\#(date)","title":"\#(feed) \#(date)","lead":"L","stories":[{"section":"top","rank":1,"headline":"H","summary":"S"}]}"#
    }

    nonisolated static func page(_ answer: String) -> String {
        let content = String(decoding: try! JSONEncoder().encode(answer), as: UTF8.self)
        return #"{"object":"list","data":[{"id":1,"role":"tool","content":"…","tool_call_id":"t1"},{"id":2,"role":"assistant","content":\#(content)}]}"#
    }

    func feed() -> (NewsFeed, FakeHTTP) {
        let http = FakeHTTP { request in
            let id = request.url!.pathComponents.dropLast().last!
            return Self.answers[id].map { (200, Self.page($0)) } ?? (500, "oops")
        }
        return (NewsFeed(rest: RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http)), http)
    }

    func fetched(_ http: FakeHTTP) -> [String] { http.requests.current.compactMap { $0.url?.pathComponents.dropLast().last } }

    let sessions = [
        SessionInfo(id: "api_1", source: "api_server", lastActive: 900),
        SessionInfo(id: "cron_ccc_1", source: "cron", startedAt: 100, lastActive: 200), // chile, earlier the same day
        SessionInfo(id: "cron_eee_1", source: "cron", lastActive: 150), // failed run
        SessionInfo(id: "cron_aaa_1", source: "cron", startedAt: 100, lastActive: 300),
        SessionInfo(id: "cron_ddd_1", source: "cron", lastActive: 400), // newer run, older edition date
        SessionInfo(id: "cron_bbb_1", source: "cron", lastActive: 50), // the relay errors
        SessionInfo(id: "tg_1", source: "telegram", lastActive: 800),
    ]

    @Test func buildsNewestFirstAndSkipsRunsWithoutEdition() async throws {
        let (news, http) = feed()
        await news.refresh(sessions)
        #expect(news.items.map(\.sessionID) == ["cron_aaa_1", "cron_ccc_1", "cron_ddd_1"])
        #expect(news.items.map(\.edition.tag) == ["AI", "CHILE", "CYBER"])
        #expect(news.items[0].publishedAt == Date(timeIntervalSince1970: 300))
        #expect(news.sessionIDs == ["cron_aaa_1", "cron_ccc_1", "cron_ddd_1"])
        // Only cron sessions, most recent first, with the small page.
        #expect(fetched(http) == ["cron_ddd_1", "cron_aaa_1", "cron_ccc_1", "cron_eee_1", "cron_bbb_1"])
        let url = try #require(http.requests.current.first?.url)
        #expect(url.path == "/api/sessions/cron_ddd_1/messages" && url.query == "limit=2&order=latest")
    }

    @Test func cachesFinishedRuns() async {
        let (news, http) = feed()
        await news.refresh(sessions)
        let first = http.requests.current.count
        await news.refresh(sessions)
        // Editions and the unchanged failed run are cached; only the run the relay failed is tried again.
        #expect(fetched(http).dropFirst(first) == ["cron_bbb_1"])

        var later = sessions
        later[2].lastActive = 500 // the "failed" run was still going: check it again
        later.append(SessionInfo(id: "cron_fff_1", source: "cron", lastActive: 600)) // a new run (500 for now)
        await news.refresh(later)
        #expect(fetched(http).dropFirst(first + 1) == ["cron_fff_1", "cron_eee_1", "cron_bbb_1"])
        #expect(news.items.count == 3)
    }

    @Test func refreshDuringRefreshIsPickedUp() async {
        let (news, http) = feed()
        async let a: Void = news.refresh(Array(sessions.prefix(2)))
        async let b: Void = news.refresh(sessions)
        _ = await (a, b) // the one that came second either ran alone or was picked up by the first
        #expect(news.items.count == 3)
        let ok = fetched(http).filter { $0 != "cron_bbb_1" }
        #expect(Set(ok).count == ok.count) // never fetched twice
    }

    @Test func noCronSessionsNoRequests() async {
        let (news, http) = feed()
        await news.refresh([SessionInfo(id: "api_1", source: "api_server"), SessionInfo(id: "x_1")])
        #expect(news.items.isEmpty && news.sessionIDs.isEmpty && http.requests.current.isEmpty)
    }
}
