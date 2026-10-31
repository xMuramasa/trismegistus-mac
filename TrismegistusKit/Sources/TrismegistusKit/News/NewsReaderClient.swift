import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NewsReaderError: Error, Sendable, Equatable {
    /// No answer: offline, off the tailnet, a timeout.
    case unreachable
    /// An answer that isn't a 2xx with the expected JSON.
    case badResponse
}

/// The news reader's public API (news-reader `apps/api/src/public.ts`): no login, reachable over the tailnet.
public struct NewsReaderClient: Sendable {
    /// A feed from `/api/feeds`: its sections in reading order.
    public struct Feed: Decodable, Sendable, Equatable {
        public var id: String
        public var sections: [NewsEdition.Section]

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = try c.required("id").lowercased()
            sections = c.lossy("sections")
        }
    }

    /// The reader's page limit (`MAX_LIMIT`); a cursor that never ends stops after `maxPages`.
    static let pageSize = 100
    static let maxPages = 20

    public let baseURL: URL
    let http: any HTTPTransport

    public init(baseURL: URL, http: any HTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.http = http
    }

    /// Every edition as a summary (no stories), newest run first, following `next`.
    public func editions() async throws(NewsReaderError) -> [NewsEdition] {
        struct Page: Decodable { var editions: Lossy<NewsEdition>; var next: String? }
        var out: [NewsEdition] = []
        var before: String?
        for _ in 0..<Self.maxPages {
            var query = [URLQueryItem(name: "limit", value: "\(Self.pageSize)")]
            if let before { query.append(URLQueryItem(name: "before", value: before)) }
            let page = try await get(Page.self, "/api/editions", query)
            out += page.editions.items.filter { $0.id != nil }
            guard let next = page.next, next != before else { break }
            before = next
        }
        return out
    }

    /// The full edition: stories, markets, gaps.
    public func edition(_ id: String) async throws(NewsReaderError) -> NewsEdition {
        struct Detail: Decodable { var edition: NewsEdition }
        // The id comes from the reader's own list, but it goes into a path.
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".utf8)
        guard !id.isEmpty, id.utf8.count <= 128, id.utf8.allSatisfy(allowed.contains) else { throw .badResponse }
        return try await get(Detail.self, "/api/editions/" + id).edition
    }

    public func feeds() async throws(NewsReaderError) -> [Feed] {
        struct Feeds: Decodable { var feeds: Lossy<Feed> }
        return try await get(Feeds.self, "/api/feeds").feeds.items
    }

    private func get<T: Decodable>(_ type: T.Type, _ path: String, _ query: [URLQueryItem] = []) async throws(NewsReaderError) -> T {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + path) else { throw .badResponse }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw .badResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: HTTPURLResponse
        do { (data, response) = try await http.response(for: request) } catch { throw .unreachable }
        guard (200..<300).contains(response.statusCode), let value = try? Wire.decode(type, from: data) else { throw .badResponse }
        return value
    }
}
