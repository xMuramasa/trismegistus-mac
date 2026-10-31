import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

let t0 = Date(timeIntervalSince1970: 1_792_801_000) // before every event() timestamp

/// The pure row rules on SessionOverview.
@Suite struct SessionOverviewTests {
    @Test func runStartsCountsToolsAndEnds() {
        var o = SessionOverview(id: "s1")
        o.apply(.run(runID: "run_1", sessionID: "s1", status: .running), at: t0)
        o.apply(.event(event("s1", 1, .toolStarted(ToolStarted(tool: "terminal")))), at: t0)
        o.apply(.event(event("s1", 2, .toolCompleted(ToolCompleted(tool: "terminal", duration: 0.1, error: false)))), at: t0)
        o.apply(.event(event("s1", 3, .toolStarted(ToolStarted(tool: "read_file")))), at: t0)
        o.apply(.event(event("s1", 3, .toolStarted(ToolStarted(tool: "read_file")))), at: t0) // repeat
        o.apply(.event(event("s2", 9, .toolStarted(ToolStarted(tool: "terminal")))), at: t0) // another session's
        #expect(o.run == SessionOverview.Run(id: "run_1", status: .running, startedAt: t0, toolCount: 2))
        #expect(o.lastActivity == Date(timeIntervalSince1970: 1_792_801_004.586))
        o.apply(.event(event("s1", 4, .runCompleted)), at: t0)
        #expect(o.run == nil && o.lastSeq == 4)
        o.apply(.run(runID: "run_2", sessionID: "s1", status: .running), at: t0)
        o.apply(.run(runID: "run_2", sessionID: "s1", status: .cancelled), at: t0)
        #expect(o.run == nil)
    }

    @Test func approvalWaitsUntilResolvedOrTheRunEnds() {
        var o = SessionOverview(id: "s1")
        let request = ApprovalRequest(requestID: "req_1", command: "rm -rf x", choices: [.once, .deny])
        o.apply(.event(event("s1", 1, .approvalRequested(request))), at: t0)
        #expect(o.pendingApproval?.id == "req_1" && o.run?.status == .waitingForApproval && o.isWaitingForApproval)
        o.apply(.event(event("s1", 2, .approvalResolved(ApprovalResolved(requestID: "req_1", choice: "once")))), at: t0)
        #expect(o.pendingApproval == nil && o.run?.status == .running && !o.isWaitingForApproval)
        o.apply(.event(event("s1", 3, .approvalRequested(ApprovalRequest(requestID: "req_2", command: "x", choices: [.deny])))), at: t0)
        o.apply(.event(event("s1", 4, .runFailed(error: "provider error"))), at: t0)
        #expect(o.approvals.isEmpty && o.run == nil)
    }

    /// Subscribed mid-run without a seq: the relay's `run` status is all there is.
    @Test func runStatusFromSubscribeAndReplayGap() {
        var o = SessionOverview(id: "s1", info: SessionInfo(id: "s1", source: "telegram", lastActive: 1_792_801_100))
        o.apply(.run(runID: "run_1", sessionID: "s1", status: .waitingForApproval), at: t0)
        #expect(o.isWaitingForApproval && o.pendingApproval == nil)
        #expect(o.isReadOnly && o.source == "telegram" && o.lastActivity == Date(timeIntervalSince1970: 1_792_801_100))
        o.apply(.event(event("s1", 40, .steerQueued)), at: t0)
        o.apply(.error(code: .replayGap, message: "reload the history", ref: "s1"), at: t0)
        #expect(o.lastSeq == 0 && o.run == nil)
        o.apply(.event(event("s1", 1, run: "run_2", .toolStarted(ToolStarted(tool: "terminal")))), at: t0)
        #expect(o.run?.id == "run_2" && o.run?.toolCount == 1)
    }

    @Test func replayedEventsDateTheRunStart() {
        var o = SessionOverview(id: "s1")
        o.apply(.run(runID: "run_1", sessionID: "s1", status: .running), at: t0.addingTimeInterval(60))
        o.apply(.event(event("s1", 5, .toolStarted(ToolStarted(tool: "terminal")))), at: t0)
        #expect(o.run?.startedAt == Date(timeIntervalSince1970: 1_792_801_004.588))
    }
}

