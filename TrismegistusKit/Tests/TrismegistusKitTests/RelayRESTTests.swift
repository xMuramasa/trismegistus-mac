import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// RelayREST against FakeHTTP, with the bodies and statuses relay/internal/server returns.
@Suite struct RelayRESTTests {
    static let unauthorized = (401, #"{"error":{"code":"unauthorized","message":"unauthorized"}}"#)
    static let notFound = (404, #"{"error":{"code":"not_found","message":"not found"}}"#)

    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: URL(string: "https://relay.invalid/")!, token: fakeToken, http: http), http)
    }

    func body(_ r: URLRequest) -> JSONValue? { r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) } }

    @Test func listSessions() async throws {
        let (api, http) = rest { _ in
            (200, #"{"object":"list","has_more":false,"data":[{"id":"api_1","source":"api_server","title":"Dates","message_count":4,"last_active":1792801004.5},{"id":7},{"id":"cli_2","source":"cli","title":null}]}"#)
        }
        let sessions = try await api.listSessions()
        #expect(sessions.map(\.id) == ["api_1", "cli_2"]) // the malformed one is skipped
        #expect(sessions[0].title == "Dates" && sessions[0].messageCount == 4 && !sessions[0].isReadOnly)
        #expect(sessions[1].isReadOnly)
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "GET")
        #expect(r.url?.absoluteString == "https://relay.invalid/api/sessions?limit=100")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer \(fakeToken)")
    }

    @Test func listSessionsUnauthorized() async {
        let (api, _) = rest { _ in Self.unauthorized }
        await #expect(throws: RelayAPIError(status: 401, code: .unauthorized, message: "unauthorized")) {
            try await api.listSessions()
        }
    }

    @Test func createSession() async throws {
        let (api, http) = rest { _ in (201, #"{"object":"hermes.session","session":{"id":"api_9","source":"api_server"}}"#) }
        #expect(try await api.createSession().id == "api_9")
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "POST" && r.url?.path == "/api/sessions" && body(r) == .object([:]))
    }

    @Test func createSessionUnauthorized() async {
        let (api, _) = rest { _ in Self.unauthorized }
        await #expect(throws: RelayAPIError.self) { try await api.createSession() }
    }

    @Test func renameSession() async throws {
        let (api, http) = rest { _ in (200, #"{"object":"hermes.session","session":{"id":"api_9","title":"Taxes"}}"#) }
        #expect(try await api.renameSession("api_9", title: "Taxes").title == "Taxes")
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "PATCH" && r.url?.path == "/api/sessions/api_9")
        #expect(body(r) == .object(["title": .string("Taxes")]))
    }

    @Test func renameErrors() async {
        let (missing, _) = rest { _ in Self.notFound }
        await #expect(throws: RelayAPIError(status: 404, code: .notFound, message: "not found")) {
            try await missing.renameSession("api_404", title: "x")
        }
        let (readOnly, _) = rest { _ in (403, #"{"error":{"code":"read_only","message":"this session is read-only here"}}"#) }
        await #expect(throws: RelayAPIError(status: 403, code: .readOnly, message: "this session is read-only here")) {
            try await readOnly.renameSession("cli_1", title: "x")
        }
    }

    @Test func deleteSession() async throws {
        let (api, http) = rest { _ in (200, #"{"deleted":true}"#) }
        try await api.deleteSession("api_9")
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "DELETE" && r.url?.path == "/api/sessions/api_9")
    }

    @Test func deleteErrors() async {
        let (busy, _) = rest { _ in (409, #"{"error":{"code":"busy","message":"a run is active in this session"}}"#) }
        await #expect(throws: RelayAPIError(status: 409, code: .busy, message: "a run is active in this session")) {
            try await busy.deleteSession("api_9")
        }
        let (missing, _) = rest { _ in Self.notFound }
        await #expect(throws: RelayAPIError(status: 404, code: .notFound, message: "not found")) {
            try await missing.deleteSession("api_9")
        }
        let (gone, _) = rest { _ in Self.unauthorized }
        await #expect(throws: RelayAPIError(status: 401, code: .unauthorized, message: "unauthorized")) {
            try await gone.deleteSession("api_9")
        }
    }

    @Test func badSessionIDNeverLeavesTheApp() async {
        let (api, http) = rest { _ in (200, "{}") }
        await #expect(throws: RelayAPIError.self) { try await api.deleteSession("../admin") }
        await #expect(throws: RelayAPIError.self) { try await api.messages("api_1/messages") }
        #expect(http.requests.current.isEmpty)
    }

    @Test func serverErrorsWithoutJSONMapByStatus() async {
        let (api, _) = rest { _ in (503, "unavailable") }
        await #expect(throws: RelayAPIError(status: 503, code: .hermesUnavailable, message: "The relay answered 503.")) {
            try await api.listSessions()
        }
        let (bad, _) = rest { _ in (500, "") }
        await #expect(throws: RelayAPIError(status: 500, code: .internal, message: "The relay answered 500.")) {
            try await bad.listSessions()
        }
    }

    @Test func messages() async throws {
        let (api, http) = rest { _ in
            (200, #"""
            {"object":"list","session_id":"api_1","data":[
              {"id":1,"role":"user","content":"What year is it?","timestamp":1792801001.0},
              {"id":2,"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function","function":{"name":"terminal","arguments":"{\"command\":\"date +%Y\"}"}}]},
              {"id":3,"role":"tool","content":"2026","tool_call_id":"call_1","tool_name":"terminal"},
              {"id":4,"role":"system","content":"skipped"},
              {"id":5,"role":"assistant","content":"It is 2026."}
            ]}
            """#)
        }
        let history = try await api.messages("api_1")
        #expect(history.map(\.id) == ["1", "2", "3", "5"])
        #expect(history[1].toolCalls.first?.name == "terminal" && history[1].content == "")
        #expect(history[2].toolCallID == "call_1")
        #expect(http.requests.current.first?.url?.path == "/api/sessions/api_1/messages")
    }

    @Test func pair() async throws {
        let http = FakeHTTP { _ in (200, #"{"token":"\#(fakeToken)","device":{"name":"macbook","created_at":"2026-10-30T12:00:00Z"}}"#) }
        let pairing = try await RelayREST.pair(baseURL: relayURL, code: "ABCD-EFGH-JKMN", http: http)
        #expect(pairing == Pairing(token: fakeToken, device: "macbook"))
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "POST" && r.url?.path == "/api/pair")
        #expect(r.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(body(r) == .object(["code": .string("ABCD-EFGH-JKMN")]))
    }

    @Test func pairRejectsBadCodesAndBadTokens() async {
        let used = FakeHTTP { _ in (401, #"{"error":{"code":"unauthorized","message":"invalid, used or expired pairing code"}}"#) }
        await #expect(throws: RelayAPIError(status: 401, code: .unauthorized, message: "invalid, used or expired pairing code")) {
            try await RelayREST.pair(baseURL: relayURL, code: "ABCD-EFGH-JKMN", http: used)
        }
        let odd = FakeHTTP { _ in (200, #"{"token":"trs_short","device":{"name":"macbook"}}"#) }
        await #expect(throws: RelayAPIError.unexpected) {
            try await RelayREST.pair(baseURL: relayURL, code: "ABCD-EFGH-JKMN", http: odd)
        }
    }
}
