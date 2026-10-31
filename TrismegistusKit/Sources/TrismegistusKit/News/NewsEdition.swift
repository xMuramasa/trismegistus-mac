import Foundation

/// A `news-edition/v1` edition (news-reader `packages/schema/src/edition.ts`), with what the reader shows. Decoding is
/// lenient: unknown keys are ignored, a story or source that doesn't decode is dropped, wrong-typed optional fields
/// are nil. Only the schema id, feed, date and title decide whether an answer is an edition at all.
public struct NewsEdition: Decodable, Sendable, Equatable {
    public static let schemaID = "news-edition/v1"

    public struct Story: Decodable, Sendable, Equatable {
        public struct Detail: Decodable, Sendable, Equatable { public var label: String; public var text: String }
        public struct Coverage: Decodable, Sendable, Equatable {
            public var group: String
            public var covered: Bool
            public var outlets: [String]
        }
        public struct Framing: Decodable, Sendable, Equatable { public var group: String; public var text: String }
        public struct Source: Decodable, Sendable, Equatable {
            public var outlet: String
            /// Only absolute http(s) URLs; the answer is model output, so nothing else is ever opened.
            public var url: URL?
        }

        public var section: String
        public var rank: Int
        public var headline: String
        public var summary: String
        public var verification: String?
        public var action: String?
        public var details: [Detail]
        public var coverage: [Coverage]
        public var framing: [Framing]
        public var blindspot: String?
        public var sources: [Source]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            headline = try c.required("headline")
            summary = try c.required("summary")
            section = c.text("section")?.lowercased() ?? "top"
            rank = (try? c.decodeIfPresent(Int.self, forKey: "rank")) ?? 100
            verification = c.text("verification")?.lowercased()
            action = c.text("action")
            details = c.lossy("details")
            coverage = c.lossy("coverage")
            framing = c.lossy("framing")
            blindspot = c.text("blindspot")
            sources = c.lossy("sources")
        }
    }

    public struct Market: Decodable, Sendable, Equatable {
        public var name: String
        public var value: String
        public var change: String?
    }

    /// `chile`, `cyber`, `ai`, or a feed added later; `tag` is what the app shows.
    public var feed: String
    /// `YYYY-MM-DD`, which sorts as text.
    public var editionDate: String
    public var title: String
    public var lead: String
    /// In reading order: the feed's sections in order, then by rank.
    public var stories: [Story]
    public var gaps: [String]
    public var marketsAsOf: String?
    public var markets: [Market]

    public var tag: String { feed.uppercased() }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.check(c.text("schema") == Self.schemaID, "schema", "not a news edition")
        feed = try c.required("feed").lowercased()
        editionDate = try c.required("edition_date")
        title = try c.required("title")
        lead = c.text("lead") ?? ""
        let order = Self.sections[feed] ?? []
        func position(_ s: Story) -> Int { order.firstIndex { $0.id == s.section } ?? order.count }
        stories = (c.lossy("stories") as [Story]).enumerated()
            .sorted { a, b in
                let (x, y) = ((position(a.element), a.element.rank, a.offset), (position(b.element), b.element.rank, b.offset))
                return x < y
            }
            .map(\.element)
        gaps = (c.lossy("gaps") as [String]).filter { !$0.isEmpty }
        let m = try? c.nestedContainer(keyedBy: AnyKey.self, forKey: "markets")
        marketsAsOf = m?.text("as_of")
        markets = m?.lossy("items") ?? []
    }

    /// The edition in a cron run's final answer, like the publisher's `parse_answer`: the whole answer, the inside of
    /// a ```json fence, or else the outermost `{…}`. Nil when the answer is not an edition.
    public static func parse(_ answer: String) -> NewsEdition? {
        var text = Substring(answer.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.hasPrefix("```"), text.hasSuffix("```"), let newline = text.firstIndex(where: \.isNewline) {
            text = text[text.index(after: newline)..<text.index(text.endIndex, offsetBy: -3)]
        }
        // Only an answer that isn't JSON falls back to its `{…}`: valid JSON that isn't an edition is not news.
        let data = Data(text.utf8)
        if (try? Wire.decode(JSONValue.self, from: data)) != nil { return try? Wire.decode(NewsEdition.self, from: data) }
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? Wire.decode(NewsEdition.self, from: Data(text[start...end].utf8))
    }

    /// Section ids and titles per feed, in reading order (news-reader `packages/schema/src/feeds.ts`).
    public static let sections: [String: [(id: String, title: String)]] = [
        "chile": [
            ("top", "Top stories"), ("independent", "Independent & alternative"), ("fact_check", "Fact-checks"),
            ("quick_hit", "Quick hits"),
        ],
        "cyber": [
            ("patch_now", "Patch now"), ("top", "Top stories"), ("your_stack", "Your stack"),
            ("chile_latam", "Chile & LatAm"), ("research", "Research & threat intel"), ("policy", "Policy"),
        ],
        "ai": [
            ("top", "Top stories"), ("release", "Model & product releases"), ("open_source", "Open-source & local AI"),
            ("research", "Research highlights"), ("industry", "Industry, funding & policy"),
        ],
    ]

    public func sectionTitle(_ id: String) -> String {
        Self.sections[feed]?.first { $0.id == id }?.title ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Coverage and framing group names (`gov_vendor` is "Gov/vendor"; the rest are their id capitalized).
    public static func groupTitle(_ id: String) -> String {
        id == "gov_vendor" ? "Gov/vendor" : id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

extension NewsEdition.Story.Source {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        outlet = try c.required("outlet")
        url = c.text("url").flatMap(URL.init(string:)).flatMap { url in
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                url.host?.isEmpty == false, url.user == nil, url.password == nil
            else { return nil }
            return url
        }
    }
}

extension NewsEdition.Story.Coverage {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        group = try c.required("group").lowercased()
        covered = (try? c.decodeIfPresent(Bool.self, forKey: "covered")) ?? true
        outlets = c.lossy("outlets")
    }
}

extension NewsEdition.Market {
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = try c.required("name")
        value = try c.required("value")
        change = c.text("change")
    }
}

extension KeyedDecodingContainer where Key == AnyKey {
    /// A trimmed, non-empty string, or nil for anything else.
    func text(_ key: AnyKey) -> String? {
        guard let s = try? decodeIfPresent(String.self, forKey: key) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    func required(_ key: AnyKey) throws -> String {
        guard let t = text(key) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "missing or empty")
        }
        return t
    }

    /// The array's items that decode; empty when the key is missing or not an array.
    func lossy<T: Decodable>(_ key: AnyKey) -> [T] {
        ((try? decodeIfPresent(Lossy<T>.self, forKey: key)) ?? nil)?.items ?? []
    }
}
