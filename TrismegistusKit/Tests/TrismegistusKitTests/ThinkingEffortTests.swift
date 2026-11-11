import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// #74: the thinking steps of each answer, the latest thought during a run, and the efforts store.
@Suite struct ThinkingTimelineTests {
    /// Two turns: the first thinks in three steps (two tool rounds, then the answer), the second doesn't think.
    static let thinking = history(#"""
    [{"id":1,"role":"user","content":"Test the UI"},
     {"id":2,"role":"assistant","content":"","reasoning":"Read the tree first.\nThen press.","tool_calls":[{"id":"c1","function":{"name":"terminal","arguments":"{\"command\":\"cua-driver inspect --depth 2\\nsecond line\"}"}}]},
     {"id":3,"role":"tool","content":"{}","tool_call_id":"c1"},
     {"id":4,"role":"assistant","content":"","reasoning":"  Press each one.  ","tool_calls":[{"id":"c2","function":{"name":"terminal","arguments":"{}"}},{"id":"c3","function":{"name":"read_file","arguments":"{}"}},{"id":"c4","function":{"name":"terminal","arguments":"{}"}}]},
     {"id":5,"role":"user","content":"and the tabs","display_kind":"steer"},
     {"id":6,"role":"assistant","content":"All good.","reasoning":"Everything works."},
     {"id":7,"role":"user","content":"Thanks"},
     {"id":8,"role":"assistant","content":"You're welcome.","reasoning":""}]
    """#)

    @Test func decodesReasoning() {
        #expect(Self.thinking[1].reasoning == "Read the tree first.\nThen press.")
        #expect(Self.thinking[0].reasoning == nil && Self.thinking[7].reasoning == "")
    }

    @Test func groupsEachAnswersStepsInOrderAfterIt() {
        var s = SessionState(id: "s1")
        s.applyHistory(Self.thinking)
        let items = ChatTimeline.items(s, compact: false)
        #expect(items.map(\.id) == ["h-1", "h-5", "h-6", "k-6", "h-7", "h-8"]) // a steer stays in its turn; no chip without thinking
        guard case .thinking(_, let steps, let commands) = items[3] else { Issue.record("no thinking after the answer"); return }
        // The turn's calls for the commands chip: three terminal calls and a read_file, in order; c1 has its result.
        #expect(commands.map(\.tool) == ["terminal", "terminal", "read_file", "terminal"])
        #expect(commands.first?.command == "cua-driver inspect --depth 2\nsecond line" && commands.first?.awaitsResult == false)
        #expect(commands.allSatisfy { $0.sessionID == "s1" })
        #expect(steps == [
            ThinkingStep(thought: "Read the tree first.\nThen press.", tool: "terminal", detail: "cua-driver inspect --depth 2"),
            ThinkingStep(thought: "Press each one.", tool: "terminal, read_file", detail: "3 calls"),
            ThinkingStep(thought: "Everything works."),
        ])
        #expect(!ChatTimeline.items(s, compact: true).contains { if case .thinking = $0 { true } else { false } }) // the window only
    }

    @Test func aTurnWithCommandsButNoThinkingGetsTheCommandsChip() {
        var s = SessionState(id: "s1")
        s.applyHistory(history(#"""
        [{"id":1,"role":"user","content":"Restart it"},
         {"id":2,"role":"assistant","content":"","tool_calls":[{"id":"c1","function":{"name":"terminal","arguments":"{\"command\":\"systemctl restart x\"}"}}]},
         {"id":3,"role":"tool","content":"{\"output\":\"\",\"exit_code\":0}","tool_call_id":"c1","timestamp":12},
         {"id":4,"role":"assistant","content":"Done."},
         {"id":5,"role":"user","content":"What's in it?"},
         {"id":6,"role":"assistant","content":"","tool_calls":[{"id":"c2","function":{"name":"read_file","arguments":"{}"}}]},
         {"id":7,"role":"tool","content":"text","tool_call_id":"c2"},
         {"id":8,"role":"assistant","content":"A config."}]
        """#))
        let items = ChatTimeline.items(s, compact: false)
        #expect(items.map(\.id) == ["h-1", "h-4", "k-2", "h-5", "h-8"]) // no command in the second turn: no chip row
        guard case .thinking(_, let steps, let commands) = items[2] else { Issue.record("no chip row"); return }
        #expect(steps.isEmpty && commands.map(\.command) == ["systemctl restart x"] && commands.first?.exitCode == 0)
        #expect(TerminalTranscript.summary(of: commands).commandCount == 1)
    }

    @Test func aRunningTurnShowsItsThinkingOnlyOnceItEnds() {
        var s = SessionState(id: "s1")
        s.run = ActiveRun(id: "run_1", status: .running)
        s.applyHistory(Array(Self.thinking.prefix(4)))
        #expect(ChatTimeline.items(s, compact: false).map(\.id) == ["h-1"])
    }

    @Test func argumentSummaries() {
        #expect(ChatTimeline.argumentSummary(#"{"path":"/a/b.swift","offset":3}"#) == "/a/b.swift")
        #expect(ChatTimeline.argumentSummary(#"{"zeta":"z","alpha":"a"}"#) == "a")
        #expect(ChatTimeline.argumentSummary(#"{"command":"\#(String(repeating: "x", count: 50))"}"#) == String(repeating: "x", count: 39) + "…")
        #expect(ChatTimeline.argumentSummary("not json") == "" && ChatTimeline.argumentSummary(nil) == "")
    }

    @Test func latestThoughtIsTheNewestOfTheTurnStillGoing() {
        #expect(ChatTimeline.latestThought(Array(Self.thinking.prefix(5))) == "Press each one.")
        #expect(ChatTimeline.latestThought(Array(Self.thinking.prefix(2))) == "Read the tree first.")
        #expect(ChatTimeline.latestThought(Array(Self.thinking.prefix(7))) == nil) // the new prompt has none yet
        #expect(ChatTimeline.latestThought(Array(Self.thinking[1...2])) == "Read the tree first.") // no prompt in the page
    }
}

@Suite struct EffortRESTTests {
    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: relayURL, token: fakeToken, http: http), http)
    }

    @Test func effortsSkipUnknownValuesAndAMissingEndpointHasNone() async throws {
        let (api, _) = rest { _ in (200, #"{"sessions":{"a":"xhigh","b":"none","c":"turbo","d":null}}"#) }
        #expect(try await api.sessionEfforts() == ["a": .xhigh, "b": Effort.none])
        let (old, _) = rest { _ in (404, #"{"error":{"code":"not_found","message":"not found"}}"#) }
        #expect(try await old.sessionEfforts() == [:])
    }

    @Test func setEffortSendsItsWireValueOrNull() async throws {
        let (api, http) = rest { r in
            let sent = r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) }
            return (200, sent == .object(["effort": .null]) ? #"{"effort":null}"# : #"{"effort":"xhigh"}"#)
        }
        #expect(try await api.setEffort("a1", .xhigh) == .xhigh)
        #expect(try await api.setEffort("a1", nil) == nil)
        let bodies = http.requests.current.map { r in r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) } }
        #expect(http.requests.current.map { "\($0.httpMethod!) \($0.url!.path)" } == ["PUT /api/sessions/a1/effort", "PUT /api/sessions/a1/effort"])
        let sent: [JSONValue?] = [.object(["effort": .string("xhigh")]), .object(["effort": .null])]
        #expect(bodies == sent)
    }

    @Test func labelsAndReasoning() {
        #expect(Effort.allCases.map(\.label) == ["Off", "Low", "Medium", "High", "Extra high", "Max"])
        let catalog = ModelCatalog(current: ModelChoice(provider: "a", model: "x"), providers: [
            try! Wire.decode(ModelCatalog.Provider.self, from: Data(#"{"slug":"a","name":"A","models":[{"id":"x","reasoning":false},{"id":"y"}]}"#.utf8)),
        ])
        #expect(!catalog.reasons(ModelChoice(provider: "a", model: "x")))
        #expect(catalog.reasons(ModelChoice(provider: "a", model: "y")) && catalog.reasons(ModelChoice(provider: "b", model: "x")))
    }
}

/// The store's efforts and the WORKING line's thought, against a fake relay and a test clock.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct EffortStoreTests {
    let clock = TestClock()
    let refuse = Watched<Bool>(false)
    /// The thought the next history page holds.
    let thought = Watched<String>("Read the tree first.")
    let http: FakeHTTP
    let store: SessionStore

    init() {
        let (refuse, thought) = (refuse, thought)
        http = FakeHTTP { r in
            switch (r.httpMethod ?? "", r.url?.path ?? "") {
            case ("GET", "/api/sessions"): return (200, #"{"data":[{"id":"s1","source":"api_server"}]}"#)
            case ("GET", "/api/session-efforts"): return (200, #"{"sessions":{"s1":"high"}}"#)
            case ("PUT", "/api/sessions/s1/effort"):
                return refuse.current ? (403, #"{"error":{"code":"read_only","message":"read-only session"}}"#) : (200, #"{"effort":"max"}"#)
            case ("DELETE", "/api/sessions/s1"): return (200, #"{"deleted":true}"#)
            case ("GET", "/api/sessions/s1/messages"):
                if r.url?.query?.contains("order=latest") == true {
                    return (200, #"{"data":[{"id":1,"role":"user","content":"go"},{"id":2,"role":"assistant","content":"","reasoning":"\#(thought.current)\nmore"}]}"#)
                }
                return (200, #"{"data":[]}"#)
            default: return (404, #"{"error":{"code":"not_found","message":"not found"}}"#)
            }
        }
        let clock = clock
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: FakeTransport(), sleep: { try await clock.sleep(for: $0) })
        store = SessionStore(
            client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http), sleep: { try await clock.sleep(for: $0) })
    }

    @Test func effortsLoadWithTheModelsAndSetIsOptimisticWithRollback() async throws {
        try await store.refreshSessions()
        #expect(store.sessionEfforts == ["s1": .high])
        try await store.setEffort("s1", .medium)
        #expect(store.sessionEfforts["s1"] == .max) // what the relay stored
        refuse.mutate { $0 = true }
        await #expect(throws: RelayAPIError.self) { try await store.setEffort("s1", nil) }
        #expect(store.sessionEfforts["s1"] == .max)
        refuse.mutate { $0 = false }
        try await store.deleteSession("s1")
        #expect(store.sessionEfforts["s1"] == nil)
    }

    func latestFetches() -> Int { http.requests.current.filter { $0.url?.query?.contains("order=latest") == true }.count }

    func completed(_ seq: Int, run: String = "run_1") async {
        await store.handle(.message(.event(event("s1", seq, run: run, .toolCompleted(ToolCompleted(tool: "terminal", duration: 0.1, error: false))))))
    }

    @Test func theThoughtIsFetchedASecondAfterTheLastToolRoundAndClearedAtTheEnd() async throws {
        await store.open("s1")
        await store.handle(.message(.event(event("s1", 1, .toolStarted(ToolStarted(tool: "terminal"))))))
        await completed(2)
        await completed(3) // debounced: one fetch for both
        await clock.fire(.seconds(1))
        await http.requests.wait { reqs in reqs.contains { $0.url?.query?.contains("order=latest") == true } }
        while store.sessions["s1"]?.thought == nil { await Task.yield() }
        #expect(store.sessions["s1"]?.thought == "Read the tree first." && latestFetches() == 1)
        #expect(store.sessions["s1"]?.events.count == 3) // the live timeline stays
        await store.handle(.message(.event(event("s1", 4, .runCompleted))))
        #expect(store.sessions["s1"]?.thought == nil)
    }
}
