import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// Resources/news/reader-*.json: real reader answers (the list cut to 5 editions, each edition to a few stories).
let readerEditions = [
    "cyber-20261031-031943": "reader-cyber.json", "chile-20261031-031017": "reader-chile.json",
    "ai-20261031-030727": "reader-ai.json",
]

/// The reader at `https://reader.invalid/`: the list, the three full editions, the feeds; anything else is a 404.
func readerHTTP() -> FakeHTTP {
    FakeHTTP { request in
        let path = request.url!.path
        let file = switch path {
        case "/api/feeds": "reader-feeds.json"
        case "/api/editions": "reader-list.json"
        default: readerEditions[request.url!.lastPathComponent].flatMap { path.hasPrefix("/api/editions/") ? $0 : nil }
        }
        return file.map { (200, try! newsResource($0)) } ?? (404, #"{"error":"not_found"}"#)
    }
}

/// No answer at all, like the reader off the tailnet.
final class DownHTTP: HTTPTransport {
    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw URLError(.cannotConnectToHost) }
}

let readerURL = URL(string: "https://reader.invalid/")!

@Suite struct NewsReaderTests {
    @Test func decodesList() async throws {
        let http = readerHTTP()
        let list = try await NewsReaderClient(baseURL: readerURL, http: http).editions()
        #expect(list.map(\.id) == ["cyber-20261031-031943", "chile-20261031-031017", "ai-20261031-030727", "chile-20261030-031316", "cyber-20261030-031239"])
        let first = try #require(list.first)
        #expect(first.feed == "cyber" && first.editionDate == "2026-10-31" && first.title == "Cyber — Saturday, 31 October 2026")
        #expect(first.lead.hasPrefix("Binance") && first.storyCount == 16 && first.stories.isEmpty)
        #expect(first.runAt == Date(timeIntervalSince1970: 1_793_427_583)) // 2026-10-31T06:19:43.000Z
        let url = try #require(http.requests.current.first?.url)
        #expect(http.requests.current.count == 1 && url.absoluteString == "https://reader.invalid/api/editions?limit=100")
    }

    @Test func followsNext() async throws {
        let list = try newsResource("reader-list.json")
        let all = try #require(try JSONSerialization.jsonObject(with: Data(list.utf8)) as? [String: Any])["editions"] as! [Any]
        func page(_ items: ArraySlice<Any>) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["editions": Array(items), "next": "c2"]), as: UTF8.self)
        }
        let (one, two) = (try page(all[..<2]), try page(all[2...]))
        // Page 2 hands back its own cursor: a loop the client must not follow.
        let http = FakeHTTP { request in (200, request.url!.query!.contains("before=") ? two : one) }
        let editions = try await NewsReaderClient(baseURL: readerURL, http: http).editions()
        #expect(editions.count == 5)
        #expect(http.requests.current.map { $0.url!.query } == ["limit=100", "limit=100&before=c2"])
    }

    @Test func decodesEditions() async throws {
        let reader = NewsReaderClient(baseURL: readerURL, http: readerHTTP())
        let cyber = try await reader.edition("cyber-20261031-031943")
        #expect(cyber.id == "cyber-20261031-031943" && cyber.storyCount == 16 && cyber.stories.count == 4)
        #expect(cyber.stories.map(\.section) == ["patch_now", "patch_now", "top", "chile_latam"])
        #expect(cyber.stories.map(\.isUpdate) == [false, true, false, false])
        #expect(cyber.stories[0].cves == ["CVE-2026-111357", "CVE-2026-118527", "CVE-2026-104935"] && cyber.stories[2].cves.isEmpty)
        #expect(cyber.stories.allSatisfy { !$0.favorite && !$0.sources.isEmpty })
        #expect(cyber.stories.map { $0.action != nil } == [true, true, false, true])
        #expect(cyber.markets.isEmpty && !cyber.gaps.isEmpty)

        let chile = try await reader.edition("chile-20261031-031017")
        #expect(chile.stories.first?.isUpdate == true && chile.stories.first?.coverage.map(\.group) == ["right", "center", "left", "independent", "foreign"])
        #expect(chile.marketsAsOf == "2026-10-30" && chile.markets.map(\.change) == ["-2.76%", "n/a", "+0.24% (week)"])

        let ai = try await reader.edition("ai-20261031-030727")
        #expect(ai.stories.map(\.section) == ["top", "release"] && ai.sectionTitle("release") == "Model & product releases")

        let starred = #"{"section":"top","headline":"H","summary":"S","favorite":true,"is_update":"yes","cves":["CVE-1",3,""]}"#
        let story = try Wire.decode(NewsEdition.Story.self, from: Data(starred.utf8))
        #expect(story.favorite && !story.isUpdate && story.cves == ["CVE-1"])
    }

    @Test func decodesFeedsAndOrdersSections() async throws {
        let feeds = try await NewsReaderClient(baseURL: readerURL, http: readerHTTP()).feeds()
        #expect(feeds.map(\.id) == ["chile", "cyber", "ai"])
        #expect(feeds[1].sections.first == NewsEdition.Section(id: "patch_now", title: "Patch now") && feeds[1].sections.count == 6)

        var cyber = try await NewsReaderClient(baseURL: readerURL, http: readerHTTP()).edition("cyber-20261031-031943")
        cyber.sections = feeds[1].sections.reversed()
        #expect(cyber.stories.map(\.section) == ["chile_latam", "top", "patch_now", "patch_now"])
        #expect(cyber.stories[2].rank == 1 && cyber.sectionTitle("chile_latam") == "Chile & LatAm")
    }

    @Test func errors() async throws {
        await #expect(throws: NewsReaderError.unreachable) { try await NewsReaderClient(baseURL: readerURL, http: DownHTTP()).feeds() }
        let broken = FakeHTTP { $0.url!.path == "/api/feeds" ? (502, "Bad Gateway") : (200, "<html>") }
        await #expect(throws: NewsReaderError.badResponse) { try await NewsReaderClient(baseURL: readerURL, http: broken).feeds() }
        await #expect(throws: NewsReaderError.badResponse) { try await NewsReaderClient(baseURL: readerURL, http: broken).editions() }
        let http = readerHTTP()
        await #expect(throws: NewsReaderError.badResponse) { try await NewsReaderClient(baseURL: readerURL, http: http).edition("../feeds") }
        await #expect(throws: NewsReaderError.badResponse) { try await NewsReaderClient(baseURL: readerURL, http: http).edition("nope") }
        #expect(http.requests.current.map(\.url!.path) == ["/api/editions/nope"]) // the bad id never left
    }
}
