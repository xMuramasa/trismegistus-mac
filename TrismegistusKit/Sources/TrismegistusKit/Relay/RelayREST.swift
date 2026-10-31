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

    public var isReadOnly: Bool { source != "api_server" }

    enum CodingKeys: String, CodingKey {
        case id, source, title, preview, startedAt = "started_at", lastActive = "last_active", messageCount = "message_count"
        case toolCallCount = "tool_call_count"
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

    /// Only for `api_server` sessions (403 read_only otherwise); title is 1-200 characters.
    public func renameSession(_ id: String, title: String) async throws -> SessionInfo {
        try decode(SessionEnvelope.self, try await call("PATCH", try sessionPath(id), body: ["title": title])).session
    }

    /// Only for `api_server` sessions with no active run (409 busy otherwise).
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
        let body = try rest.decode(Body.self, try await rest.call("POST", "/api/pair", body: ["code": code]))
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

    private func sessionPath(_ id: String) throws -> String {
        guard isValidID(id) else { throw RelayAPIError(status: 0, code: .notFound, message: "Unknown session.") }
        return "/api/sessions/" + id
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try Wire.decode(type, from: data) } catch { throw RelayAPIError.unexpected }
    }

    private func call(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> Data {
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
