import Foundation

/// One numbered, stored event. seq counts up per session across runs, from 1; ts is unix milliseconds.
public struct Event: Codable, Sendable, Equatable {
    public var sessionID: String
    public var runID: String
    public var seq: Int
    public var ts: Int
    public var payload: EventPayload

    public var kind: String { payload.kind }

    public init(sessionID: String, runID: String, seq: Int, ts: Int, payload: EventPayload) {
        self.sessionID = sessionID
        self.runID = runID
        self.seq = seq
        self.ts = ts
        self.payload = payload
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        try c.only(["type", "session_id", "run_id", "seq", "kind", "data", "ts"])
        try c.check(try c.decode(String.self, forKey: "type") == "event", "type", "not an event")
        sessionID = try c.decode(String.self, forKey: "session_id")
        runID = try c.decode(String.self, forKey: "run_id")
        seq = try c.decode(Int.self, forKey: "seq")
        try c.check(seq >= 1, "seq", "seq must be >= 1")
        ts = try c.decode(Int.self, forKey: "ts")
        try c.check(ts >= 0, "ts", "ts must be >= 0")
        payload = try EventPayload(kind: try c.decode(String.self, forKey: "kind"), data: try c.superDecoder(forKey: "data"))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyKey.self)
        try c.encode("event", forKey: "type")
        try c.encode(sessionID, forKey: "session_id")
        try c.encode(runID, forKey: "run_id")
        try c.encode(seq, forKey: "seq")
        try c.encode(kind, forKey: "kind")
        try c.encode(ts, forKey: "ts")
        try payload.encodeData(to: c.superEncoder(forKey: "data"))
    }
}

/// An event's `kind` with its typed `data`.
public enum EventPayload: Sendable, Equatable {
    case toolStarted(ToolStarted)
    case toolCompleted(ToolCompleted)
    case subagentStarted(SubagentStarted)
    case subagentCompleted(SubagentCompleted)
    case approvalRequested(ApprovalRequest)
    case approvalResolved(ApprovalResolved)
    /// The final answer; over 256 KiB it's cut and marked truncated (the full text is in the history).
    case answer(Answer)
    case runCompleted
    case runFailed(error: String?)
    case runCancelled(reason: String?)
    /// Hermes accepted a steer.
    case steerQueued
    /// The relay lost Hermes' stream or restarted: some steps may be missing.
    case reconnected(reason: ReconnectReason)
    /// A Hermes event the relay doesn't map; safe to ignore.
    case unknown(UnknownEvent)
    /// A user's prompt or steer as the relay accepted it (trismegistus#30), so every device shows it at once.
    case userMessage(UserMessage)

    public var kind: String {
        switch self {
        case .toolStarted: "tool.started"
        case .toolCompleted: "tool.completed"
        case .subagentStarted: "subagent.started"
        case .subagentCompleted: "subagent.completed"
        case .approvalRequested: "approval.requested"
        case .approvalResolved: "approval.resolved"
        case .answer: "answer"
        case .runCompleted: "run.completed"
        case .runFailed: "run.failed"
        case .runCancelled: "run.cancelled"
        case .steerQueued: "steer.queued"
        case .reconnected: "reconnected"
        case .unknown: "unknown"
        case .userMessage: "user.message"
        }
    }

    /// Ends the run it belongs to.
    public var isTerminal: Bool {
        switch self {
        case .runCompleted, .runFailed, .runCancelled: true
        default: false
        }
    }

    init(kind: String, data d: any Decoder) throws {
        let c = try d.container(keyedBy: AnyKey.self)
        switch kind {
        case "tool.started": self = .toolStarted(try .init(strict: d))
        case "tool.completed": self = .toolCompleted(try .init(strict: d))
        case "subagent.started": self = .subagentStarted(try .init(strict: d))
        case "subagent.completed": self = .subagentCompleted(try .init(strict: d))
        case "approval.requested": self = .approvalRequested(try .init(strict: d))
        case "approval.resolved": self = .approvalResolved(try .init(strict: d))
        case "answer": self = .answer(try .init(strict: d))
        case "unknown": self = .unknown(try .init(strict: d))
        case "user.message": self = .userMessage(try .init(strict: d))
        case "run.completed":
            try c.only([])
            self = .runCompleted
        case "steer.queued":
            try c.only([])
            self = .steerQueued
        case "run.failed":
            try c.only(["error"])
            self = .runFailed(error: try c.decodeIfPresent(String.self, forKey: "error"))
        case "run.cancelled":
            try c.only(["reason"])
            self = .runCancelled(reason: try c.decodeIfPresent(String.self, forKey: "reason"))
        case "reconnected":
            try c.only(["reason"])
            self = .reconnected(reason: try c.decode(ReconnectReason.self, forKey: "reason"))
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "unknown event kind"))
        }
    }

    func encodeData(to e: any Encoder) throws {
        var c = e.container(keyedBy: AnyKey.self) // also makes run.completed and steer.queued encode as {}
        switch self {
        case .toolStarted(let v): try v.encode(to: e)
        case .toolCompleted(let v): try v.encode(to: e)
        case .subagentStarted(let v): try v.encode(to: e)
        case .subagentCompleted(let v): try v.encode(to: e)
        case .approvalRequested(let v): try v.encode(to: e)
        case .approvalResolved(let v): try v.encode(to: e)
        case .answer(let v): try v.encode(to: e)
        case .unknown(let v): try v.encode(to: e)
        case .userMessage(let v): try v.encode(to: e)
        case .runCompleted, .steerQueued: break
        case .runFailed(let error): try c.encodeIfPresent(error, forKey: "error")
        case .runCancelled(let reason): try c.encodeIfPresent(reason, forKey: "reason")
        case .reconnected(let reason): try c.encode(reason, forKey: "reason")
        }
    }
}

