import Foundation
import Testing
@testable import TrismegistusKit

/// RelayClient against FakeTransport and TestClock: no network, no real time.
@Suite(.timeLimit(.minutes(1)))
struct RelayClientTests {
    let transport = FakeTransport()
    let clock = TestClock()
    let client: RelayClient

    init() {
        let clock = clock
        client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport,
                             sleep: { try await clock.sleep(for: $0) }, jitter: { 0 }, now: clock.date)
    }

    static let ready = ServerMessage.ready(device: "macbook", serverVersion: "0.1.0")

    /// Waits for the index-th connection's auth and answers ready.
    func connect(_ index: Int) async -> FakeConnection {
        let c = await transport.connection(index)
        #expect(await c.sent(1).first == .auth(token: fakeToken))
        c.push(Self.ready)
        return c
    }

    @Test func authThenReady() async throws {
        var out = client.outputs.makeAsyncIterator()
        await client.start()
        let c = await transport.connection(0)
        #expect(transport.urls.current == [URL(string: "wss://relay.invalid/ws")!])
        #expect(await c.sent(1) == [.auth(token: fakeToken)])
        await #expect(throws: RelayClient.SendError.notConnected) { try await client.send(.stop(runID: "run_1")) }
        c.push(Self.ready)
        #expect(await out.next() == .state(.connecting))
        #expect(await out.next() == .message(Self.ready))
        #expect(await out.next() == .state(.connected(device: "macbook", serverVersion: "0.1.0")))
        try await client.send(.stop(runID: "run_1"))
        #expect(await c.sent(2).last == .stop(runID: "run_1"))
    }

    @Test func authRejectedIsSurfacedAndNeverRetried() async {
        var out = client.outputs.makeAsyncIterator()
        await client.start()
        let c = await transport.connection(0)
        _ = await c.sent(1)
        c.push(.error(code: .unauthorized, message: "unauthorized"))
        c.drop()
        #expect(await out.next() == .state(.connecting))
        #expect(await out.next() == .message(.error(code: .unauthorized, message: "unauthorized")))
        #expect(await out.next() == .state(.authFailed(message: "unauthorized")))
        #expect(await !client.isRunning)
        #expect(transport.connections.current.count == 1)
        #expect(clock.state.current.sleepers.isEmpty) // no backoff pending
    }

    @Test func subscribeReplaysThenLiveInOrder() async {
        var out = client.outputs.makeAsyncIterator()
        await client.subscribe("s1", afterSeq: 2)
        await client.start()
        let c = await connect(0)
        #expect(await c.sent(2).last == .subscribe(sessionID: "s1", afterSeq: 2))
        let frames: [ServerMessage] = [
            .event(event("s1", 3, .toolStarted(ToolStarted(tool: "terminal", preview: "date")))),
            .event(event("s1", 4, .toolCompleted(ToolCompleted(tool: "terminal", duration: 0.1, error: false)))),
            .run(runID: "run_1", sessionID: "s1", status: .running),
            .event(event("s1", 5, .answer(Answer(text: "2026")))),
        ]
        for f in frames { c.push(f) }
        #expect(await out.nextMessage() == Self.ready)
        for f in frames { #expect(await out.nextMessage() == f) }

        await client.subscribe("s2")
        #expect(await c.sent(3).last == .subscribe(sessionID: "s2", afterSeq: nil))
    }

    @Test func approvalIsAnsweredWithItsRequestID() async throws {
        var out = client.outputs.makeAsyncIterator()
        await client.subscribe("s1")
        await client.start()
        let c = await connect(0)
        let request = ApprovalRequest(requestID: "req_9", command: "rm -rf ~/scratch", description: "recursive delete",
                                      choices: [.once, .session, .deny])
        c.push(.event(event("s1", 1, run: "run_7", .approvalRequested(request))))
        _ = await out.nextMessage() // ready
        guard case .event(let e)? = await out.nextMessage(), case .approvalRequested(let req) = e.payload else {
            Issue.record("expected approval.requested")
            return
        }
        try await client.send(.approve(runID: e.runID, requestID: req.requestID, choice: .once))
        #expect(await c.sent(3).last == .approve(runID: "run_7", requestID: "req_9", choice: .once))
        // `always` has no case, so it can't be sent; the relay's own list of choices never has it either.
        #expect(ApprovalChoice.allCases == [.once, .session, .deny])
    }

    @Test func pongsKeepTheConnection() async {
        var out = client.outputs.makeAsyncIterator()
        await client.start()
        let c = await connect(0)
        _ = await out.nextMessage() // ready
        for round in 1...3 {
            await clock.fire(RelayClient.pingInterval)
            #expect(await c.sent(1 + round).last == .ping)
            c.push(.pong)
            #expect(await out.nextMessage() == .pong)
        }
        #expect(c.state.current.closeCode == nil)
        #expect(transport.connections.current.count == 1)
    }

    @Test func missedPongsDropAndReconnectWithBackoffFromTheLastSeq() async {
        var out = client.outputs.makeAsyncIterator()
        await client.subscribe("s1")
        await client.subscribe("s2", afterSeq: 7)
        await client.start()
        let c0 = await connect(0)
        c0.push(.event(event("s1", 4, .steerQueued)), .event(event("s2", 9, .runCompleted)))
        _ = await out.nextMessage() // ready
        _ = await out.nextMessage()
        _ = await out.nextMessage()

        // Ping at 25 s and 50 s go unanswered; at 75 s the second miss drops the socket, like the relay does.
        await clock.fire(RelayClient.pingInterval)
        await clock.fire(RelayClient.pingInterval)
        #expect(c0.state.current.closeCode == nil)
        await clock.fire(RelayClient.pingInterval)
        #expect(await c0.waitClosed() == 1001)

        await clock.fire(.seconds(1))
        let c1 = await connect(1)
        let resubscribed = await c1.sent(3).dropFirst()
        #expect(resubscribed.contains(.subscribe(sessionID: "s1", afterSeq: 4)))
        #expect(resubscribed.contains(.subscribe(sessionID: "s2", afterSeq: 9)))

        // Never got a pong: the next wait doubles.
        c1.drop()
        await clock.fire(.seconds(2))
        let c2 = await connect(2)
        await clock.fire(RelayClient.pingInterval)
        _ = await c2.sent(4)
        c2.push(.pong)
        while await out.nextMessage() != .pong {}
        // A pong made the connection stable: back to 1 s.
        c2.drop()
        await clock.fire(.seconds(1))
        _ = await connect(3)
        let backoffs = clock.state.current.requested.filter { $0 < RelayClient.readyTimeout }
        #expect(backoffs == [.seconds(1), .seconds(2), .seconds(1)])
    }

    @Test func serverCloseReconnects() async {
        var out = client.outputs.makeAsyncIterator()
        await client.start()
        let c0 = await connect(0)
        #expect(await out.nextState() == .connecting)
        #expect(await out.nextState() == .connected(device: "macbook", serverVersion: "0.1.0"))
        c0.drop()
        #expect(await out.nextState() == .reconnecting(attempt: 1, at: Date(timeIntervalSince1970: 1)))
        await clock.fire(.seconds(1))
        _ = await connect(1)
        #expect(await out.nextState() == .connecting)
        #expect(await out.nextState() == .connected(device: "macbook", serverVersion: "0.1.0"))
    }

    @Test func reconnectingCarriesAttemptAndJitteredTime() async {
        let clock = clock
        // 0.625 makes the jitter 1/8 of the wait, exact in binary: 1.125 s, 2.25 s, 4.5 s.
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport,
                                 sleep: { try await clock.sleep(for: $0) }, jitter: { 0.625 }, now: clock.date)
        var out = client.outputs.makeAsyncIterator()
        await client.start()
        var at = 0.0
        for (attempt, wait) in [(1, 1.125), (2, 2.25), (3, 4.5)] {
            await connect(attempt - 1).drop() // never stable: the wait keeps doubling
            while case let s? = await out.nextState(), s != .reconnecting(attempt: attempt, at: Date(timeIntervalSince1970: at + wait)) {
                if case .reconnecting = s { Issue.record("unexpected \(s)") }
            }
            await clock.fire(.milliseconds(Int(wait * 1000)))
            at += wait
        }
        #expect(await out.nextState() == .connecting)
    }

    @Test func retryNowSkipsTheWaitOnly() async {
        var out = client.outputs.makeAsyncIterator()
        await client.subscribe("s1")
        await client.start()
        let c0 = await connect(0)
        c0.push(.event(event("s1", 3, .steerQueued)))
        _ = await out.nextMessage() // ready
        _ = await out.nextMessage()
        await client.retryNow() // connected: nothing happens
        c0.drop()
        while await out.nextState() != .reconnecting(attempt: 1, at: Date(timeIntervalSince1970: 1)) {}

        await client.retryNow() // no clock advance
        let c1 = await connect(1)
        #expect(await c1.sent(2).last == .subscribe(sessionID: "s1", afterSeq: 3))
        #expect(clock.state.current.sleepers.allSatisfy { $0.duration != .seconds(1) }) // the wait was cancelled
        #expect(transport.connections.current.count == 2)

        // The attempt count goes on: the next wait is 2 s.
        c1.drop()
        while await out.nextState() != .reconnecting(attempt: 2, at: Date(timeIntervalSince1970: 2)) {}
        await clock.fire(.seconds(2))
        _ = await connect(2)
    }

    @Test func retryNowAfterAuthFailureDoesNothing() async {
        var out = client.outputs.makeAsyncIterator()
        await client.start()
        let c = await transport.connection(0)
        _ = await c.sent(1)
        c.push(.error(code: .unauthorized, message: "unauthorized"))
        while await out.nextState() != .authFailed(message: "unauthorized") {}
        await client.retryNow()
        #expect(await !client.isRunning)
        #expect(transport.connections.current.count == 1)
    }

    @Test func noReadyInTimeReconnects() async {
        await client.start()
        let c0 = await transport.connection(0)
        _ = await c0.sent(1)
        await clock.fire(RelayClient.readyTimeout)
        _ = await c0.waitClosed()
        await clock.fire(.seconds(1))
        _ = await connect(1)
    }

    @Test func replayGapResubscribesLive() async {
        var out = client.outputs.makeAsyncIterator()
        await client.subscribe("s1", afterSeq: 40)
        await client.start()
        let c = await connect(0)
        #expect(await c.sent(2).last == .subscribe(sessionID: "s1", afterSeq: 40))
        let gap = ServerMessage.error(code: .replayGap, message: "reload the history", ref: "s1")
        c.push(gap)
        #expect(await c.sent(3).last == .subscribe(sessionID: "s1", afterSeq: nil))
        _ = await out.nextMessage() // ready
        #expect(await out.nextMessage() == gap)
    }

    @Test func stopClosesAndStaysDown() async {
        var out = client.outputs.makeAsyncIterator()
        await client.start()
        let c = await connect(0)
        #expect(await out.nextState() == .connecting)
        #expect(await out.nextState() == .connected(device: "macbook", serverVersion: "0.1.0"))
        await client.stop()
        #expect(await c.waitClosed() == 1000)
        #expect(await out.nextState() == .disconnected)
        #expect(await !client.isRunning)
    }
}
