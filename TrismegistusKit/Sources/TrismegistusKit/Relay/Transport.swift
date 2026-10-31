import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One open WebSocket. Keepalive uses the protocol's own `ping`/`pong` messages, so text frames are all it carries.
public protocol WebSocketConnection: AnyObject, Sendable {
    func send(_ text: String) async throws
    /// The next text message; throws once the socket is closed (by either side).
    func receive() async throws -> String
    func close(code: Int) async
}

public protocol WebSocketTransport: Sendable {
    func connect(to url: URL) async throws -> any WebSocketConnection
}

/// One HTTP exchange; RelayREST's seam.
public protocol HTTPTransport: Sendable {
    func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionWebSocketTransport: WebSocketTransport {
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func connect(to url: URL) async throws -> any WebSocketConnection {
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 4 << 20 // an answer event carries up to 256 KiB of text, escaped
        task.resume()
        return URLSessionWebSocketConnection(task: task)
    }
}

// URLSessionWebSocketTask is thread-safe; it isn't annotated Sendable everywhere.
final class URLSessionWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) { self.task = task }

    func send(_ text: String) async throws { try await task.send(.string(text)) }

    func receive() async throws -> String {
        switch try await task.receive() {
        case .string(let s): return s
        case .data(let d): return String(decoding: d, as: UTF8.self)
        @unknown default: return ""
        }
    }

    func close(code: Int) async {
        task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
    }
}

extension URLSession: HTTPTransport {
    public func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