public enum ReconnectReason: String, Codable, Sendable, CaseIterable {
    case streamLost = "stream_lost"
    case relayRestart = "relay_restart"
}

public struct ToolStarted: StrictCodable, Sendable, Equatable {
    public var tool: String
    public var preview: String?
    enum CodingKeys: String, CodingKey, CaseIterable { case tool, preview }
}

public struct ToolCompleted: StrictCodable, Sendable, Equatable {
    public var tool: String
    /// Seconds.
    public var duration: Double?
    public var error: Bool
    public var preview: String?
    enum CodingKeys: String, CodingKey, CaseIterable { case tool, duration, error, preview }
}

public struct SubagentStarted: StrictCodable, Sendable, Equatable {
    public var subagentID: String
    public var goal: String?
    public var model: String?
    public var childSessionID: String?
    public var taskIndex: Int?
    public var taskCount: Int?
    enum CodingKeys: String, CodingKey, CaseIterable {
        case subagentID = "subagent_id", goal, model, childSessionID = "child_session_id"
        case taskIndex = "task_index", taskCount = "task_count"
    }
}

public struct SubagentCompleted: StrictCodable, Sendable, Equatable {
    public var subagentID: String
    public var status: String?
    public var summary: String?
    public var duration: Double?
    enum CodingKeys: String, CodingKey, CaseIterable { case subagentID = "subagent_id", status, summary, duration }
}

/// Hermes asks before running a risky command. choices never contains `always`.
public struct ApprovalRequest: StrictCodable, Sendable, Equatable {
    public var requestID: String
    public var command: String
    public var description: String?
    public var choices: [ApprovalChoice]
    enum CodingKeys: String, CodingKey, CaseIterable { case requestID = "request_id", command, description, choices }
}

public struct ApprovalResolved: StrictCodable, Sendable, Equatable {
    public var requestID: String
    /// Whatever answered it (another surface may have chosen `always`), so a plain string.
    public var choice: String
    enum CodingKeys: String, CodingKey, CaseIterable { case requestID = "request_id", choice }
}

public struct Answer: StrictCodable, Sendable, Equatable {
    public var text: String
    public var truncated: Bool?
    enum CodingKeys: String, CodingKey, CaseIterable { case text, truncated }
}

/// `user.message`: a prompt (its run's first event; `clientMsgID` is the prompt's) or a steer (right before
/// `steer.queued`), as the relay accepted it from `device`.
public struct UserMessage: StrictCodable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case prompt, steer }

    public struct Image: StrictCodable, Sendable, Equatable {
        public var id: String
        public var mime: String
        public var width: Int
        public var height: Int
        enum CodingKeys: String, CodingKey, CaseIterable { case id, mime, width, height }

        public var ref: AttachmentRef { AttachmentRef(id: id, mime: mime, width: width, height: height) }
    }

    public var kind: Kind
    public var text: String
    public var device: String
    public var clientMsgID: String?
    public var attachments: [Image]?
    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, text, device, attachments
        case clientMsgID = "client_msg_id"
    }

    public init(kind: Kind, text: String, device: String, clientMsgID: String? = nil, attachments: [Image]? = nil) {
        self.kind = kind
        self.text = text
        self.device = device
        self.clientMsgID = clientMsgID
        self.attachments = attachments
    }
}

public struct UnknownEvent: StrictCodable, Sendable, Equatable {
    public var event: String
    /// The Hermes frame without its envelope; empty and truncated when over 8 KiB.
    public var data: [String: JSONValue]
    public var truncated: Bool?
    enum CodingKeys: String, CodingKey, CaseIterable { case event, data, truncated }
}
