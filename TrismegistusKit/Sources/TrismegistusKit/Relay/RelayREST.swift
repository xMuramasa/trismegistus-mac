import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A failed REST call, as the relay reports it: `{"error": {code, message}}` with the matching HTTP status.
public struct RelayAPIError: Error, Sendable, Equatable {
    /// HTTP status; 0 when the request never reached the relay's answer (bad id, bad response).
    public let status: Int
    public let code: ErrorCode
    public let message: String

    public init(status: Int, code: ErrorCode, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    /// relay/internal/server/server.go statusOf, reversed: for error bodies that aren't the relay's JSON.
    static let codeOfStatus: [Int: ErrorCode] = [
        400: .badRequest, 401: .unauthorized, 403: .readOnly, 404: .notFound, 409: .busy, 410: .replayGap,
        413: .tooLarge, 429: .rateLimited, 502: .hermesError, 503: .hermesUnavailable,
    ]

    init(status: Int, body: Data) {
        struct Body: Decodable {
            struct Inner: Decodable { var code: String?; var message: String? }
            var error: Inner?
        }
        let inner = (try? Wire.decode(Body.self, from: body))?.error
        self.status = status
        code = inner?.code.flatMap(ErrorCode.init(rawValue:)) ?? Self.codeOfStatus[status] ?? .internal
        message = String((inner?.message ?? "The relay answered \(status).").prefix(512))
    }

    static let unexpected = RelayAPIError(status: 0, code: .hermesError, message: "The relay sent an unexpected response.")
}

/// A Hermes session as the relay passes it through. Only id is required; the rest is whatever Hermes sent.
public struct SessionInfo: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    /// `api_server` sessions are writable from the app; others (telegram, cli...) are read-only.
    public var source: String?
    public var title: String?
    public var preview: String?
    /// Unix seconds.
    public var startedAt: Double?
    public var lastActive: Double?
    public var messageCount: Int?
    public var toolCallCount: Int?
    /// Hermes' keep flag; absent counts as false.
    public var pinned: Bool?
    /// The model Hermes ran the session on (an id like `claude-opus-5-5[1m]`, no provider).
    public var model: String?

    public var isPinned: Bool { pinned ?? false }
    public var isReadOnly: Bool { source != "api_server" }

    enum CodingKeys: String, CodingKey {
        case id, source, title, preview, startedAt = "started_at", lastActive = "last_active", messageCount = "message_count"
        case toolCallCount = "tool_call_count", pinned, model
    }
}

/// One message of a session's Hermes history (`GET /api/sessions/{id}/messages`).
public struct HistoryMessage: Decodable, Sendable, Equatable {
    public enum Role: String, Decodable, Sendable { case user, assistant, tool }

    public struct ToolCall: Decodable, Sendable, Equatable {
        public var id: String?
        public var name: String
        public var arguments: String?

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            id = try c.decodeIfPresent(String.self, forKey: "id")
            let f = try c.nestedContainer(keyedBy: AnyKey.self, forKey: "function")
            name = try f.decode(String.self, forKey: "name")
            arguments = try f.decodeIfPresent(String.self, forKey: "arguments")
        }
    }

    /// Hermes sends a number; kept as a string.
    public var id: String
    public var role: Role
    public var content: String
    public var toolCalls: [ToolCall]
    public var toolCallID: String?
    public var toolName: String?
    public var timestamp: Double?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        if let n = try? c.decode(Int.self, forKey: "id") { id = String(n) } else { id = try c.decode(String.self, forKey: "id") }
        role = try c.decode(Role.self, forKey: "role")
        content = try c.decodeIfPresent(String.self, forKey: "content") ?? ""
        toolCalls = (try? c.decodeIfPresent(Lossy<ToolCall>.self, forKey: "tool_calls"))??.items ?? []
        toolCallID = try c.decodeIfPresent(String.self, forKey: "tool_call_id")
        toolName = try c.decodeIfPresent(String.self, forKey: "tool_name")
        timestamp = try c.decodeIfPresent(Double.self, forKey: "timestamp")
    }
}

