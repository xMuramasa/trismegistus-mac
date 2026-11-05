import Foundation
import Testing
#if canImport(Network)
import Network
#endif
@testable import TrismegistusKit

/// A frame as protocol/terminal.schema.json allows it: known type, required and known keys, value types and sizes.
private func matchesSchema(_ json: String) throws -> Bool {
    let url = try #require(protocolDir).appendingPathComponent("terminal.schema.json")
    let schema = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let defs = try #require(schema["$defs"] as? [String: [String: Any]])
    let frame = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    guard let type = frame["type"] as? String, let def = defs[type],
        let required = def["required"] as? [String], let properties = def["properties"] as? [String: [String: Any]],
        Set(required).isSubset(of: frame.keys), Set(frame.keys).isSubset(of: properties.keys) else { return false }
    return frame.allSatisfy { key, value in
        let property = properties[key] ?? [:]
        if let const = property["const"] as? String { return value as? String == const }
        if let allowed = property["enum"] as? [String] { return (value as? String).map(allowed.contains) ?? false }
        if property["$ref"] != nil {
            guard let size = value as? Int, let min = defs["size"]?["minimum"] as? Int, let max = defs["size"]?["maximum"] as? Int
            else { return false }
            return (min...max).contains(size)
        }
        return property["type"] as? String == "integer" ? value is Int : value is String
    }
}

/// One scripted `/api/terminal` socket: the test pushes relay frames and reads what the link sent.
private final class FakeTerminalSocket: TerminalSocket {
    struct State {
        var inbox: [TerminalFrame] = []
        var sent: [TerminalFrame] = []
        var closeCode: Int?
        var dropped = false
        var closedByLink: Int?
    }

    let state = Watched(State())

    func send(_ frame: TerminalFrame) async throws {
        try state.mutate { s in
            guard s.closeCode == nil, !s.dropped else { throw TerminalSocketClosed(code: s.closeCode) }
            s.sent.append(frame)
        }
    }

    func receive() async throws -> TerminalFrame {
        await state.wait { !$0.inbox.isEmpty || $0.closeCode != nil || $0.dropped }
        return try state.mutate { s in
            guard !s.inbox.isEmpty else { throw TerminalSocketClosed(code: s.closeCode) }
            return s.inbox.removeFirst()
        }
    }

    func close(code: Int) async {
        state.mutate { s in
            s.closedByLink = code
            if s.closeCode == nil { s.closeCode = code }
        }
    }

    // Test side.

    /// A relay text frame, which must itself match the schema.
    func push(_ json: String) throws {
        #expect(try matchesSchema(json), "the fake's frame isn't in the schema: \(json)")
        state.mutate { $0.inbox.append(.text(json)) }
    }

    func push(bytes: String) { state.mutate { $0.inbox.append(.binary(Data(bytes.utf8))) } }

    /// The relay closed with `code`; nil: no close frame at all.
    func drop(code: Int?) {
        state.mutate { s in
            s.closeCode = code
            s.dropped = true
        }
    }

    func sent(_ count: Int) async -> [TerminalFrame] {
        await state.wait { $0.sent.count >= count }
        return state.current.sent
    }

    /// The text frames sent as JSON objects, each checked against the schema.
    func sentMessages(_ count: Int) async throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        for frame in await sent(count) {
            guard case .text(let json) = frame else { continue }
            #expect(try matchesSchema(json), "the link's frame isn't in the schema: \(json)")
            out.append(try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]))
        }
        return out
    }
}

private final class FakeTerminalTransport: TerminalTransport {
    let socket = FakeTerminalSocket()
    let urls = Watched<[URL]>([])

    func connect(to url: URL) async throws -> any TerminalSocket {
        urls.mutate { $0.append(url) }
        return socket
    }
}

private struct Unreachable: TerminalTransport {
    func connect(to url: URL) async throws -> any TerminalSocket { throw URLError(.cannotConnectToHost) }
}

private let openedFrame = #"{"type":"opened","host":"optiplex","shell":"/bin/bash"}"#

private func link(_ transport: any TerminalTransport, cols: Int = 80, rows: Int = 24) -> TerminalLink {
    TerminalLink(relayURL: relayURL, token: fakeToken, cols: cols, rows: rows, transport: transport)
}

/// A link past `opened`.
private func openLink() async throws -> (TerminalLink, FakeTerminalSocket) {
    let transport = FakeTerminalTransport()
    let link = link(transport)
    try transport.socket.push(openedFrame)
    #expect(await link.next() == .state(.open(host: "optiplex", shell: "/bin/bash")))
    return (link, transport.socket)
}

