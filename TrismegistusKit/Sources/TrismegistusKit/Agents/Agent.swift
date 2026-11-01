import Foundation

/// One background run on optiplex (`GET /api/agents`): a Hermes background process or a Claude Code delegate run,
/// alive or recently finished. Hermes subagents are not listed (the relay can't see them).
public struct Agent: Decodable, Sendable, Equatable, Identifiable {
    /// `proc_…` for a process, `run_<name>` for a delegate run.
    public var id: String
    /// `process` or `delegate`.
    public var kind: String
    public var title: String
    public var command: String?
    public var cwd: String?
    /// Unix seconds.
    public var startedAt: Double?
    /// Finished runs: when the transcript was last written.
    public var endedAt: Double?
    public var alive: Bool
    /// The Hermes conversation that started it, when Hermes recorded one.
    public var sessionID: String?
    /// False for plain processes: Hermes keeps their output in its own memory.
    public var hasTranscript: Bool
    /// Delegate runs: the last line of the progress file.
    public var progress: String?
    /// The result line's subtype (`success`, `error_max_turns`, …); absent while running or when killed.
    public var outcome: String?
    public var numTurns: Int?
    public var durationMs: Int?

    public var isDelegate: Bool { kind == "delegate" }
    public var started: Date? { startedAt.map(Date.init(timeIntervalSince1970:)) }
    public var ended: Date? { endedAt.map(Date.init(timeIntervalSince1970:)) }
    /// A finished run that ended in anything but `success`.
    public var failed: Bool { !alive && outcome.map { $0 != "success" } ?? false }

    /// "running", "done", "out of turns", "failed", or "ended" when nothing says how.
    public var statusWords: String {
        if alive { return "running" }
        switch outcome {
        case nil: return "ended"
        case "success": return "done"
        case "error_max_turns": return "out of turns"
        case "error_during_execution": return "failed"
        case let other?: return other.replacingOccurrences(of: "_", with: " ")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, title, command, cwd, alive, transcript, progress, outcome
        case startedAt = "started_at", endedAt = "ended_at", sessionID = "session_id", numTurns = "num_turns", durationMs = "duration_ms"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "process"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? id
        command = try c.decodeIfPresent(String.self, forKey: .command)
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd)
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Double.self, forKey: .endedAt)
        alive = try c.decodeIfPresent(Bool.self, forKey: .alive) ?? false
        sessionID = try c.decodeIfPresent(String.self, forKey: .sessionID)
        hasTranscript = try c.decodeIfPresent(Bool.self, forKey: .transcript) ?? false
        progress = try c.decodeIfPresent(String.self, forKey: .progress)
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome)
        numTurns = try c.decodeIfPresent(Int.self, forKey: .numTurns)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
    }
}

/// One readable step of a Claude Code run's transcript.
public struct AgentStep: Decodable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case text, tool, toolResult = "tool_result", result, unknown }

    /// The stream-json line number it came from; `after=` takes one.
    public var line: Int
    public var kind: Kind
    public var text: String
    /// A `tool_result` of a tool that failed.
    public var error: Bool

    public var id: Int { line }

    enum CodingKeys: String, CodingKey { case line, kind, text, error }

    public init(line: Int, kind: Kind, text: String, error: Bool = false) {
        self.line = line
        self.kind = kind
        self.text = text
        self.error = error
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        line = try c.decode(Int.self, forKey: .line)
        kind = Kind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "") ?? .unknown
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        error = try c.decodeIfPresent(Bool.self, forKey: .error) ?? false
    }
}

/// `GET /api/agents/:id/transcript?after=N`.
public struct AgentTranscriptPage: Decodable, Sendable, Equatable {
    public var steps: [AgentStep]
    /// Ask again with `after=next`.
    public var next: Int
    /// Absent for a process without a transcript.
    public var alive: Bool?

    enum CodingKeys: String, CodingKey { case steps, next, alive }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = (try c.decodeIfPresent(Lossy<AgentStep>.self, forKey: .steps))?.items ?? []
        next = try c.decode(Int.self, forKey: .next)
        alive = try c.decodeIfPresent(Bool.self, forKey: .alive)
    }
}

/// The relay's agents errors (`{"error": {code, message}}`); `not_configured` (the host helper isn't installed or
/// isn't running) and `forbidden` are REST-only codes, so not `ErrorCode`.
public struct AgentsError: Error, Sendable, Equatable {
    /// HTTP status; 0 when the request was refused before it was sent (a bad id) or never answered.
    public let status: Int
    public let code: String
    public let message: String

    public init(status: Int, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }

    init(status: Int, body: Data) {
        struct Body: Decodable {
            struct Inner: Decodable { var code: String?; var message: String? }
            var error: Inner?
        }
        let inner = (try? Wire.decode(Body.self, from: body))?.error
        self.init(
            status: status, code: inner?.code ?? "http_\(status)",
            message: String((inner?.message ?? "The relay answered \(status).").prefix(512)))
    }

    public var isNotConfigured: Bool { code == "not_configured" }
    public var isNotFound: Bool { code == "not_found" }

    /// What the app shows for any error of an agents call.
    public static func describe(_ error: any Error) -> String {
        switch error {
        case let e as AgentsError where e.isNotConfigured: "The agents helper isn't running."
        case let e as AgentsError where e.code == "forbidden": "This device can read agents but not stop them."
        case let e as AgentsError: e.message
        case let e as RelayAPIError: e.message
        default: "Can't reach the relay."
        }
    }

    /// Any error of an agents call as an `AgentsError`.
    static func wrap(_ error: any Error) -> AgentsError {
        error as? AgentsError ?? AgentsError(status: 0, code: "unreachable", message: describe(error))
    }
}