/// A JSON array where items that don't decode are skipped (Hermes objects pass through the relay unchecked).
struct Lossy<T: Decodable>: Decodable {
    var items: [T] = []
    /// Items in the array, skipped ones included.
    var count = 0

    init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            count += 1
            if let v = try? c.decode(T.self) { items.append(v) } else { _ = try c.decode(JSONValue.self) }
        }
    }
}

/// The pairing exchange's result: a device token for the Keychain and the name the relay gave the device.
public struct Pairing: Sendable, Equatable {
    public var token: String
    public var device: String
}

/// The relay's REST API with the device token as Bearer: the session list and history, and pairing.
public struct RelayREST: Sendable {
    public let baseURL: URL
    let token: String
    let http: any HTTPTransport

    public init(baseURL: URL, token: String, http: any HTTPTransport = URLSession.shared) {
        self.baseURL = baseURL
        self.token = token
        self.http = http
    }

    public func listSessions() async throws -> [SessionInfo] {
        try decode(Envelope<Lossy<SessionInfo>>.self, try await call("GET", "/api/sessions?limit=100")).data.items
    }

    /// The relay ignores the body and Hermes names the session itself.
    public func createSession() async throws -> SessionInfo {
        try decode(SessionEnvelope.self, try await call("POST", "/api/sessions", body: [:])).session
    }

    /// Every source; title is 1-200 characters.
    public func renameSession(_ id: String, title: String) async throws -> SessionInfo {
        try decode(SessionEnvelope.self, try await call("PATCH", try sessionPath(id), body: ["title": .string(title)])).session
    }

    /// Every source. Pinning is Hermes' durable keep flag (also exempt from auto-prune).
    public func setPinned(_ id: String, _ pinned: Bool) async throws -> SessionInfo {
        try decode(SessionEnvelope.self, try await call("PATCH", try sessionPath(id), body: ["pinned": .bool(pinned)])).session
    }

    /// Every session's tags by session id (`GET /api/tags`). Ids of sessions deleted elsewhere may linger. A relay
    /// that predates the endpoint answers 404: no tags.
    public func tags() async throws -> [String: [String]] {
        do {
            return try decode(TagsEnvelope.self, try await call("GET", "/api/tags")).sessions
        } catch let error as RelayAPIError where error.status == 404 {
            return [:]
        }
    }

    /// Replaces the session's tags (`[]` clears); answers the set as stored (trimmed, deduplicated). 400 bad_request
    /// with a message when a tag breaks the rules (see `TagRules`).
    public func setTags(_ id: String, _ tags: [String]) async throws -> [String] {
        struct Stored: Decodable { var tags: [String] }
        let body: [String: JSONValue] = ["tags": .array(tags.map(JSONValue.string))]
        return try decode(Stored.self, try await call("PUT", try sessionPath(id) + "/tags", body: body)).tags
    }

    /// Hermes' connected providers and models; nil from a relay that predates the endpoint (404).
    public func models() async throws -> ModelCatalog? {
        do {
            return try decode(ModelCatalog.self, try await call("GET", "/api/models"))
        } catch let error as RelayAPIError where error.status == 404 {
            return nil
        }
    }

    /// The sessions with a model of their own; the others use the catalog's `current`. 404 → none.
    public func sessionModels() async throws -> [String: ModelChoice] {
        struct Body: Decodable { var sessions: [String: ModelChoice] }
        do {
            return try decode(Body.self, try await call("GET", "/api/session-models")).sessions
        } catch let error as RelayAPIError where error.status == 404 {
            return [:]
        }
    }

    /// Only `api_server` sessions (403 read_only otherwise); the pair must be in `models()` (400 bad_request). Applies
    /// from the next run.
    public func setModel(_ id: String, _ choice: ModelChoice) async throws -> ModelChoice {
        let body: [String: JSONValue] = ["provider": .string(choice.provider), "model": .string(choice.model)]
        return try decode(ModelChoice.self, try await call("PUT", try sessionPath(id) + "/model", body: body))
    }

    /// Handoff links, newer id → the older id it continues. Ids deleted elsewhere may linger. 404 → none.
    public func links() async throws -> [String: String] {
        struct Body: Decodable { var continues: [String: String] }
        do {
            return try decode(Body.self, try await call("GET", "/api/links")).continues
        } catch let error as RelayAPIError where error.status == 404 {
            return [:]
        }
    }

