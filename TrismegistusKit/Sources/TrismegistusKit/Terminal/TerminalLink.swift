import Foundation

/// One shell on the host over the relay's `/api/terminal` (protocol/terminal.schema.json): `auth`, `open`, then PTY bytes
/// both ways. A link is one shell and never reconnects; a new shell is a new link.
///
/// The caller pulls with `next()`: the socket is read only as fast as it asks, which is the contract's "a slow app
/// slows the shell". Input and resizes keep their order, and wait for `opened`.
// shortcut: no pings of its own (the relay's are answered by URLSession), so a silently dead link shows as lost only
// once input fails or TCP gives up; send pings like RelayClient if that turns out to matter.
public actor TerminalLink {
    public enum State: Sendable, Equatable {
        case connecting
        case open(host: String, shell: String)
        /// The shell exited; the relay's status (128 + the signal for a killed shell).
        case ended(status: Int)
        /// The relay said no: `error {code, message}`.
        case refused(code: String, message: String)
        /// Closed 1008 while open: revoked, the grant turned off, or demoted.
        case accessEnded
        /// Anything else: the network, a relay restart (1001), an oversized frame (1009).
        case lost

        public var isLive: Bool {
            switch self {
            case .connecting, .open: true
            case .ended, .refused, .accessEnded, .lost: false
            }
        }

        /// What the drawer prints once the shell is over; nil while it isn't.
        public var notice: String? {
            switch self {
            case .connecting, .open: nil
            case .ended(let status): "[shell ended · exit \(status)]"
            case .accessEnded: "[terminal closed by the server: access ended]"
            case .lost: "[connection lost]"
            // The relay's message already names the fix, except for the helper, which only the host can see.
            case .refused("unavailable", let message), .refused("not_configured", let message):
                message + "\nThe terminal helper isn't running on optiplex: systemctl --user start trismegistus-term"
            case .refused(_, let message): message
            }
        }
    }

    public enum Output: Sendable, Equatable {
        case state(State)
        case bytes(Data)
    }

    /// The relay closes the socket (1009) on a bigger frame.
    public static let maxFrame = 32 << 10
    /// `cols` and `rows`, each.
    public static let sizes = 1...1000

    public private(set) var state = State.connecting
    private let url: URL
    private let token: String
    private let size: (cols: Int, rows: Int)
    private let transport: any TerminalTransport
    private let outgoing: AsyncStream<TerminalFrame>
    private let input: AsyncStream<TerminalFrame>.Continuation
    private var socket: (any TerminalSocket)?
    private var writer: Task<Void, Never>?
    private var closing = false

    /// relayURL is the relay's https base URL, as for `RelayClient`.
    public init(
        relayURL: URL, token: String, cols: Int, rows: Int, transport: any TerminalTransport = URLSessionTerminalTransport()
    ) {
        (outgoing, input) = AsyncStream.makeStream(of: TerminalFrame.self)
        url = Self.socketURL(relayURL)
        self.token = token
        size = (Self.clamped(cols), Self.clamped(rows))
        self.transport = transport
    }

    static func socketURL(_ base: URL) -> URL {
        RelayClient.webSocketURL(base).deletingLastPathComponent().appendingPathComponent("api/terminal")
    }

    private static func clamped(_ size: Int) -> Int { min(max(size, sizes.lowerBound), sizes.upperBound) }

    /// The next bytes or state change, connecting on the first call; nil once the link is over.
    public func next() async -> Output? {
        guard state.isLive, !closing else { return nil }
        do {
            let socket = try await connected()
            while true {
                switch try await socket.receive() {
                case .binary(let bytes): return .bytes(bytes)
                case .text(let text):
                    guard let frame = try? Wire.decode(ServerFrame.self, from: Data(text.utf8)) else { continue }
                    switch frame.type {
                    case "opened":
                        state = .open(host: frame.host ?? "", shell: frame.shell ?? "")
                        startWriting(to: socket)
                        return .state(state)
                    case "exit":
                        return await finish(.ended(status: frame.status ?? 0))
                    case "error":
                        // A bad `resize`: the terminal stays open.
                        if case .open = state { continue }
                        return await finish(.refused(code: frame.code ?? "", message: frame.message ?? ""))
                    default: continue
                    }
                }
            }
        } catch {
            guard !closing else { return nil }
            return await finish((error as? TerminalSocketClosed)?.code == 1008 ? .accessEnded : .lost)
        }
    }

    /// Bytes for the shell, split to fit the relay's frames.
    public nonisolated func write(_ bytes: Data) {
        var rest = bytes[...]
        while !rest.isEmpty {
            input.yield(.binary(Data(rest.prefix(Self.maxFrame))))
            rest = rest.dropFirst(Self.maxFrame)
        }
    }

    public nonisolated func resize(cols: Int, rows: Int) {
        input.yield(Self.frame(ClientFrame(type: "resize", cols: Self.clamped(cols), rows: Self.clamped(rows))))
    }

    /// Ends the link from this side; `next()` returns nil. The relay ends the shell with the socket.
    public func close() async {
        closing = true
        stopWriting()
        await socket?.close(code: 1000)
    }

    private func connected() async throws -> any TerminalSocket {
        if let socket { return socket }
        let socket = try await transport.connect(to: url)
        guard !closing else {
            await socket.close(code: 1000)
            throw TerminalSocketClosed(code: nil)
        }
        self.socket = socket
        // Not `try`: a failed send leaves the relay's `error` to read, which says more than the send's failure.
        try? await socket.send(Self.frame(ClientFrame(type: "auth", token: token)))
        try? await socket.send(Self.frame(ClientFrame(type: "open", cols: size.cols, rows: size.rows)))
        return socket
    }

    /// One writer keeps the input in order; a failed send surfaces as the failed `receive`.
    private func startWriting(to socket: any TerminalSocket) {
        writer = Task { [outgoing] in
            for await frame in outgoing { try? await socket.send(frame) }
        }
    }

    private func stopWriting() {
        input.finish()
        writer?.cancel()
    }

    private func finish(_ end: State) async -> Output {
        state = end
        stopWriting()
        await socket?.close(code: 1000)
        return .state(end)
    }

    private static func frame(_ message: ClientFrame) -> TerminalFrame {
        .text(String(decoding: (try? Wire.encode(message)) ?? Data(), as: UTF8.self))
    }

    private struct ClientFrame: Encodable {
        let type: String
        var token: String?
        var cols: Int?
        var rows: Int?
    }

    private struct ServerFrame: Decodable {
        let type: String
        let host: String?
        let shell: String?
        let status: Int?
        let code: String?
        let message: String?
    }
}
