import Foundation
import Testing
@testable import TrismegistusKit

/// Resources/news/: the news reader's three valid fixtures and a trimmed `limit=2&order=latest` page of a real run.
func newsResource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/news/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite struct NewsEditionTests {
    @Test func readerFixturesDecode() throws {
        for (feed, stories, firstSection) in [("ai", 15, "top"), ("chile", 11, "top"), ("cyber", 22, "patch_now")] {
            let edition = try #require(NewsEdition.parse(try newsResource("\(feed).valid.json")))
            #expect(edition.feed == feed && edition.tag == feed.uppercased())
            #expect(!edition.title.isEmpty && !edition.lead.isEmpty && edition.editionDate.count == 10)
            #expect(edition.stories.count == stories)
            #expect(edition.stories.first?.section == firstSection && edition.stories.first?.rank == 1)
            #expect(!edition.gaps.isEmpty)
        }
    }

    @Test func storyFields() throws {
        let chile = try #require(NewsEdition.parse(try newsResource("chile.valid.json")))
        let quiroz = chile.stories[2]
        #expect(quiroz.headline.hasPrefix("Quiroz"))
        #expect(quiroz.blindspot == "I found no left-leaning coverage of the speech.")
        #expect(quiroz.coverage.map(\.group) == ["right", "center", "left"] && quiroz.coverage[2].covered == false)
        #expect(quiroz.framing.count == 2 && quiroz.details.first?.label == "Context")
        #expect(quiroz.sources.map(\.url?.host) == ["www.latercera.com", "www.biobiochile.cl"])
        #expect(chile.marketsAsOf == "2026-10-20" && chile.markets.count == 4)
        #expect(chile.markets[1].change == nil && chile.markets[0].change == "-0.42%")
        #expect(chile.sectionTitle("quick_hit") == "Quick hits")

        let cyber = try #require(NewsEdition.parse(try newsResource("cyber.valid.json")))
        #expect(cyber.stories[0].action?.hasPrefix("Update PHP") == true)
        #expect(NewsEdition.groupTitle("gov_vendor") == "Gov/vendor" && NewsEdition.groupTitle("press") == "Press")
        let ai = try #require(NewsEdition.parse(try newsResource("ai.valid.json")))
        #expect(ai.stories.first { $0.verification == "mixed" }?.headline.hasPrefix("Replit") == true)
    }

    /// Stories come in the feed's section order, then by rank, whatever order the answer has.
    @Test func readingOrder() throws {
        let edition = try #require(NewsEdition.parse(Self.edition(stories: """
            {"section":"industry","rank":1,"headline":"C","summary":"s"},
            {"section":"top","rank":2,"headline":"B","summary":"s"},
            {"section":"weird","rank":1,"headline":"D","summary":"s"},
            {"section":"top","rank":1,"headline":"A","summary":"s"}
            """)))
        #expect(edition.stories.map(\.headline) == ["A", "B", "C", "D"])
        #expect(edition.sectionTitle("weird") == "Weird")
    }

    @Test func realRunPage() throws {
        struct Page: Decodable { var data: Lossy<HistoryMessage> }
        let page = try Wire.decode(Page.self, from: Data(try newsResource("cron-ai.latest2.json").utf8)).data.items
        #expect(page.map(\.role) == [.tool, .assistant])
        let edition = try #require(NewsEdition.parse(page[1].content))
        #expect(edition.feed == "ai" && edition.editionDate == "2026-10-31" && edition.title == "AI daily — 31 October 2026")
        #expect(edition.stories.count == 2 && edition.markets.isEmpty)
        #expect(edition.stories[0].verification == "mixed" && edition.stories[0].blindspot != nil)
    }

    @Test func fencedAndWrapped() throws {
        let json = Self.edition()
        let answers = [
            "```json\n\(json)\n```",
            "```\r\n\(json)\r\n```  ",
            "Here is today's edition:\n\n\(json)\n\nLet me know if you need anything else.",
            "Here it is:\n```json\n\(json)\n```\nDone.",
        ]
        for answer in answers {
            #expect(NewsEdition.parse(answer)?.title == "Test edition", "\(answer.prefix(20))")
        }
    }

    @Test func lenient() throws {
        let edition = try #require(NewsEdition.parse(Self.edition(
            extra: #","novel":{"x":1},"markets":{"as_of":"","items":[{"name":"IPSA","value":"1"},{"name":3}]}"#,
            stories: """
                {"section":"top","rank":"first","headline":" Kept ","summary":"s","sources":[
                  {"outlet":"Good","url":"https://example.com/a"},{"outlet":"Script","url":"javascript:alert(1)"},
                  {"outlet":"Relative","url":"/a"},{"outlet":"Creds","url":"https://u:p@example.com/"},{"url":"https://x.y"}],
                 "coverage":"lots","action":"  ","unknown":true},
                {"section":"top","rank":2,"summary":"no headline: dropped"}
                """)))
        #expect(edition.stories.map(\.headline) == ["Kept"])
        let story = edition.stories[0]
        #expect(story.rank == 100 && story.coverage.isEmpty && story.action == nil)
        #expect(story.sources.map(\.outlet) == ["Good", "Script", "Relative", "Creds"])
        #expect(story.sources.map { $0.url?.absoluteString } == ["https://example.com/a", nil, nil, nil])
        #expect(edition.markets.map(\.name) == ["IPSA"] && edition.marketsAsOf == nil)
    }

    @Test func notNews() {
        let answers = [
            "",
            "I couldn't finish the edition: the search tool was rate-limited.",
            "{not json}",
            "[\(Self.edition())]", // JSON but not an object, like the reader's invalid.not-object.json
            #"{"schema":"news-edition/v2","feed":"ai","edition_date":"2026-10-31","title":"T","lead":"L","stories":[]}"#,
            #"{"feed":"ai","edition_date":"2026-10-31","title":"T"}"#,
            #"{"schema":"news-edition/v1","feed":"ai","edition_date":"2026-10-31","title":"  "}"#,
            #"{"schema":"news-edition/v1","feed":"ai","title":"T"}"#,
            "```json\n{\"schema\":\"news-edition/v1\",\n```",
            "} backwards {",
        ]
        for answer in answers {
            #expect(NewsEdition.parse(answer) == nil, "\(answer.prefix(40))")
        }
    }

    static func edition(extra: String = "", stories: String = #"{"section":"top","rank":1,"headline":"H","summary":"S"}"#) -> String {
        #"{"schema":"news-edition/v1","feed":"ai","edition_date":"2026-10-31","title":"Test edition","lead":"L","stories":["#
            + stories + "]" + extra + "}"
    }
}
