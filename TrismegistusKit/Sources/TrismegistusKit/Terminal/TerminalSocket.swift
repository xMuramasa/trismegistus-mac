import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One frame of `/api/terminal`: JSON text, or PTY bytes.
public enum TerminalFrame: Sendable, Equatable {
    case text(String)
    case binary(Data)
}

/// The socket is gone. `code` is its WebSocket close code, nil when it dropped without one.
public struct TerminalSocketClosed: Error, Equatable {
    public let code: Int?

    public init(code: Int?) { self.code = code }
}

/// `/api/terminal`'s socket: unlike `WebSocketConnection` it carries binary frames and says how it closed.
public protocol TerminalSocket: AnyObject, Sendable {
    func send(_ frame: TerminalFrame) async throws
    /// The next frame; throws `TerminalSocketClosed` once the socket is closed (by either side).
    func receive() async throws -> TerminalFrame
    func close(code: Int) async
}

public protocol TerminalTransport: Sendable {
    func connect(to url: URL) async throws -> any TerminalSocket
}

public struct URLSessionTerminalTransport: TerminalTransport {
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func connect(to url: URL) async throws -> any TerminalSocket {
        let task = session.webSocketTask(with: url)
        task.resume()
        return URLSessionTerminalSocket(task: task)
    }
}

// URLSessionWebSocketTask is thread-safe; it isn't annotated Sendable everywhere.
final class URLSessionTerminalSocket: TerminalSocket, @unchecked Sendable {
    let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) { self.task = task }

    func send(_ frame: TerminalFrame) async throws {
        switch frame {
        case .text(let text): try await task.send(.string(text))
        case .binary(let bytes): try await task.send(.data(bytes))
        }
    }

    func receive() async throws -> TerminalFrame {
        do {
            switch try await task.receive() {
            case .string(let text): return .text(text)
            case .data(let bytes): return .binary(bytes)
            @unknown default: return .text("")
            }
        } catch {
            throw TerminalSocketClosed(code: task.closeCode == .invalid ? nil : task.closeCode.rawValue)
        }
    }

    func close(code: Int) async {
        task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure, reason: nil)
    }
}
