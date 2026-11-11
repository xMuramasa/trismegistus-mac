import Foundation

/// Approval choices the app may send. Hermes' `always` is hidden on purpose: there is no case for it.
public enum ApprovalChoice: String, Codable, Sendable, CaseIterable {
    case once, session, deny
}

public enum RunStatus: String, Codable, Sendable, CaseIterable {
    case running
    case waitingForApproval = "waiting_for_approval"
    case completed, failed, cancelled

    public var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
}

public enum ErrorCode: String, Codable, Sendable, CaseIterable {
    case unauthorized
    case badRequest = "bad_request"
    case tooLarge = "too_large"
    case rateLimited = "rate_limited"
    case busy
    case notFound = "not_found"
    case readOnly = "read_only"
    /// REST only (HTTP 403): a write from a `viewer` device, or GitHub refusing the relay. Not one of `schema.json`'s
    /// WebSocket codes.
    case forbidden
    case replayGap = "replay_gap"
    case hermesUnavailable = "hermes_unavailable"
    case hermesError = "hermes_error"
    case `internal`
}

/// App → relay.
public enum ClientMessage: Codable, Sendable, Equatable {
    /// First message on a socket, within 5 s of connecting.
    case auth(token: String)
    /// With afterSeq, stored events with a larger seq are replayed first (or `error replay_gap`).
    case subscribe(sessionID: String, afterSeq: Int? = nil)
    case unsubscribe(sessionID: String)
    /// clientMsgID (a UUID) makes resends safe. attachments: 1-4 unique ids from `POST /api/attachments`; text may be
    /// empty when there is one. rewindTo: the Hermes id of one of the session's user messages; the relay first rewinds
    /// the conversation to just before it (retry and edit).
    case prompt(clientMsgID: String, sessionID: String, text: String, attachments: [String] = [], rewindTo: Int64? = nil)
    case stop(runID: String)
    case steer(runID: String, text: String)
    case approve(runID: String, requestID: String, choice: ApprovalChoice)
    case ping

