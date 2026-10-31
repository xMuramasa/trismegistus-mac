import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TrismegistusKit

let fakeToken = "trs_FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAK"
let relayURL = URL(string: "https://relay.invalid")!

/// Shared state tests wait on without real time: wait(until:) resumes as soon as a mutation makes the check true.
final class Watched<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    private var waiters: [(check: (Value) -> Bool, resume: CheckedContinuation<Void, Never>)] = []

    init(_ value: Value) { self.value = value }

    var current: Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    func mutate<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        let result = try body(&value)
        let snapshot = value
        waiters.removeAll { w in
            guard w.check(snapshot) else { return false }
            w.resume.resume()
            return true
        }
        return result
    }

    func wait(until check: @escaping @Sendable (Value) -> Bool) async {
        await withCheckedContinuation { c in
            lock.lock()
            defer { lock.unlock() }
            if check(value) { c.resume() } else { waiters.append((check, c)) }
        }
    }
}

/// Time for RelayClient: sleeps end only when the test advances the clock.
final class TestClock: Sendable {
    struct Sleeper {
        let id: Int
        let deadline: Duration
        let duration: Duration
        let resume: CheckedContinuation<Void, any Error>
    }

    struct State {
        var now: Duration = .zero
        var nextID = 0
        var sleepers: [Sleeper] = []
        /// Every sleep asked for, in order (backoff assertions).
        var requested: [Duration] = []
    }

    let state = Watched(State())

    @Sendable func sleep(for duration: Duration) async throws {
        let id = state.mutate { s in
            s.nextID += 1
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                state.mutate { s in
                    if Task.isCancelled { return c.resume(throwing: CancellationError()) }
                    s.sleepers.append(Sleeper(id: id, deadline: s.now + duration, duration: duration, resume: c))
                    s.requested.append(duration)
                }
            }
        } onCancel: {
            state.mutate { s in
                if let i = s.sleepers.firstIndex(where: { $0.id == id }) {
                    s.sleepers.remove(at: i).resume.resume(throwing: CancellationError())
                }
            }
        }
    }

    /// Waits until something sleeps for `duration`, then moves time forward by it.
    func fire(_ duration: Duration) async {
        await state.wait { $0.sleepers.contains { $0.duration == duration } }
        state.mutate { s in
            s.now += duration
            let now = s.now
            for sleeper in s.sleepers where sleeper.deadline <= now { sleeper.resume.resume() }
            s.sleepers.removeAll { $0.deadline <= now }
        }
    }
}

struct Closed: Error {}

/// One scripted socket: the test pushes relay frames and reads what the client sent.
final class FakeConnection: WebSocketConnection {
    struct State {
        var inbox: [String] = []
        var sent: [String] = []
        var closeCode: Int?
    }

    let state = Watched(State())

    func send(_ text: String) async throws {
        try state.mutate { s in
            guard s.closeCode == nil else { throw Closed() }
            s.sent.append(text)
        }
    }

    func receive() async throws -> String {
        await state.wait { !$0.inbox.isEmpty || $0.closeCode != nil }
        return try state.mutate { s in
            guard !s.inbox.isEmpty else { throw Closed() }
            return s.inbox.removeFirst()
        }
    }

    func close(code: Int) async {
        state.mutate { s in if s.closeCode == nil { s.closeCode = code } }
    }

    // Test side.

    func push(_ messages: ServerMessage...) {
        state.mutate { s in s.inbox += messages.map { String(decoding: try! Wire.encode($0), as: UTF8.self) } }
    }

    func push(raw: String) { state.mutate { $0.inbox.append(raw) } }

    /// The relay or the network went away (1006: no close frame).
    func drop() { state.mutate { s in if s.closeCode == nil { s.closeCode = 1006 } } }

    /// Waits for the client's first `count` messages.
    func sent(_ count: Int) async -> [ClientMessage] {
        await state.wait { $0.sent.count >= count }
        return state.current.sent.map { try! Wire.decode(ClientMessage.self, from: Data($0.utf8)) }
    }

    func waitClosed() async -> Int {
        await state.wait { $0.closeCode != nil }
        return state.current.closeCode!
    }
}

final class FakeTransport: WebSocketTransport {
    let connections = Watched<[FakeConnection]>([])
    let urls = Watched<[URL]>([])

    func connect(to url: URL) async throws -> any WebSocketConnection {
        let c = FakeConnection()
        urls.mutate { $0.append(url) }
        connections.mutate { $0.append(c) }
        return c
    }

    /// The index-th connection the client opened, once it has.
    func connection(_ index: Int) async -> FakeConnection {
        await connections.wait { $0.count > index }
        return connections.current[index]
    }
}

/// Answers each request with (status, JSON body) from `respond`, and records the requests.
final class FakeHTTP: HTTPTransport {
    let requests = Watched<[URLRequest]>([])
    let respond: @Sendable (URLRequest) -> (Int, String)

    init(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) { self.respond = respond }

    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.mutate { $0.append(request) }
        let (status, body) = respond(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

extension AsyncStream<RelayClient.Output>.Iterator {
    /// The next connection state, skipping messages.
    mutating func nextState() async -> RelayClient.ConnectionState? {
        while let o = await next() { if case .state(let s) = o { return s } }
        return nil
    }

    /// The next relay message, skipping states.
    mutating func nextMessage() async -> ServerMessage? {
        while let o = await next() { if case .message(let m) = o { return m } }
        return nil
    }
}

func event(_ session: String, _ seq: Int, run: String = "run_1", _ payload: EventPayload) -> Event {
    Event(sessionID: session, runID: run, seq: seq, ts: 1_792_801_004_583 + seq, payload: payload)
}
