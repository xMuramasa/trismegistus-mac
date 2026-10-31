import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

private func message(_ id: Int, _ role: String, _ content: String, calls: [(String, String)] = [], callID: String? = nil) throws -> HistoryMessage {
    var object: [String: JSONValue] = ["id": .number(Double(id)), "role": .string(role), "content": .string(content),
                                       "timestamp": .number(1_793_440_000 + Double(id))]
    if !calls.isEmpty {
        object["tool_calls"] = .array(calls.enumerated().map { i, c in
            .object(["id": .string("c\(id)-\(i)"), "function": .object(["name": .string(c.0), "arguments": .string(c.1)])])
        })
    }
    if let callID { object["tool_call_id"] = .string(callID) }
    return try Wire.decode(HistoryMessage.self, from: Wire.encode(JSONValue.object(object)))
}

private func entry(_ tool: String, _ command: String?, exit: Int? = nil) -> TerminalEntry {
    TerminalEntry(id: -1, runID: "", tool: tool, time: 0, command: command, exitCode: exit, isError: false,
                  isTruncated: false, isRunning: false)
}

@Suite struct HandoffDigestTests {
    let info = SessionInfo(id: "api_1793441468_d77589de", source: "api_server", title: "Approvals test",
                           startedAt: 1_793_441_468, messageCount: 23)
    let utc = TimeZone(identifier: "UTC")!

    @Test func realHistoryHasMessagesAndOneLinePerCallButNoOutput() throws {
        let digest = HandoffDigest.make(history: try appSession(), info: info, model: "anthropic/claude-opus-4-7", timeZone: utc)
        #expect(digest.hasPrefix("# Earlier conversation\nTitle: Approvals test\nId: api_1793441468_d77589de\nStarted: 2026-10-31 "))
        #expect(digest.contains("Model: anthropic/claude-opus-4-7\nMessages: 23\n"))
        #expect(digest.contains("## User · 2026-10-31 ") && digest.contains("can you ask for an approval?"))
        #expect(digest.contains("It printed \"hello world\" and exited with code 0."))
        #expect(digest.contains("- $ echo hello world → exit 0"))
        #expect(digest.contains("- patch /home/muramasa/.hermes/config.yaml"))
        #expect(digest.components(separatedBy: "\n- $ ").count - 1 == 8) // 8 terminal calls and the patch
        // Tool output never: these are only in results.
        #expect(!digest.contains("sudo: interactive authentication") && !digest.contains("drwxrwxr-x"))
        #expect(!digest.contains("Refusing to write"))
        #expect(!digest.contains("cut to fit"))
    }

    @Test func toolLines() {
        #expect(HandoffDigest.toolLine(entry("terminal", "ls -la\nrm x", exit: 2)) == "$ ls -la … → exit 2")
        let long = HandoffDigest.toolLine(entry("terminal", String(repeating: "a", count: 500), exit: 0))
        #expect(long == "$ " + String(repeating: "a", count: 200) + " … → exit 0")
        var waiting = entry("terminal", "sleep 100")
        waiting.awaitsResult = true
        #expect(HandoffDigest.toolLine(waiting) == "$ sleep 100 → no result")
        #expect(HandoffDigest.toolLine(entry("write_file", #"{"path":"/tmp/a.md","content":"secret body"}"#)) == "write_file /tmp/a.md")
        #expect(HandoffDigest.toolLine(entry("web_search", #"{"query":"swift 6.4","limit":5}"#)) == "web_search query=swift 6.4")
        #expect(HandoffDigest.toolLine(entry("execute_code", "import os\nprint(1)")) == "execute_code: import os …")
        #expect(HandoffDigest.toolLine(entry("todo", #"{"merge":true}"#)) == "todo")
    }