    public var type: String {
        switch self {
        case .auth: "auth"
        case .subscribe: "subscribe"
        case .unsubscribe: "unsubscribe"
        case .prompt: "prompt"
        case .stop: "stop"
        case .steer: "steer"
        case .approve: "approve"
        case .ping: "ping"
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let type = try c.decode(String.self, forKey: "type")
        func str(_ k: AnyKey) throws -> String { try c.decode(String.self, forKey: k) }
        switch type {
        case "auth":
            try c.only(["type", "token"])
            self = .auth(token: try str("token"))
        case "subscribe":
            try c.only(["type", "session_id", "after_seq"])
            let after = try c.decodeIfPresent(Int.self, forKey: "after_seq")
            try c.check((after ?? 0) >= 0, "after_seq", "after_seq must be >= 0")
            self = .subscribe(sessionID: try str("session_id"), afterSeq: after)
        case "unsubscribe":
            try c.only(["type", "session_id"])
            self = .unsubscribe(sessionID: try str("session_id"))
        case "prompt":
            try c.only(["type", "client_msg_id", "session_id", "text", "attachments", "rewind_to"])
            let ids = try c.decodeIfPresent([String].self, forKey: "attachments")
            try c.check(ids.map { (1...4).contains($0.count) && Set($0).count == $0.count } ?? true, "attachments",
                        "attachments must hold 1-4 unique ids")
            let rewind = try c.decodeIfPresent(Int64.self, forKey: "rewind_to")
            try c.check((rewind ?? 1) >= 1, "rewind_to", "rewind_to must be >= 1")
            self = .prompt(clientMsgID: try str("client_msg_id"), sessionID: try str("session_id"), text: try str("text"),
                           attachments: ids ?? [], rewindTo: rewind)
        case "stop":
            try c.only(["type", "run_id"])
            self = .stop(runID: try str("run_id"))
        case "steer":
            try c.only(["type", "run_id", "text"])
            self = .steer(runID: try str("run_id"), text: try str("text"))
        case "approve":
            try c.only(["type", "run_id", "request_id", "choice"])
            self = .approve(runID: try str("run_id"), requestID: try str("request_id"),
                            choice: try c.decode(ApprovalChoice.self, forKey: "choice"))
        case "ping":
            try c.only(["type"])
            self = .ping
        default:
            throw DecodingError.dataCorruptedError(forKey: "type", in: c, debugDescription: "not an app message type")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(type, forKey: "type")
        switch self {
        case .auth(let token):
            try c.encode(token, forKey: "token")
        case .subscribe(let sessionID, let afterSeq):
            try c.encode(sessionID, forKey: "session_id")
            try c.encodeIfPresent(afterSeq, forKey: "after_seq")
        case .unsubscribe(let sessionID):
            try c.encode(sessionID, forKey: "session_id")
        case .prompt(let clientMsgID, let sessionID, let text, let attachments, let rewindTo):
            try c.encode(clientMsgID, forKey: "client_msg_id")
            try c.encode(sessionID, forKey: "session_id")
            try c.encode(text, forKey: "text")
            if !attachments.isEmpty { try c.encode(attachments, forKey: "attachments") }
            try c.encodeIfPresent(rewindTo, forKey: "rewind_to")
        case .stop(let runID):
            try c.encode(runID, forKey: "run_id")
        case .steer(let runID, let text):
            try c.encode(runID, forKey: "run_id")
            try c.encode(text, forKey: "text")
        case .approve(let runID, let requestID, let choice):
            try c.encode(runID, forKey: "run_id")
            try c.encode(requestID, forKey: "request_id")
            try c.encode(choice, forKey: "choice")
        case .ping:
            break
        }
    }
}

/// Relay → app.
public enum ServerMessage: Codable, Sendable, Equatable {
    /// After a successful auth.
    case ready(device: String, serverVersion: String)
    /// One numbered, stored event.
    case event(Event)
    /// A run's status changed (live only, and after a subscribe replay for the active run).
    case run(runID: String, sessionID: String, status: RunStatus)
    /// A prompt was accepted; replayed is true when client_msg_id was seen before (no new run).
    case ack(clientMsgID: String, runID: String, replayed: Bool)
    /// ref names what failed: a prompt's client_msg_id, the run_id of stop/steer/approve, a subscribe's session_id.
    case error(code: ErrorCode, message: String, ref: String? = nil)
    case pong

    public var type: String {
        switch self {
        case .ready: "ready"
        case .event: "event"
        case .run: "run"
        case .ack: "ack"
        case .error: "error"
        case .pong: "pong"
        }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        func str(_ k: AnyKey) throws -> String { try c.decode(String.self, forKey: k) }
        switch try c.decode(String.self, forKey: "type") {
        case "ready":
            try c.only(["type", "device", "server_version"])
            self = .ready(device: try str("device"), serverVersion: try str("server_version"))
        case "event":
            self = .event(try Event(from: decoder))
        case "run":
            try c.only(["type", "run_id", "session_id", "status"])
            self = .run(runID: try str("run_id"), sessionID: try str("session_id"),
                        status: try c.decode(RunStatus.self, forKey: "status"))
        case "ack":
            try c.only(["type", "client_msg_id", "run_id", "replayed"])
            self = .ack(clientMsgID: try str("client_msg_id"), runID: try str("run_id"),
                        replayed: try c.decode(Bool.self, forKey: "replayed"))
        case "error":
            try c.only(["type", "code", "message", "ref"])
            self = .error(code: try c.decode(ErrorCode.self, forKey: "code"), message: try str("message"),
                          ref: try c.decodeIfPresent(String.self, forKey: "ref"))
        case "pong":
            try c.only(["type"])
            self = .pong
        default:
            throw DecodingError.dataCorruptedError(forKey: "type", in: c, debugDescription: "not a relay message type")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        if case .event(let e) = self { return try e.encode(to: encoder) }
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode(type, forKey: "type")
        switch self {
        case .ready(let device, let serverVersion):
            try c.encode(device, forKey: "device")
            try c.encode(serverVersion, forKey: "server_version")
        case .run(let runID, let sessionID, let status):
            try c.encode(runID, forKey: "run_id")
            try c.encode(sessionID, forKey: "session_id")
            try c.encode(status, forKey: "status")
        case .ack(let clientMsgID, let runID, let replayed):
            try c.encode(clientMsgID, forKey: "client_msg_id")
            try c.encode(runID, forKey: "run_id")
            try c.encode(replayed, forKey: "replayed")
        case .error(let code, let message, let ref):
            try c.encode(code, forKey: "code")
            try c.encode(message, forKey: "message")
            try c.encodeIfPresent(ref, forKey: "ref")
        case .event, .pong:
            break
        }
    }
}
