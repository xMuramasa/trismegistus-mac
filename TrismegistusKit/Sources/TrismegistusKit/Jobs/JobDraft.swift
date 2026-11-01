import Foundation

/// The job form, as typed: only what the relay lets the app write (name, schedule, prompt, deliver, skills, repeat;
/// paused on create). Scripts, model, toolsets and the rest stay as Hermes has them.
public struct JobDraft: Sendable, Equatable {
    public var name = ""
    /// A cron expression, `every 2h`, `30m`, an ISO time: Hermes reads it.
    public var schedule = ""
    public var prompt = ""
    /// `local`, `telegram` (Hermes' default chat) or another target.
    public var deliver = "local"
    /// Comma-separated skill names.
    public var skills = ""
    /// A number of runs; empty is forever.
    public var repeatTimes = ""
    /// Create only: the job starts paused.
    public var paused = false

    public init() {}

    public init(job: Job) {
        name = job.name ?? ""
        schedule = job.schedule?.expr ?? job.schedule?.display ?? job.scheduleDisplay ?? ""
        prompt = job.prompt ?? ""
        deliver = job.deliver ?? "local"
        skills = (job.skills ?? []).joined(separator: ", ")
        repeatTimes = job.repeat?.times.map(String.init) ?? ""
    }

    public var skillList: [String] {
        skills.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The first thing that keeps the form from being sent, in words; nil when it can go. Hermes checks the rest
    /// (a schedule it can't read, the prompt scanner) and its message is shown instead.
    public var problem: String? {
        let name = Self.trim(name), schedule = Self.trim(schedule), repeatTimes = Self.trim(repeatTimes)
        if name.isEmpty { return "Give the job a name." }
        if name.count > 200 { return "The name is longer than 200 characters." }
        if schedule.isEmpty { return "Give the job a schedule." }
        if schedule.split(whereSeparator: \.isWhitespace).count == 5, CronExpression(schedule) == nil {
            return "The cron expression doesn't read: five fields of numbers, *, lists, ranges and steps."
        }
        if prompt.count > 5000 { return "The prompt is longer than 5,000 characters." }
        if Self.trim(deliver).isEmpty { return "Say where the output goes." }
        if !repeatTimes.isEmpty, (Int(repeatTimes) ?? 0) < 1 { return "Repeat is a number of runs, 1 or more; empty runs forever." }
        return nil
    }

    /// `POST /api/jobs`.
    public var createBody: [String: JSONValue] {
        var body: [String: JSONValue] = [
            "name": .string(Self.trim(name)), "schedule": .string(Self.trim(schedule)), "prompt": .string(prompt),
            "deliver": .string(Self.trim(deliver)), "skills": .array(skillList.map(JSONValue.string)),
        ]
        if let n = Int(Self.trim(repeatTimes)) { body["repeat"] = .number(Double(n)) }
        if paused { body["paused"] = .bool(true) }
        return body
    }

    /// `PATCH /api/jobs/:id` with only what differs from `job` (Hermes refuses an empty update); empty when nothing does.
    public func updateBody(from job: Job) -> [String: JSONValue] {
        let old = JobDraft(job: job)
        var body: [String: JSONValue] = [:]
        if Self.trim(name) != Self.trim(old.name) { body["name"] = .string(Self.trim(name)) }
        if Self.trim(schedule) != Self.trim(old.schedule) { body["schedule"] = .string(Self.trim(schedule)) }
        if prompt != old.prompt { body["prompt"] = .string(prompt) }
        if Self.trim(deliver) != Self.trim(old.deliver) { body["deliver"] = .string(Self.trim(deliver)) }
        if skillList != old.skillList { body["skills"] = .array(skillList.map(JSONValue.string)) }
        if Self.trim(repeatTimes) != Self.trim(old.repeatTimes) {
            body["repeat"] = .number(Double(Int(Self.trim(repeatTimes)) ?? 0)) // 0 is forever
        }
        return body
    }

    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
}
