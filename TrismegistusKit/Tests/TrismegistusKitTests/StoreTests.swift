import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

func history(_ json: String) -> [HistoryMessage] {
    try! Wire.decode([HistoryMessage].self, from: Data(json.utf8))
}

let answeredHistory = history(#"""
[{"id":1,"role":"user","content":"What year is it?"},{"id":2,"role":"assistant","content":"It is 2026."}]
"""#)

/// The pure rules on SessionState.
@Suite struct SessionStateTests {
    @Test func duplicateSeqIsIgnored() {
        var s = SessionState(id: "s1")
        for seq in [1, 2, 2, 1, 3] { s.apply(.event(event("s1", seq, .steerQueued))) }
        s.apply(.event(event("s2", 4, .steerQueued))) // another session's
        #expect(s.events.map(\.seq) == [1, 2, 3])
        #expect(s.lastSeq == 3)
    }

    /// trismegistus #10: after replay_gap, events starting again from seq 1 must be applied.
    @Test func replayGapResetsTheSeqAndAsksForHistory() {
        var s = SessionState(id: "s1")
        s.applyHistory([])
        s.apply(.event(event("s1", 40, .runCompleted)))
        s.apply(.error(code: .replayGap, message: "reload the history", ref: "other"))
        #expect(s.lastSeq == 40 && s.historyLoaded)
        s.apply(.error(code: .replayGap, message: "reload the history", ref: "s1"))
        #expect(s.lastSeq == 0 && !s.historyLoaded)
        s.applyHistory(answeredHistory)
        s.apply(.event(event("s1", 1, run: "run_2", .toolStarted(ToolStarted(tool: "terminal")))))
        s.apply(.event(event("s1", 2, run: "run_2", .answer(Answer(text: "done")))))
        #expect(s.events.map(\.seq) == [1, 2])
        #expect(s.lastSeq == 2)
    }

    /// trismegistus #11: live answer and run.completed, then the history (which has the answer): one answer.
    @Test func lateHistoryDoesNotDuplicateAFinishedTurn() {
        var s = SessionState(id: "s1")
        s.outbox.append(OutgoingPrompt(id: "c1", text: "What year is it?", status: .pending))
        s.apply(.ack(clientMsgID: "c1", runID: "run_1", replayed: false))
        #expect(s.run == ActiveRun(id: "run_1", status: .running))
        s.apply(.event(event("s1", 1, .toolStarted(ToolStarted(tool: "terminal")))))
        s.apply(.event(event("s1", 2, .answer(Answer(text: "It is 2026.")))))
        s.apply(.event(event("s1", 3, .runCompleted)))
        #expect(s.run == nil)
        s.applyHistory(answeredHistory)
        let liveAnswers = s.events.filter { $0.kind == "answer" }.count
        let historyAnswers = s.history.filter { $0.role == .assistant && $0.content == "It is 2026." }.count
        #expect(liveAnswers + historyAnswers == 1)
        #expect(s.events.isEmpty && s.outbox.isEmpty)
        // A late repeat of an old event stays out too.
        s.apply(.event(event("s1", 2, .answer(Answer(text: "It is 2026.")))))
        #expect(s.events.isEmpty)
    }

    @Test func lateHistoryKeepsTheRunningTurnAndUnsentPrompts() {
        var s = SessionState(id: "s1")
        s.outbox.append(OutgoingPrompt(id: "c2", text: "and next year?", status: .pending))
        s.apply(.event(event("s1", 1, .runCompleted)))
        s.apply(.event(event("s1", 2, run: "run_2", .toolStarted(ToolStarted(tool: "terminal")))))
        s.applyHistory(answeredHistory)
        #expect(s.events.map(\.seq) == [2])
        #expect(s.outbox.map(\.id) == ["c2"])
    }

    @Test func approvalsFollowRequestResolveAndRunEnd() {
        var s = SessionState(id: "s1")
        let request = ApprovalRequest(requestID: "req_1", command: "rm -rf x", choices: [.once, .deny])
        s.apply(.event(event("s1", 1, .approvalRequested(request))))
        #expect(s.approvals.map(\.id) == ["req_1"] && s.run?.status == .waitingForApproval)
        s.apply(.event(event("s1", 2, .approvalResolved(ApprovalResolved(requestID: "req_1", choice: "once")))))
        #expect(s.approvals.isEmpty && s.run?.status == .running)
        s.apply(.event(event("s1", 3, .approvalRequested(ApprovalRequest(requestID: "req_2", command: "x", choices: [.deny])))))
        s.apply(.event(event("s1", 4, .runFailed(error: "provider error"))))
        #expect(s.approvals.isEmpty && s.run == nil)
    }

    @Test func runMessagesSetAndEndTheRun() {
        var s = SessionState(id: "s1")
        s.apply(.run(runID: "run_1", sessionID: "s1", status: .running))
        s.apply(.run(runID: "run_1", sessionID: "s2", status: .completed))
        s.apply(.run(runID: "run_0", sessionID: "s1", status: .completed))
        #expect(s.run == ActiveRun(id: "run_1", status: .running))
        s.apply(.run(runID: "run_1", sessionID: "s1", status: .cancelled))
        #expect(s.run == nil)
    }

    @Test func promptErrorsMarkTheOutbox() {
        var s = SessionState(id: "s1")
        s.outbox.append(OutgoingPrompt(id: "c1", text: "hi", status: .pending))
        s.apply(.error(code: .busy, message: "a run is already active in this session", ref: "c1"))
        #expect(s.outbox.first?.status == .failed(code: .busy, message: "a run is already active in this session"))
        s.outbox.append(OutgoingPrompt(id: "c2", text: "hi again", status: .pending))
        s.apply(.ack(clientMsgID: "c2", runID: "run_5", replayed: true))
        #expect(s.outbox.last?.status == .sent(runID: "run_5"))
        #expect(s.run == nil) // replayed: the run may be long over
    }
}

/// SessionStore with an unstarted RelayClient and FakeHTTP; outputs are fed through handle(_:).
@MainActor @Suite(.timeLimit(.minutes(1)))
struct SessionStoreTests {
    let transport = FakeTransport()
    let http = FakeHTTP { r in
        switch (r.httpMethod ?? "", r.url?.path ?? "") {
        case ("GET", "/api/sessions/s1/messages"), ("GET", "/api/sessions/s2/messages"):
            (200, #"{"object":"list","data":[{"id":1,"role":"user","content":"What year is it?"},{"id":2,"role":"assistant","content":"It is 2026."}]}"#)
        case ("GET", "/api/sessions"):
            (200, #"{"data":[{"id":"s1","source":"api_server","title":"Dates"}]}"#)
        case ("POST", "/api/sessions"):
            (201, #"{"session":{"id":"s3","source":"api_server"}}"#)
        case ("PATCH", "/api/sessions/s1"):
            (200, #"{"session":{"id":"s1","title":"Years"}}"#)
        case ("DELETE", "/api/sessions/s1"):
            (200, #"{"deleted":true}"#)
        default:
            (404, #"{"error":{"code":"not_found","message":"not found"}}"#)
        }
    }
    let clock = TestClock() // never advanced: no timer fires
    let store: SessionStore

    init() {
        let clock = clock
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport,
                                 sleep: { try await clock.sleep(for: $0) })
        store = SessionStore(client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http))
    }

    /// start() wires the client's outputs into handle(_:): a replay_gap from the socket reloads history over REST.
    @Test func feedWiresTheClientToTheStore() async {
        await store.open("s1")
        store.start()
        let c = await transport.connection(0)
        _ = await c.sent(1)
        c.push(.ready(device: "macbook", serverVersion: "0.1.0"))
        #expect(await c.sent(2).last == .subscribe(sessionID: "s1", afterSeq: nil))
        c.push(.error(code: .replayGap, message: "reload the history", ref: "s1"))
        await http.requests.wait { $0.count >= 2 }
        #expect(historyLoads("s1") == 2)
        await store.stop()
    }

    func historyLoads(_ id: String) -> Int {
        http.requests.current.filter { $0.url?.path == "/api/sessions/\(id)/messages" }.count
    }

    /// trismegistus #10 end to end: replay_gap -> history reloaded over REST -> events from seq 1 shown.
    @Test func replayGapReloadsHistoryOverREST() async {
        await store.open("s1")
        #expect(historyLoads("s1") == 1 && store.sessions["s1"]?.historyLoaded == true)
        await store.handle(.message(.event(event("s1", 40, .runCompleted))))
        await store.handle(.message(.error(code: .replayGap, message: "reload the history", ref: "s1")))
        #expect(historyLoads("s1") == 2)
        #expect(store.sessions["s1"]?.historyLoaded == true && store.sessions["s1"]?.history.count == 2)
        await store.handle(.message(.event(event("s1", 1, run: "run_2", .toolStarted(ToolStarted(tool: "terminal"))))))
        #expect(store.sessions["s1"]?.events.map(\.seq) == [1])
    }

    @Test func reconnectReloadsSessionsThatCouldNotResume() async {
        await store.open("s1")
        await store.open("s2")
        await store.handle(.state(.connected(device: "macbook", serverVersion: "0.1.0")))
        await store.handle(.message(.event(event("s2", 5, .steerQueued))))
        await store.handle(.state(.disconnected))
        await store.handle(.state(.connected(device: "macbook", serverVersion: "0.1.0")))
        #expect(historyLoads("s1") == 2) // no seq: resubscribed live only, so reload
        #expect(historyLoads("s2") == 1) // resumed from seq 5
        #expect(store.connection == .connected(device: "macbook", serverVersion: "0.1.0"))
    }

    @Test func historyErrorIsKeptAndNotRetriedInALoop() async {
        await store.open("s9") // FakeHTTP: 404
        #expect(store.sessions["s9"]?.historyError == "not found")
        await store.handle(.message(.pong))
        #expect(historyLoads("s9") == 1)
    }

    @Test func promptWhileDisconnectedFails() async {
        await store.open("s1")
        let id = await store.sendPrompt("hi", to: "s1")
        #expect(store.sessions["s1"]?.outbox == [OutgoingPrompt(id: id, text: "hi", status: .failed(code: nil, message: "Not connected to the relay."))])
    }

    @Test func approvalsAcrossSessions() async {
        await store.open("s1")
        let request = ApprovalRequest(requestID: "req_1", command: "rm -rf x", choices: [.once, .session, .deny])
        await store.handle(.message(.event(event("s1", 1, .approvalRequested(request)))))
        #expect(store.pendingApprovals.map(\.id) == ["req_1"] && store.isWorking)
    }

    @Test func sessionListFollowsREST() async throws {
        try await store.refreshSessions()
        #expect(store.sessionList.map(\.id) == ["s1"])
        try await store.createSession()
        #expect(store.sessionList.map(\.id) == ["s3", "s1"])
        try await store.renameSession("s1", to: "Years")
        #expect(store.sessionList.last?.title == "Years")
        await store.open("s1")
        try await store.deleteSession("s1")
        #expect(store.sessionList.map(\.id) == ["s3"] && store.sessions["s1"] == nil)
    }
}
