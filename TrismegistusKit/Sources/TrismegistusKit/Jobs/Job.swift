import Foundation

/// A Hermes cron job as the relay answers it (`GET /api/jobs`, keys from Hermes' `cron/jobs.py`). Only id is required;
/// the rest is whatever Hermes sent. Model, provider, toolsets, script, workdir, context_from and failure_deliver are
/// read-only: the relay never writes them.
public struct Job: Decodable, Sendable, Equatable, Identifiable {
    public struct Schedule: Decodable, Sendable, Equatable {
        /// `once`, `interval` or `cron`.
        public var kind: String?
        /// The cron expression (kind `cron`).
        public var expr: String?
        /// Hermes' own words for it.
        public var display: String?

        enum CodingKeys: String, CodingKey { case kind, expr, display }

        public init(from decoder: any Decoder) throws {
            // A job written by an older Hermes may keep the schedule as the string it was given.
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                expr = text
                display = text
                return
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decodeIfPresent(String.self, forKey: .kind)
            expr = try c.decodeIfPresent(String.self, forKey: .expr)
            display = try c.decodeIfPresent(String.self, forKey: .display)
        }
    }

    public struct Repeat: Decodable, Sendable, Equatable {
        /// Nil: forever.
        public var times: Int?
        public var completed: Int?
    }

    public var id: String
    public var name: String?
    public var prompt: String?
    public var schedule: Schedule?
    public var scheduleDisplay: String?
    public var deliver: String?
    public var failureDeliver: String?
    public var skills: [String]?
    public var `repeat`: Repeat?
    public var enabled: Bool?
    /// `scheduled`, `paused`, `completed` or `error`.
    public var state: String?
    public var pausedReason: String?
    public var model: String?
    public var provider: String?
    public var enabledToolsets: [String]?
    public var script: String?
    public var workdir: String?
    /// Hermes' shape (an id or a list of them); shown as it is.
    public var contextFrom: JSONValue?
    /// ISO 8601 strings, as Hermes writes them; see `Job.date(_:)`.
    public var nextRunAt: String?
    public var lastRunAt: String?
    /// `ok`, or `error` with `lastError`.
    public var lastStatus: String?
    public var lastError: String?

    enum CodingKeys: String, CodingKey {
        case id, name, prompt, schedule, scheduleDisplay = "schedule_display", deliver, failureDeliver = "failure_deliver"
        case skills, `repeat`, enabled, state, pausedReason = "paused_reason", model, provider
        case enabledToolsets = "enabled_toolsets", script, workdir, contextFrom = "context_from"
        case nextRunAt = "next_run_at", lastRunAt = "last_run_at", lastStatus = "last_status", lastError = "last_error"
    }

    public var title: String { name.flatMap { $0.isEmpty ? nil : $0 } ?? id }
    public var isPaused: Bool { enabled == false || state == "paused" }
    public var lastRunFailed: Bool { lastStatus != nil && lastStatus != "ok" }
    /// The first line of the last error. Hermes' `delivery_failed` (the run worked, its delivery didn't) has no error
    /// text of its own, so it gets a line here.
    public var lastErrorLine: String? {
        if let line = lastError?.split(whereSeparator: \.isNewline).first.map(String.init) { return line }
        return lastStatus == "delivery_failed" ? "the run worked but its delivery failed" : nil
    }
    public var nextRun: Date? { Self.date(nextRunAt) }
    public var lastRun: Date? { Self.date(lastRunAt) }

    /// "daily at 03:00" for the presets' shapes; otherwise Hermes' own words, or the expression.
    public var scheduleWords: String {
        if let expr = schedule?.expr, let preset = SchedulePreset(expression: expr) { return preset.words }
        return scheduleDisplay ?? schedule?.display ?? schedule?.expr ?? "no schedule"
    }

    /// Hermes' ISO 8601 times (Python's `isoformat`: microseconds, an offset or, from older jobs, local time without).
    public static func date(_ iso: String?) -> Date? {
        guard var s = iso else { return nil }
        // ISO8601DateFormatter reads at most milliseconds; seconds are enough here.
        if let dot = s.firstIndex(of: ".") {
            let end = s[s.index(after: dot)...].firstIndex { !$0.isNumber } ?? s.endIndex
            s.removeSubrange(dot..<end)
        }
        let f = ISO8601DateFormatter()
        if let date = f.date(from: s) { return date }
        f.formatOptions = [.withFullDate, .withFullTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        f.formatOptions.remove(.withTimeZone)
        f.timeZone = .current
        return f.date(from: s)
    }
}

/// One run of a job: its session (`cron_<job id>_<YYYYMMDD_HHMMSS>`), openable like any session.
public struct JobRun: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Unix seconds.
    public var startedAt: Double?
    public var title: String?

    enum CodingKeys: String, CodingKey { case id, startedAt = "started_at", title }
}

/// What the relay lets this device do (`GET /api/me`): a `viewer` only reads jobs, a `manager` changes them.
public enum DeviceRole: String, Sendable, Equatable {
    case manager, viewer

    /// What every write refused with 403 `forbidden` says.
    public static let viewerNotice = "This device can only view: change its role on the relay (`devices set-role`)."
}