/// SessionStore following the whole list over FakeTransport, FakeHTTP and TestClock.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct OverviewTests {
    let transport = FakeTransport()
    let clock = TestClock()
    /// The REST list, most recent first (served oldest first, so the store has to sort).
    let list = Watched<[String]>(["s1", "s2", "s3", "s4", "s5"])
    let http: FakeHTTP
    let store: SessionStore

    init() {
        let list = list
        http = FakeHTTP { r in
            switch (r.httpMethod ?? "", r.url?.path ?? "") {
            case ("GET", "/api/sessions"):
                let items = list.current.enumerated().reversed().map { i, id in
                    #"{"id":"\#(id)","source":"api_server","last_active":\#(1_792_800_000 - i)}"#
                }
                return (200, #"{"data":[\#(items.joined(separator: ","))]}"#)
            case ("POST", "/api/sessions"):
                return (201, #"{"session":{"id":"new","source":"api_server"}}"#)
            case ("DELETE", _):
                return (200, #"{"deleted":true}"#)
            default: // a session's messages
                return (200, #"{"object":"list","data":[]}"#)
            }
        }
        let clock = clock
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport,
                                 sleep: { try await clock.sleep(for: $0) }, jitter: { 0 })
        store = SessionStore(client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http), now: { t0 })
    }

    /// Starts the store (once) and answers the index-th connection's auth.
    func connect(_ index: Int) async -> FakeConnection {
        store.start()
        let c = await transport.connection(index)
        _ = await c.sent(1)
        c.push(.ready(device: "macbook", serverVersion: "0.1.0"))
        return c
    }

    /// What c sent after auth, once that is count messages.
    func subscriptions(_ c: FakeConnection, _ count: Int) async -> [ClientMessage] {
        Array(await c.sent(count + 1).dropFirst())
    }

    /// Lets the store's feed catch up.
    func until(_ check: () -> Bool) async {
        while !check() { await Task.yield() }
    }

    func subscribe(_ ids: [String]) -> [ClientMessage] { ids.map { .subscribe(sessionID: $0) } }

    @Test func fiveSessionsLiveRunAndApproval() async throws {
        try await store.refreshSessions()
        let c = await connect(0)
        #expect(await subscriptions(c, 5) == subscribe(["s1", "s2", "s3", "s4", "s5"]))
        let request = ApprovalRequest(requestID: "req_1", command: "rm -rf x", choices: [.once, .session, .deny])
        c.push(.run(runID: "run_1", sessionID: "s2", status: .running),
               .event(event("s2", 1, .toolStarted(ToolStarted(tool: "terminal")))),
               .event(event("s4", 1, run: "run_2", .approvalRequested(request))))
        await until { store.overview["s4"]?.pendingApproval != nil && store.overview["s2"]?.run?.toolCount == 1 }
        #expect(store.activity == .approvalWaiting)
        #expect(store.pendingApprovals.map(\.id) == ["req_1"] && store.sessions.isEmpty)
        #expect(store.overview["s2"]?.run == SessionOverview.Run(id: "run_1", status: .running, startedAt: t0, toolCount: 1))
        #expect(store.overview["s1"]?.run == nil && store.overview["s1"]?.source == "api_server")

        c.push(.event(event("s4", 2, run: "run_2", .approvalResolved(ApprovalResolved(requestID: "req_1", choice: "once")))),
               .event(event("s4", 3, run: "run_2", .runCompleted)))
        await until { store.overview["s4"]?.lastSeq == 3 }
        #expect(store.activity == .running)
        c.push(.event(event("s2", 2, .runCancelled(reason: "stopped"))))
        await until { store.overview["s2"]?.lastSeq == 2 }
        #expect(store.activity == .idle)
        await store.stop()
    }

    @Test func reconnectResubscribesAllFromTheirSeqs() async throws {
        try await store.refreshSessions()
        let c0 = await connect(0)
        _ = await subscriptions(c0, 5)
        c0.push(.event(event("s1", 3, .steerQueued)), .event(event("s3", 7, .runCompleted)),
                .event(event("s5", 2, .steerQueued)), .run(runID: "run_9", sessionID: "s2", status: .running))
        await until { store.overview["s2"]?.run != nil && store.overview["s5"]?.lastSeq == 2 }
        c0.drop()
        await clock.fire(.seconds(1))
        let c1 = await connect(1)
        #expect(await subscriptions(c1, 5) == [
            .subscribe(sessionID: "s1", afterSeq: 3), .subscribe(sessionID: "s2"), .subscribe(sessionID: "s3", afterSeq: 7),
            .subscribe(sessionID: "s4"), .subscribe(sessionID: "s5", afterSeq: 2),
        ])
        // s2 was resubscribed live: its run may be over, and the relay re-sends it if not.
        await until { store.overview["s2"]?.run == nil }
        c1.push(.run(runID: "run_9", sessionID: "s2", status: .running))
        await until { store.overview["s2"]?.run != nil }
        #expect(store.activity == .running)
        await store.stop()
    }

    @Test func listChangesAddAndDropSubscriptions() async throws {
        list.mutate { $0 = ["s1", "s2"] }
        try await store.refreshSessions()
        let c = await connect(0)
        _ = await subscriptions(c, 2)
        list.mutate { $0 = ["s3", "s1"] }
        try await store.refreshSessions()
        #expect(await subscriptions(c, 4).suffix(2) == [.unsubscribe(sessionID: "s2"), .subscribe(sessionID: "s3")])
        #expect(Set(store.overview.keys) == ["s1", "s3"])
        try await store.createSession()
        #expect(await subscriptions(c, 5).last == .subscribe(sessionID: "new"))
        try await store.deleteSession("s1")
        #expect(await subscriptions(c, 6).last == .unsubscribe(sessionID: "s1"))
        #expect(Set(store.overview.keys) == ["s3", "new"])
        // Closing a listed session keeps its row live.
        await store.open("s3")
        await store.close("s3")
        #expect(c.state.current.sent.count == 7)
        await store.stop()
    }

    @Test func the65thSessionIsNotSubscribed() async throws {
        list.mutate { $0 = (1...65).map { "s\($0)" } }
        try await store.refreshSessions()
        let c = await connect(0)
        #expect(await subscriptions(c, 64) == subscribe((1...64).map { "s\($0)" }))
        #expect(store.overview["s65"] != nil)
        // Opening it takes the slot of the oldest followed one.
        await store.open("s65")
        #expect(await subscriptions(c, 66).suffix(2) == [.unsubscribe(sessionID: "s64"), .subscribe(sessionID: "s65")])
        await store.stop()
    }

    /// trismegistus #10 among many subscriptions: only the gapped session restarts, its history is reloaded if open.
    @Test func replayGapAmongManySubscriptions() async throws {
        try await store.refreshSessions()
        await store.open("s3")
        let c0 = await connect(0)
        #expect(await subscriptions(c0, 5) == subscribe(["s3", "s1", "s2", "s4", "s5"]))
        c0.push(.event(event("s1", 4, .steerQueued)), .event(event("s3", 9, .steerQueued)),
                .error(code: .replayGap, message: "reload the history", ref: "s3"))
        #expect(await subscriptions(c0, 6).last == .subscribe(sessionID: "s3"))
        await http.requests.wait { $0.filter { $0.url?.path == "/api/sessions/s3/messages" }.count == 2 }
        await until { store.sessions["s3"]?.historyLoaded == true }
        #expect(store.overview["s3"]?.lastSeq == 0 && store.overview["s1"]?.lastSeq == 4)
        c0.drop()
        await clock.fire(.seconds(1))
        let c1 = await connect(1)
        #expect(await subscriptions(c1, 5).prefix(2) == [.subscribe(sessionID: "s3"), .subscribe(sessionID: "s1", afterSeq: 4)])
        await store.stop()
    }

    /// Opening a followed session starts it from the row (the relay won't repeat the run's status); #11 still holds.
    @Test func openingAFollowedSessionStartsFromItsRow() async throws {
        try await store.refreshSessions()
        let c = await connect(0)
        _ = await subscriptions(c, 5)
        c.push(.run(runID: "run_1", sessionID: "s2", status: .running),
               .event(event("s2", 1, .toolStarted(ToolStarted(tool: "terminal")))))
        await until { store.overview["s2"]?.lastSeq == 1 }
        await store.open("s2")
        #expect(store.sessions["s2"]?.run == ActiveRun(id: "run_1", status: .running))
        #expect(c.state.current.sent.count == 6) // no second subscribe
        c.push(.event(event("s2", 2, .toolStarted(ToolStarted(tool: "terminal")))))
        await until { store.sessions["s2"]?.lastSeq == 2 }
        #expect(store.sessions["s2"]?.events.map(\.seq) == [2] && store.sessions["s2"]?.historyLoaded == true)
        await store.stop()
    }
}