@Suite struct TerminalLinkTests {
    @Test func sendsAuthThenOpenToTheTerminalPath() async throws {
        let transport = FakeTerminalTransport()
        let link = link(transport, cols: 120, rows: 9)
        try transport.socket.push(openedFrame)
        _ = await link.next()

        #expect(transport.urls.current == [URL(string: "wss://relay.invalid/api/terminal")!])
        let sent = try await transport.socket.sentMessages(2)
        #expect(sent[0]["type"] as? String == "auth" && sent[0]["token"] as? String == fakeToken)
        #expect(sent[1]["type"] as? String == "open" && sent[1]["cols"] as? Int == 120 && sent[1]["rows"] as? Int == 9)
        #expect(await link.state == .open(host: "optiplex", shell: "/bin/bash"))
    }

    @Test func socketURLKeepsABasePath() {
        #expect(TerminalLink.socketURL(URL(string: "https://relay.invalid/")!).absoluteString == "wss://relay.invalid/api/terminal")
        #expect(TerminalLink.socketURL(URL(string: "http://relay.invalid/lab")!).absoluteString == "ws://relay.invalid/lab/api/terminal")
    }

    @Test func sizesStayInTheSchema() async throws {
        let transport = FakeTerminalTransport()
        let link = link(transport, cols: 0, rows: 5000)
        try transport.socket.push(openedFrame)
        _ = await link.next()
        let sent = try await transport.socket.sentMessages(2)
        #expect(sent[1]["cols"] as? Int == 1 && sent[1]["rows"] as? Int == 1000)
    }

    @Test func bytesGoBothWays() async throws {
        let (link, socket) = try await openLink()
        socket.push(bytes: "optiplex\r\n")
        #expect(await link.next() == .bytes(Data("optiplex\r\n".utf8)))

        link.write(Data("hostname\r".utf8))
        #expect(await socket.sent(3)[2] == .binary(Data("hostname\r".utf8)))
    }