    /// Records that `id` continues `from` (nil removes its link). A taken link, a loop, a chain over 32 links or a
    /// self-link is 400 bad_request with the reason.
    @discardableResult
    public func setContinues(_ id: String, from: String?) async throws -> String? {
        struct Body: Decodable { var from: String? }
        let body: [String: JSONValue] = ["from": from.map(JSONValue.string) ?? .null]
        return try decode(Body.self, try await call("PUT", try sessionPath(id) + "/continues", body: body)).from
    }

    /// Only for `api_server`, `cron` and `cli` sessions (403 read_only otherwise) with no active run (409 busy).
    public func deleteSession(_ id: String) async throws {
        _ = try await call("DELETE", try sessionPath(id))
    }

    public func messages(_ sessionID: String) async throws -> [HistoryMessage] {
        try decode(Envelope<Lossy<HistoryMessage>>.self, try await call("GET", try sessionPath(sessionID) + "/messages")).data.items
    }

    /// The last `limit` messages of a session, oldest first: the end of a long history without fetching all of it.
    public func latestMessages(_ sessionID: String, limit: Int) async throws -> [HistoryMessage] {
        let path = try sessionPath(sessionID) + "/messages?limit=\(limit)&order=latest"
        return try decode(Envelope<Lossy<HistoryMessage>>.self, try await call("GET", path)).data.items
    }

    /// Up to `limit` messages after the first `offset`, oldest first: the rest of a history fetched before. `count` is
    /// how many the page held, messages that didn't decode included: add it to the offset for the next page.
    public func messages(_ sessionID: String, offset: Int, limit: Int) async throws -> (messages: [HistoryMessage], count: Int) {
        let path = try sessionPath(sessionID) + "/messages?limit=\(limit)&offset=\(offset)&order=oldest"
        let page = try decode(Envelope<Lossy<HistoryMessage>>.self, try await call("GET", path)).data
        return (page.items, page.count)
    }

    /// Trades a one-time pairing code (`XXXX-XXXX-XXXX`, from `trismegistus-relay pair`) for a device token.
    /// A bad, used or expired code is `unauthorized`.
    public static func pair(baseURL: URL, code: String, http: any HTTPTransport = URLSession.shared) async throws -> Pairing {
        struct Body: Decodable {
            struct Device: Decodable { var name: String }
            var token: String
            var device: Device
        }
        let rest = RelayREST(baseURL: baseURL, token: "", http: http)
        let body = try rest.decode(Body.self, try await rest.call("POST", "/api/pair", body: ["code": .string(code)]))
        guard isDeviceToken(body.token) else { throw RelayAPIError.unexpected }
        return Pairing(token: body.token, device: String(body.device.name.prefix(64)))
    }

    /// `trs_` and 43 base64url characters, as relay/internal/pairing makes them.
    static func isDeviceToken(_ s: String) -> Bool {
        let base64url = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
        return s.hasPrefix("trs_") && s.utf8.count == 47 && s.utf8.dropFirst(4).allSatisfy(base64url.contains)
    }

    private struct Envelope<T: Decodable>: Decodable { var data: T }
    private struct SessionEnvelope: Decodable { var session: SessionInfo }
    private struct TagsEnvelope: Decodable { var sessions: [String: [String]] }

    private func sessionPath(_ id: String) throws -> String {
        guard isValidID(id) else { throw RelayAPIError(status: 0, code: .notFound, message: "Unknown session.") }
        return "/api/sessions/" + id
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try Wire.decode(type, from: data) } catch { throw RelayAPIError.unexpected }
    }

    private func call(_ method: String, _ path: String, body: [String: JSONValue]? = nil) async throws -> Data {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + path) else { throw RelayAPIError(status: 0, code: .badRequest, message: "Bad relay URL.") }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try Wire.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await http.response(for: request)
        guard (200..<300).contains(response.statusCode) else { throw RelayAPIError(status: response.statusCode, body: data) }
        return data
    }
}
