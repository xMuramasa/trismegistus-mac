import Foundation

/// The one WebSocket to the relay: auth, wait for ready, resubscribe from the last seq per session, keepalive,
/// reconnect with backoff. Everything the relay sends comes out of `outputs`, in order.
public actor RelayClient {
    public enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected(device: String, serverVersion: String)
        /// The relay refused the token (revoked, or never paired). The client stopped and won't retry on its own.
        case authFailed(message: String)
    }

    public enum Output: Sendable, Equatable {
        case state(ConnectionState)
        case message(ServerMessage)
    }

    public enum SendError: Error, Equatable {
        case notConnected
    }

    /// The relay's numbers (relay/internal/server: PingInterval 25 s, two missed pongs drop the socket).
    public static let pingInterval: Duration = .seconds(25)
    public static let missedPongLimit = 2
    /// The relay closes a socket that hasn't sent auth within 5 s; this is the wait for its `ready`.
    public static let readyTimeout: Duration = .seconds(10)
    public static let maxBackoff: Duration = .seconds(30)

    public nonisolated let outputs: AsyncStream<Output>
    private let output: AsyncStream<Output>.Continuation
    private let url: URL
    private let token: String
    private let transport: any WebSocketTransport
    private let sleep: @Sendable (Duration) async throws -> Void
    private let jitter: @Sendable () -> Double

    public private(set) var state: ConnectionState = .disconnected
    /// Followed sessions and the last seq seen in each (0: none yet, subscribe without after_seq).
    private var lastSeq: [String: Int] = [:]
    private var socket: (any WebSocketConnection)?
    private var ready = false
    private var loop: Task<Void, Never>?
    private var awaitingPong = false
    private var missedPongs = 0
    /// A pong came back on this connection: it was healthy for a ping interval, so the backoff starts over.
    private var stable = false

    public var isRunning: Bool { loop != nil }

    /// relayURL is the relay's https base URL (as in the pairing QR); the socket is `<base>/ws`.
    /// sleep and jitter (0..<1) are injectable so tests control time.
    public init(
        relayURL: URL,
        token: String,
        transport: any WebSocketTransport = URLSessionWebSocketTransport(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        jitter: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
    ) {
        (outputs, output) = AsyncStream.makeStream(of: Output.self)
        url = Self.webSocketURL(relayURL)
        self.token = token
        self.transport = transport
        self.sleep = sleep
        self.jitter = jitter
    }

    static func webSocketURL(_ base: URL) -> URL {
        guard var c = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        c.scheme = c.scheme == "http" ? "ws" : "wss"
        while c.path.hasSuffix("/") { c.path.removeLast() }
        c.path += "/ws"
        return c.url ?? base
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task { await self.run() }
    }

    /// Closes the socket for good (until start()).
    public func stop() async {
        loop?.cancel()
        loop = nil
        let s = socket
        socket = nil
        ready = false
        await s?.close(code: 1000)
        setState(.disconnected)
    }

    /// Follows a session: subscribes now if connected, and again after every reconnect from the last seq seen.
    /// afterSeq > 0 replays the stored events after it first.
    public func subscribe(_ sessionID: String, afterSeq: Int = 0) async {
        lastSeq[sessionID] = afterSeq
        if ready, let c = socket {
            try? await c.send(Self.text(.subscribe(sessionID: sessionID, afterSeq: afterSeq > 0 ? afterSeq : nil)))
        }
    }

    public func unsubscribe(_ sessionID: String) async {
        guard lastSeq.removeValue(forKey: sessionID) != nil else { return }
        if ready, let c = socket { try? await c.send(Self.text(.unsubscribe(sessionID: sessionID))) }
    }

    /// prompt, steer, stop, approve (subscribe through subscribe(_:afterSeq:) so reconnects resume it).
    public func send(_ message: ClientMessage) async throws {
        guard ready, let c = socket else { throw SendError.notConnected }
        try await c.send(Self.text(message))
    }

    static func text(_ message: ClientMessage) throws -> String {
        String(decoding: try Wire.encode(message), as: UTF8.self)
    }

    private func setState(_ s: ConnectionState) {
        guard s != state else { return }
        state = s
        output.yield(.state(s))
    }

    private func run() async {
        var attempt = 0
        while !Task.isCancelled {
            guard let wasStable = await session() else { return } // auth failed
            if wasStable { attempt = 0 }
            if Task.isCancelled { return }
            let base = min(Self.maxBackoff, .seconds(1 << min(attempt, 5)))
            attempt += 1
            do { try await sleep(base + base * (0.2 * jitter())) } catch { return }
        }
    }

    /// One connection, from connect to drop. Returns whether it was stable, or nil after an auth failure.
    private func session() async -> Bool? {
        setState(.connecting)
        let c: any WebSocketConnection
        do { c = try await transport.connect(to: url) } catch {
            setState(.disconnected)
            return false
        }
        if Task.isCancelled {
            await c.close(code: 1000)
            return false
        }
        socket = c
        let result = await serve(c)
        if socket === c { // else stop() already cleaned up
            socket = nil
            ready = false
            if result != nil { setState(.disconnected) }
        }
        return result
    }

    private func serve(_ c: any WebSocketConnection) async -> Bool? {
        stable = false
        awaitingPong = false
        missedPongs = 0
        do {
            try await c.send(Self.text(.auth(token: token)))
            switch try await firstMessage(c) {
            case .ready(let device, let version)?:
                ready = true
                output.yield(.message(.ready(device: device, serverVersion: version)))
                setState(.connected(device: device, serverVersion: version))
            case .error(.unauthorized, let message, let ref)?:
                output.yield(.message(.error(code: .unauthorized, message: message, ref: ref)))
                await c.close(code: 1000)
                loop = nil
                setState(.authFailed(message: message))
                return nil
            default:
                await c.close(code: 1000)
                return false
            }
            for (sessionID, seq) in lastSeq {
                try await c.send(Self.text(.subscribe(sessionID: sessionID, afterSeq: seq > 0 ? seq : nil)))
            }
            let keepalive = Task { await self.keepalive(c) }
            defer { keepalive.cancel() }
            while true {
                await handle(try await c.receive(), from: c)
            }
        } catch {
            return stable
        }
    }

    /// The relay's answer to auth, or nil if it isn't a protocol message. Closes the socket after readyTimeout.
    private func firstMessage(_ c: any WebSocketConnection) async throws -> ServerMessage? {
        let sleep = self.sleep
        let timer = Task {
            try await sleep(Self.readyTimeout)
            await c.close(code: 1000)
        }
        defer { timer.cancel() }
        let text = try await c.receive()
        return try? Wire.decode(ServerMessage.self, from: Data(text.utf8))
    }

    private func handle(_ text: String, from c: any WebSocketConnection) async {
        // Untrusted input: what doesn't match the protocol is dropped.
        guard let msg = try? Wire.decode(ServerMessage.self, from: Data(text.utf8)) else { return }
        switch msg {
        case .pong:
            awaitingPong = false
            stable = true
        case .event(let e):
            if let seq = lastSeq[e.sessionID] { lastSeq[e.sessionID] = max(seq, e.seq) }
        case .error(.replayGap, _, let sessionID?) where lastSeq[sessionID] != nil:
            // The relay refused the subscription. Take live events from now on; SessionStore reloads the history.
            lastSeq[sessionID] = 0
            try? await c.send(Self.text(.subscribe(sessionID: sessionID)))
        default:
            break
        }
        output.yield(.message(msg))
    }

    private func keepalive(_ c: any WebSocketConnection) async {
        while (try? await sleep(Self.pingInterval)) != nil, !Task.isCancelled {
            if awaitingPong {
                missedPongs += 1
                if missedPongs >= Self.missedPongLimit {
                    await c.close(code: 1001) // the read loop sees the close and reconnects
                    return
                }
            } else {
                missedPongs = 0
            }
            awaitingPong = true
            try? await c.send(Self.text(.ping))
        }
    }
}