    @Test func inputWaitsForOpenedAndKeepsItsOrder() async throws {
        let transport = FakeTerminalTransport()
        let link = link(transport)
        link.write(Data("a".utf8))
        link.resize(cols: 100, rows: 30)
        link.write(Data("b".utf8))
        // Before `opened` a binary frame would be a bad `open`.
        let next = Task { await link.next() }
        _ = await transport.socket.sent(2)
        #expect(transport.socket.state.current.sent.count == 2)

        try transport.socket.push(openedFrame)
        _ = await next.value
        let sent = await transport.socket.sent(5)
        #expect(sent[2] == .binary(Data("a".utf8)) && sent[4] == .binary(Data("b".utf8)))
        guard case .text(let resize) = sent[3] else { return #expect(Bool(false)) }
        #expect(try matchesSchema(resize) && resize.contains(#""type":"resize""#))
    }

    @Test func aPasteIsSplitToTheRelaysFrameLimit() async throws {
        let (link, socket) = try await openLink()
        let paste = Data(repeating: 0x61, count: TerminalLink.maxFrame * 2 + 1)
        link.write(paste)
        let frames = await socket.sent(5)[2...].map { frame -> Data in
            guard case .binary(let bytes) = frame else { return Data() }
            return bytes
        }
        #expect(frames.map(\.count) == [TerminalLink.maxFrame, TerminalLink.maxFrame, 1])
        #expect(Data(frames.joined()) == paste)
    }

    @Test func aBadResizeLeavesTheTerminalOpen() async throws {
        let (link, socket) = try await openLink()
        try socket.push(#"{"type":"error","code":"bad_request","message":"bad resize"}"#)
        socket.push(bytes: "still here")
        #expect(await link.next() == .bytes(Data("still here".utf8)))
        #expect(await link.state == .open(host: "optiplex", shell: "/bin/bash"))
    }

    @Test func exitEndsTheLink() async throws {
        let (link, socket) = try await openLink()
        try socket.push(#"{"type":"exit","status":0}"#)
        #expect(await link.next() == .state(.ended(status: 0)))
        #expect(await link.next() == nil)
        #expect(socket.state.current.closedByLink == 1000)
        #expect(TerminalLink.State.ended(status: 0).notice == "[shell ended · exit 0]")
        #expect(TerminalLink.State.ended(status: 137).notice == "[shell ended · exit 137]")
    }

    /// The socket is already closed when the link sends `auth` and `open`: the relay's error still comes through.
    @Test(arguments: ["unauthorized", "forbidden", "not_configured", "unavailable", "busy", "bad_request"])
    func eachRefusalCode(_ code: String) async throws {
        let transport = FakeTerminalTransport()
        let link = link(transport)
        try transport.socket.push(#"{"type":"error","code":"\#(code)","message":"from the relay"}"#)
        transport.socket.state.mutate { $0.closeCode = 1008 }
        let refused = TerminalLink.State.refused(code: code, message: "from the relay")
        #expect(await link.next() == .state(refused))
        #expect(await link.next() == nil)
        let helper = code == "unavailable" || code == "not_configured"
        #expect(refused.notice?.hasPrefix("from the relay") == true)
        #expect(refused.notice?.contains("systemctl --user start trismegistus-term") == helper)
    }

    /// 1008 while open is access ended; every other close is lost.
    @Test(arguments: [(1008, TerminalLink.State.accessEnded), (1001, .lost), (1006, .lost), (1009, .lost)])
    func closeWhileOpen(_ code: Int, _ end: TerminalLink.State) async throws {
        let (link, socket) = try await openLink()
        socket.drop(code: code)
        #expect(await link.next() == .state(end))
        #expect(await link.next() == nil)
    }

    @Test func dropWithoutACloseFrameIsLost() async throws {
        let (link, socket) = try await openLink()
        socket.drop(code: nil)
        #expect(await link.next() == .state(.lost))
        #expect(TerminalLink.State.lost.notice == "[connection lost]")
        #expect(TerminalLink.State.accessEnded.notice == "[terminal closed by the server: access ended]")
    }

    @Test func anUnreachableRelayIsLost() async {
        let link = link(Unreachable())
        #expect(await link.next() == .state(.lost))
    }

    @Test func closingEndsWithoutAState() async throws {
        let (link, socket) = try await openLink()
        let next = Task { await link.next() }
        await link.close()
        #expect(await next.value == nil)
        #expect(socket.state.current.closedByLink == 1000)
        link.write(Data("x".utf8)) // after the end: nowhere to go, no crash
    }

    @Test func aFrameOutsideTheSchemaFails() throws {
        #expect(try !matchesSchema(#"{"type":"resize","cols":0,"rows":24}"#))
        #expect(try !matchesSchema(#"{"type":"open","cols":80}"#))
        #expect(try !matchesSchema(#"{"type":"auth","token":"x","extra":1}"#))
        #expect(try !matchesSchema(#"{"type":"error","code":"nope","message":"x"}"#))
    }
}

#if canImport(Network)
/// The real socket against a loopback WebSocket server (Network.framework; Mac only): binary frames arrive as bytes,
/// and a relay close reaches the link as its code, which is how "access ended" differs from "lost".
@Suite struct URLSessionTerminalSocketTests {
    private final class Server: @unchecked Sendable {
        let listener: NWListener
        let queue = DispatchQueue(label: "terminal-socket-test")

        /// Echoes the first binary frame, then closes with `code`.
        init(closingWith code: NWProtocolWebSocket.CloseCode) throws {
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
            listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [queue] connection in
                connection.start(queue: queue)
                connection.receiveMessage { data, _, _, _ in
                    let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
                    let context = NWConnection.ContentContext(identifier: "echo", metadata: [metadata])
                    connection.send(content: data, contentContext: context, completion: .contentProcessed { _ in
                        let close = NWProtocolWebSocket.Metadata(opcode: .close)
                        close.closeCode = code
                        let context = NWConnection.ContentContext(identifier: "close", metadata: [close])
                        connection.send(content: nil, contentContext: context, completion: .idempotent)
                    })
                }
            }
        }

        func start() async throws -> UInt16 {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<UInt16, any Error>) in
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready: c.resume(returning: listener.port?.rawValue ?? 0)
                    case .failed(let error): c.resume(throwing: error)
                    default: break
                    }
                    if case .ready = state { listener.stateUpdateHandler = nil }
                }
                listener.start(queue: queue)
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func binaryFramesAndTheCloseCode() async throws {
        let server = try Server(closingWith: .protocolCode(.policyViolation))
        defer { server.listener.cancel() }
        let port = try await server.start()
        let socket = try await URLSessionTerminalTransport().connect(to: URL(string: "ws://127.0.0.1:\(port)/api/terminal")!)

        let bytes = Data([0x00, 0xFF, 0x1B, 0x5B])
        try await socket.send(.binary(bytes))
        #expect(try await socket.receive() == .binary(bytes))
        await #expect(throws: TerminalSocketClosed(code: 1008)) { try await socket.receive() }
    }
}
#endif