    @Test func longHistoryKeepsTheFirstUserMessageAndTheNewestPart() throws {
        var history: [HistoryMessage] = []
        for i in 0..<200 {
            history.append(try message(2 * i, "user", "question \(i) " + String(repeating: "q", count: 300)))
            history.append(try message(2 * i + 1, "assistant", "answer \(i) " + String(repeating: "a", count: 600),
                                       calls: [("terminal", #"{"command":"make \#(i)"}"#)]))
        }
        history.append(try message(1000, "user", String(repeating: "x", count: 50_000))) // one huge paste
        let digest = HandoffDigest.make(history: history, info: SessionInfo(id: "s1"), model: nil)
        #expect(digest.unicodeScalars.count <= HandoffDigest.limit)
        #expect(digest.contains("question 0 ") && digest.contains("answer 199 ") && digest.contains("$ make 199"))
        #expect(!digest.contains("answer 0 ") && !digest.contains("question 100 "))
        #expect(digest.contains("earlier entries cut to fit; the full history stays in conversation s1"))
        #expect(digest.contains(String(repeating: "x", count: 4000) + " …") && !digest.contains(String(repeating: "x", count: 4001)))
        // With the fixed text it still fits the relay's 32,768.
        #expect(HandoffDigest.prompt(digest: digest).unicodeScalars.count <= 32_768)
    }

    @Test func stallMessagesMatchOnStableFragments() {
        #expect(HandoffDigest.isStall("Provider has been unresponsive (no response received) for 5 consecutive stale attempts"))
        #expect(HandoffDigest.isStall("Operation interrupted: waiting for model response (480s)"))
        #expect(HandoffDigest.isStall("Your request was not processed. Send it again if you still want me to carry it out."))
        #expect(!HandoffDigest.isStall("Run failed: exit 1"))
    }
}

@Suite struct HandoffChainTests {
    // c continues b, b continues a; y continues x.
    let links = ["c": "b", "b": "a", "y": "x"]

    @Test func tipsAndOlderParts() {
        let listed: Set<String> = ["a", "b", "c", "x", "y", "z"]
        #expect(HandoffChain.continued(listed: listed, links: links) == ["a", "b", "x"])
        #expect(HandoffChain.tip(of: "a", links: links, listed: listed) == "c")
        #expect(HandoffChain.tip(of: "c", links: links, listed: listed) == "c")
        #expect(HandoffChain.tip(of: "z", links: links, listed: listed) == "z")
        #expect(HandoffChain.older(than: "c", links: links) == ["b", "a"])
        #expect(HandoffChain.older(than: "a", links: links).isEmpty)
        #expect(SessionListing.threads(["z", "c", "b", "y", "a", "x"], id: { $0 }, links: links) == ["z", "c", "y"])
    }

    @Test func brokenLinks() {
        // c was deleted elsewhere: b is the tip and shows; a part deleted elsewhere is still named as older.
        let listed: Set<String> = ["a", "b"]
        #expect(HandoffChain.continued(listed: listed, links: links) == ["a"])
        #expect(HandoffChain.tip(of: "a", links: links, listed: listed) == "b")
        #expect(HandoffChain.older(than: "y", links: links) == ["x"])
        #expect(SessionListing.threads(["y"], id: { $0 }, links: links) == ["y"])
    }

    @Test func depthAndLoopsAreBounded() {
        let long = Dictionary(uniqueKeysWithValues: (1...40).map { ("s\($0)", "s\($0 - 1)") })
        #expect(HandoffChain.older(than: "s40", links: long).count == HandoffChain.maxLinks)
        #expect(HandoffChain.tip(of: "s0", links: long, listed: Set((0...40).map { "s\($0)" })) == "s32") // 32 links up
        let loop = ["a": "b", "b": "a"]
        #expect(HandoffChain.older(than: "a", links: loop) == ["b"])
        #expect(["a", "b"].contains(HandoffChain.tip(of: "a", links: loop, listed: ["a", "b"])))
    }
}

@Suite struct ModelsAndLinksRESTTests {
    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: relayURL, token: fakeToken, http: http), http)
    }

    @Test func modelsAndAMissingEndpoint() async throws {
        let (api, _) = rest { _ in
            (200, #"{"current":{"provider":"anthropic","model":"claude-opus-4-7[1m]"},"providers":[{"slug":"anthropic","name":"Anthropic","models":[{"id":"claude-opus-4-7[1m]","reasoning":true}]}]}"#)
        }
        let catalog = try #require(try await api.models())
        #expect(catalog.current.label == "claude-opus-4-7 1M" && catalog.providerName("anthropic") == "Anthropic")
        #expect(catalog.providers.first?.models.first?.id == "claude-opus-4-7[1m]")
        let (old, _) = rest { _ in (404, #"{"error":{"code":"not_found","message":"not found"}}"#) }
        #expect(try await old.models() == nil)
        #expect(try await old.sessionModels() == [:])
        #expect(try await old.links() == [:])
    }

    @Test func setModelAndContinuesSendTheirBodies() async throws {
        let (api, http) = rest { r in
            r.url?.path.hasSuffix("/model") == true ? (200, #"{"provider":"copilot","model":"gpt-5"}"#) : (200, #"{"from":null}"#)
        }
        #expect(try await api.setModel("a1", ModelChoice(provider: "copilot", model: "gpt-5")) == ModelChoice(provider: "copilot", model: "gpt-5"))
        #expect(try await api.setContinues("a1", from: nil) == nil)
        let bodies = http.requests.current.map { r in r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) } }
        #expect(http.requests.current.map { "\($0.httpMethod!) \($0.url!.path)" } == ["PUT /api/sessions/a1/model", "PUT /api/sessions/a1/continues"])
        #expect(bodies == [.object(["provider": .string("copilot"), "model": .string("gpt-5")]), .object(["from": .null])])
    }
}

/// The handoff flow and thread delete against a fake relay.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct HandoffFlowTests {
    let transport = FakeTransport()
    let clock = TestClock()
    let refuseLink = Watched<Bool>(false)
    let http: FakeHTTP
    let store: SessionStore

    init() {
        let refuseLink = refuseLink
        http = FakeHTTP { r in
            switch (r.httpMethod ?? "", r.url?.path ?? "") {
            case ("GET", "/api/sessions"):
                return (200, #"{"data":[{"id":"old","source":"api_server","title":"Homepage","pinned":true},{"id":"older","source":"telegram"},{"id":"other","source":"cli"}]}"#)
            case ("GET", "/api/tags"): return (200, #"{"sessions":{"old":["web"]}}"#)
            case ("GET", "/api/links"): return (200, #"{"continues":{"old":"older"}}"#)
            case ("GET", "/api/models"):
                return (200, #"{"current":{"provider":"anthropic","model":"opus"},"providers":[{"slug":"anthropic","name":"Anthropic","models":[{"id":"opus"},{"id":"sonnet"}]}]}"#)
            case ("GET", "/api/session-models"): return (200, #"{"sessions":{}}"#)
            case ("POST", "/api/sessions"): return (200, #"{"session":{"id":"new","source":"api_server"}}"#)
            case ("PUT", "/api/sessions/new/continues"):
                return refuseLink.current ? (400, #"{"error":{"code":"bad_request","message":"link taken"}}"#) : (200, #"{"from":"old"}"#)
            case ("PATCH", let path): return (200, #"{"session":{"id":"\#(path.split(separator: "/").last!)"}}"#)
            case ("PUT", "/api/sessions/new/tags"): return (200, #"{"tags":["web"]}"#)
            case ("PUT", "/api/sessions/new/model"): return (200, #"{"provider":"anthropic","model":"sonnet"}"#)
            case ("GET", "/api/sessions/new/messages"): return (200, #"{"data":[]}"#)
            case ("DELETE", "/api/sessions/old"), ("DELETE", "/api/sessions/new"): return (200, #"{"deleted":true}"#)
            default: return (404, #"{"error":{"code":"not_found","message":"not found"}}"#)
            }
        }
        let clock = clock
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport, sleep: { try await clock.sleep(for: $0) })
        store = SessionStore(client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http))
    }

    func requests(after count: Int) -> [String] {
        http.requests.current.dropFirst(count).map { "\($0.httpMethod!) \($0.url!.path)" }
    }

    @Test func refreshLoadsLinksAndModelsAndTheListShowsThreads() async throws {
        try await store.refreshSessions()
        #expect(store.links == ["old": "older"] && store.model(for: "old") == ModelChoice(provider: "anthropic", model: "opus"))
        #expect(SessionListing.threads(store.sessionList, id: \.id, links: store.links).map(\.id) == ["old", "other"])
        #expect(store.threadTip(of: "older") == "old" && store.olderParts(of: "old") == ["older"])
    }

    @Test func handOffRunsTheStepsInOrderAndSendsThePromptLast() async throws {
        try await store.refreshSessions()
        let before = http.requests.current.count
        let old = try #require(store.sessionList.first { $0.id == "old" })
        let result = try await store.handOff(old, model: ModelChoice(provider: "anthropic", model: "sonnet"), prompt: "digest")
        #expect(result.sessionID == "new" && result.problems.isEmpty)
        #expect(requests(after: before) == [
            "POST /api/sessions", "PUT /api/sessions/new/continues", "PATCH /api/sessions/new", "PUT /api/sessions/new/tags",
            "PATCH /api/sessions/new", "PATCH /api/sessions/old", "PUT /api/sessions/new/model", "GET /api/sessions/new/messages",
        ])
        #expect(store.links["new"] == "old" && store.threadTip(of: "older") == "new")
        #expect(store.tags["new"] == ["web"] && store.sessionList.first { $0.id == "new" }?.title == "Homepage")
        #expect(store.sessionList.first { $0.id == "new" }?.isPinned == true && store.sessionList.first { $0.id == "old" }?.isPinned == false)
        #expect(store.sessions["new"]?.outbox.map(\.text) == ["digest"]) // through the outbox (not connected here: failed, retryable)
    }

    @Test func sameModelIsNotSetAndALinkRefusalStopsBeforeThePrompt() async throws {
        try await store.refreshSessions()
        refuseLink.mutate { $0 = true }
        let before = http.requests.current.count
        let old = try #require(store.sessionList.first { $0.id == "old" })
        await #expect(throws: HandoffError(sessionID: "new", message: "Couldn't link the new conversation: link taken")) {
            try await store.handOff(old, model: store.model(for: "old"), prompt: "digest")
        }
        #expect(requests(after: before) == ["POST /api/sessions", "PUT /api/sessions/new/continues"])
        #expect(store.sessionList.contains { $0.id == "new" } && store.sessions["new"] == nil)
    }

    @Test func deleteThreadGoesNewestFirstAndSkipsProtectedParts() async throws {
        try await store.refreshSessions()
        #expect(store.deletableParts(of: "old") == ["old"]) // "older" is a Telegram chat
        let before = http.requests.current.count
        try await store.deleteThread("old")
        #expect(requests(after: before) == ["DELETE /api/sessions/old"])
        #expect(store.links.isEmpty && store.sessionList.map(\.id) == ["older", "other"])
    }
}
