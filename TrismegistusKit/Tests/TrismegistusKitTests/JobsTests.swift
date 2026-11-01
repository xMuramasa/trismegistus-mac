import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// A job as relay/internal/server/jobs.go answers it (keys trimmed to its jobFields), from fakehermes' record.
let sampleJob = #"""
{"id":"0000000000a1","name":"Nightly backup","prompt":"Back up the notes.","schedule":{"kind":"cron","expr":"0 3 * * *","display":"0 3 * * *"},
"schedule_display":"0 3 * * *","deliver":"telegram","skills":["backup","notes"],"repeat":{"times":null,"completed":4},
"enabled":true,"state":"scheduled","paused_at":null,"paused_reason":null,"model":"claude-opus-5-5","provider":"anthropic",
"enabled_toolsets":["terminal","file"],"script":null,"workdir":"/home/m","context_from":["0000000000a0"],
"created_at":"2026-11-01T09:00:00+00:00","next_run_at":"2026-11-02T03:00:00.123456+00:00",
"last_run_at":"2026-11-01T03:00:04.5+00:00","last_status":"error","last_error":"Provider timed out\nTraceback..."}
"""#

@Suite struct JobDecodingTests {
    @Test func job() throws {
        let job = try Wire.decode(Job.self, from: Data(sampleJob.utf8))
        #expect(job.id == "0000000000a1" && job.title == "Nightly backup" && job.prompt == "Back up the notes.")
        #expect(job.schedule?.kind == "cron" && job.schedule?.expr == "0 3 * * *")
        #expect(job.scheduleWords == "daily at 03:00")
        #expect(job.deliver == "telegram" && job.skills == ["backup", "notes"])
        #expect(job.repeat == Job.Repeat(times: nil, completed: 4))
        #expect(!job.isPaused)
        #expect(job.model == "claude-opus-5-5" && job.provider == "anthropic" && job.enabledToolsets == ["terminal", "file"])
        #expect(job.script == nil && job.workdir == "/home/m" && job.contextFrom == .array([.string("0000000000a0")]))
        #expect(job.lastRunFailed && job.lastErrorLine == "Provider timed out")
        #expect(job.nextRun == Date(timeIntervalSince1970: 1_793_588_400)) // 2026-11-02T03:00:00Z, microseconds dropped
        #expect(job.lastRun == Date(timeIntervalSince1970: 1_793_502_004))
    }

    @Test func pausedIntervalJob() throws {
        let json = #"{"id":"0000000000b2","schedule":{"kind":"interval","minutes":120,"display":"every 120m"},"enabled":false,"state":"paused","last_status":"ok"}"#
        let job = try Wire.decode(Job.self, from: Data(json.utf8))
        #expect(job.isPaused && !job.lastRunFailed && job.lastErrorLine == nil)
        #expect(job.scheduleWords == "every 120m")
        #expect(job.title == "0000000000b2")
    }

    @Test func deliveryFailedHasALine() throws {
        let json = #"{"id":"0000000000c3","last_status":"delivery_failed","last_error":null}"#
        let job = try Wire.decode(Job.self, from: Data(json.utf8))
        #expect(job.lastRunFailed && job.lastErrorLine == "the run worked but its delivery failed")
    }

    @Test func scheduleAsString() throws {
        let job = try Wire.decode(Job.self, from: Data(#"{"id":"0000000000c3","schedule":"30 9 * * 1-5"}"#.utf8))
        #expect(job.scheduleWords == "weekdays at 09:30")
    }

    @Test func otherCronKeepsHermesWords() throws {
        let json = #"{"id":"0000000000c4","schedule":{"kind":"cron","expr":"*/15 * * * *"},"schedule_display":"*/15 * * * *"}"#
        #expect(try Wire.decode(Job.self, from: Data(json.utf8)).scheduleWords == "*/15 * * * *")
    }

    @Test func dates() {
        #expect(Job.date("2026-11-02T03:00:00+00:00") == Date(timeIntervalSince1970: 1_793_588_400))
        #expect(Job.date("2026-11-02T04:00:00.5+01:00") == Date(timeIntervalSince1970: 1_793_588_400))
        #expect(Job.date("2026-11-02T03:00:00") != nil) // local time, from older jobs
        #expect(Job.date("soon") == nil && Job.date(nil) == nil)
    }
}

@Suite struct CronTests {
    /// Fixed zone and dates, so the tests don't depend on the machine's.
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Santiago")!
        return c
    }()

    func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func next(_ expr: String, after: Date, _ count: Int = 3) -> [Date] {
        CronExpression(expr)?.next(count, after: after, calendar: Self.calendar) ?? []
    }

    @Test func fields() throws {
        let e = try #require(CronExpression("*/20 9-17/4 1,15 * 7"))
        #expect(e.minutes == [0, 20, 40] && e.hours == [9, 13, 17] && e.days == [1, 15] && e.weekdays == [0])
        #expect(CronExpression("5/20 * * * *")?.minutes == [5, 25, 45])
        #expect(CronExpression("0 0 * 1-12/6 *")?.months == [1, 7])
    }

    @Test(arguments: ["", "* * * *", "* * * * * *", "60 * * * *", "* 24 * * *", "* * 0 * *", "* * * 13 *", "* * * * 8",
                      "*/0 * * * *", "5-1 * * * *", "a * * * *", "-1 * * * *", "1,,2 * * * *", "1/2/3 * * * *", "@daily"])
    func rejects(_ expr: String) {
        #expect(CronExpression(expr) == nil)
    }

    @Test func daily() {
        #expect(next("0 3 * * *", after: date(2026, 11, 1, 2, 59)) == [date(2026, 11, 1, 3), date(2026, 11, 2, 3), date(2026, 11, 3, 3)])
        // Exactly at a run: the next one, not this one.
        #expect(next("0 3 * * *", after: date(2026, 11, 1, 3), 1) == [date(2026, 11, 2, 3)])
    }

    @Test func steps() {
        #expect(next("*/15 * * * *", after: date(2026, 11, 1, 10, 7)) == [date(2026, 11, 1, 10, 15), date(2026, 11, 1, 10, 30), date(2026, 11, 1, 10, 45)])
        #expect(next("0 */6 * * *", after: date(2026, 11, 1, 19)) == [date(2026, 11, 2, 0), date(2026, 11, 2, 6), date(2026, 11, 2, 12)])
    }

    @Test func weekdays() {
        // 2026-11-06 is a Friday.
        #expect(next("30 9 * * 1-5", after: date(2026, 11, 6, 10)) == [date(2026, 11, 9, 9, 30), date(2026, 11, 10, 9, 30), date(2026, 11, 11, 9, 30)])
        #expect(next("0 8 * * 0", after: date(2026, 11, 6)) == next("0 8 * * 7", after: date(2026, 11, 6)))
        #expect(next("0 8 * * 0", after: date(2026, 11, 6), 1) == [date(2026, 11, 8, 8)])
    }

    @Test func dayOfMonthOrWeekday() {
        // Both restricted: the 13th or any Friday.
        #expect(next("0 0 13 * 5", after: date(2026, 11, 1)) == [date(2026, 11, 6), date(2026, 11, 13), date(2026, 11, 20)])
        // Only one restricted: that one.
        #expect(next("0 0 13 * *", after: date(2026, 11, 1), 2) == [date(2026, 11, 13), date(2026, 12, 13)])
    }

    @Test func monthsAndLeapDays() {
        #expect(next("0 12 29 2 *", after: date(2026, 11, 1), 1) == [date(2028, 2, 29, 12)])
        #expect(next("0 0 31 * *", after: date(2026, 11, 1), 2) == [date(2026, 12, 31), date(2027, 1, 31)])
        #expect(next("0 0 30 2 *", after: date(2026, 11, 1)).isEmpty)
    }

    @Test func dstSkippedHourComesOnce() {
        // Chile springs forward on 2026-09-06 at 00:00 → 01:00: 00:30 doesn't exist that day.
        let runs = next("30 0 * * *", after: date(2026, 9, 5, 12))
        #expect(runs.count == 3 && Set(runs).count == 3 && runs == runs.sorted())
    }
}

@Suite struct SchedulePresetTests {
    @Test(arguments: [
        (SchedulePreset(.hourly, minute: 5), "5 * * * *", "hourly at :05"),
        (SchedulePreset(.daily, hour: 3, minute: 0), "0 3 * * *", "daily at 03:00"),
        (SchedulePreset(.weekdays, hour: 9, minute: 30), "30 9 * * 1-5", "weekdays at 09:30"),
        (SchedulePreset(.weekly, hour: 18, minute: 45, weekday: 1), "45 18 * * 1", "Mondays at 18:45"),
        (SchedulePreset(.weekly, hour: 8, minute: 0, weekday: 0), "0 8 * * 0", "Sundays at 08:00"),
    ])
    func roundTrip(_ preset: SchedulePreset, _ expression: String, _ words: String) {
        #expect(preset.expression == expression && preset.words == words)
        #expect(SchedulePreset(expression: expression) == preset)
        #expect(CronExpression(expression) != nil)
    }

    @Test func readsSundayAsSeven() {
        #expect(SchedulePreset(expression: "0 8 * * 7") == SchedulePreset(.weekly, hour: 8, minute: 0, weekday: 0))
    }

    @Test(arguments: ["*/5 * * * *", "0 3 1 * *", "0 3 * 1 *", "0 3 * * 1,3", "5 * * * 1", "0 24 * * *", "every 2h", "30m"])
    func notAPreset(_ expr: String) {
        #expect(SchedulePreset(expression: expr) == nil)
    }
}

@Suite struct JobDraftTests {
    func valid() -> JobDraft {
        var d = JobDraft()
        d.name = "Backup"
        d.schedule = "0 3 * * *"
        d.prompt = "Back up."
        return d
    }

    @Test func validates() {
        #expect(valid().problem == nil)
        var d = valid()
        d.name = "  "
        #expect(d.problem == "Give the job a name.")
        d = valid(); d.name = String(repeating: "n", count: 201)
        #expect(d.problem?.contains("200") == true)
        d = valid(); d.schedule = ""
        #expect(d.problem == "Give the job a schedule.")
        d = valid(); d.schedule = "0 25 * * *"
        #expect(d.problem?.contains("cron") == true)
        d = valid(); d.prompt = String(repeating: "p", count: 5001)
        #expect(d.problem?.contains("5,000") == true)
        d = valid(); d.deliver = " "
        #expect(d.problem != nil)
        for bad in ["0", "-2", "two"] {
            d = valid(); d.repeatTimes = bad
            #expect(d.problem?.hasPrefix("Repeat") == true)
        }
    }

    @Test(arguments: ["every 2h", "30m", "2026-11-02T09:00", "0 9 * * 1-5"])
    func otherSchedulesAreHermesToRead(_ schedule: String) {
        var d = valid()
        d.schedule = schedule
        #expect(d.problem == nil)
    }

    @Test func createBody() throws {
        var d = valid()
        d.name = " Backup "
        d.deliver = "telegram"
        d.skills = "backup, , notes"
        d.repeatTimes = "3"
        d.paused = true
        let json = String(decoding: try Wire.encode(d.createBody), as: UTF8.self)
        #expect(json == #"{"deliver":"telegram","name":"Backup","paused":true,"prompt":"Back up.","repeat":3,"schedule":"0 3 * * *","skills":["backup","notes"]}"#)
        // Forever and running: no repeat, no paused.
        #expect(valid().createBody["repeat"] == nil && valid().createBody["paused"] == nil)
    }

    @Test func updateBodyHasOnlyChanges() throws {
        let job = try Wire.decode(Job.self, from: Data(sampleJob.utf8))
        var d = JobDraft(job: job)
        #expect(d.name == "Nightly backup" && d.schedule == "0 3 * * *" && d.skills == "backup, notes" && d.repeatTimes == "")
        #expect(d.updateBody(from: job).isEmpty)
        d.skills = "notes,backup " // order matters to Hermes
        d.schedule = "0 4 * * *"
        d.repeatTimes = "2"
        #expect(d.updateBody(from: job) == ["schedule": .string("0 4 * * *"), "skills": .array([.string("notes"), .string("backup")]), "repeat": .number(2)])
        d.repeatTimes = ""
        var withRepeat = job
        withRepeat.repeat = Job.Repeat(times: 5, completed: 1)
        #expect(d.updateBody(from: withRepeat)["repeat"] == .number(0)) // back to forever
    }
}

@Suite struct JobRESTTests {
    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http), http)
    }

    @Test func role() async throws {
        #expect(try await rest { _ in (200, #"{"device":"mac","role":"manager"}"#) }.0.role() == .manager)
        #expect(try await rest { _ in (200, #"{"device":"mac","role":"owner"}"#) }.0.role() == .viewer)
        #expect(try await rest { _ in (404, "404 page not found") }.0.role() == .viewer)
        let (api, http) = rest { _ in (200, #"{"device":"mac","role":"viewer"}"#) }
        _ = try await api.role()
        #expect(http.requests.current.first?.url?.path == "/api/me")
    }

    @Test func listAndRuns() async throws {
        let (api, http) = rest { r in
            r.url!.path.hasSuffix("/runs")
                ? (200, #"{"runs":[{"id":"cron_0000000000a1_20261101_030000","started_at":1793502000,"title":null},{"id":"cron_0000000000a1_20261031_030000","started_at":null,"title":"Backup"}]}"#)
                : (200, #"{"jobs":[\#(sampleJob),{"name":"no id"}]}"#)
        }
        #expect(try await api.jobs().map(\.id) == ["0000000000a1"]) // the malformed one is skipped
        let runs = try await api.jobRuns("0000000000a1")
        #expect(runs.map(\.id) == ["cron_0000000000a1_20261101_030000", "cron_0000000000a1_20261031_030000"])
        #expect(runs[0].startedAt == 1_793_502_000 && runs[1].title == "Backup")
        #expect(http.requests.current.map { $0.url!.absoluteString } == ["https://relay.invalid/api/jobs", "https://relay.invalid/api/jobs/0000000000a1/runs"])
    }

    @Test func writes() async throws {
        let (api, http) = rest { r in r.httpMethod == "DELETE" ? (200, #"{"ok":true}"#) : (200, #"{"job":\#(sampleJob)}"#) }
        _ = try await api.createJob(["name": .string("Backup")])
        _ = try await api.updateJob("0000000000a1", ["prompt": .string("x")])
        _ = try await api.jobAction("0000000000a1", .pause)
        _ = try await api.jobAction("0000000000a1", .resume)
        _ = try await api.jobAction("0000000000a1", .run)
        try await api.deleteJob("0000000000a1")
        #expect(http.requests.current.map { "\($0.httpMethod!) \($0.url!.path)" } == [
            "POST /api/jobs", "PATCH /api/jobs/0000000000a1", "POST /api/jobs/0000000000a1/pause",
            "POST /api/jobs/0000000000a1/resume", "POST /api/jobs/0000000000a1/run", "DELETE /api/jobs/0000000000a1",
        ])
        let patch = http.requests.current[1]
        #expect(patch.httpBody.map { String(decoding: $0, as: UTF8.self) } == #"{"prompt":"x"}"#)
    }

    @Test func badIDNeverLeaves() async {
        let (api, http) = rest { _ in (200, "{}") }
        for id in ["0000000000A1", "short", "0000000000a1/../x", "cron_0000000000a1"] {
            await #expect(throws: RelayAPIError(status: 0, code: .notFound, message: "Unknown job.")) { try await api.deleteJob(id) }
        }
        #expect(http.requests.current.isEmpty)
    }

    @Test func refusalKeepsHermesMessage() async {
        let (api, _) = rest { _ in (400, #"{"error":{"code":"bad_request","message":"Name must be ≤ 200 characters"}}"#) }
        await #expect(throws: RelayAPIError(status: 400, code: .badRequest, message: "Name must be ≤ 200 characters")) {
            try await api.createJob([:])
        }
    }
}

@MainActor @Suite struct JobBoardTests {
    @Test func refreshLearnsRoleAndLists() async throws {
        let http = FakeHTTP { r in
            r.url!.path == "/api/me" ? (200, #"{"device":"mac","role":"manager"}"#) : (200, #"{"jobs":[\#(sampleJob)]}"#)
        }
        let board = JobBoard(rest: RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http))
        #expect(!board.canManage && !board.isLoaded)
        await board.refresh()
        await board.refresh()
        #expect(board.canManage && board.isLoaded && board.jobs.count == 1 && board.anyFailed)
        #expect(http.requests.current.map { $0.url!.path } == ["/api/me", "/api/jobs", "/api/me", "/api/jobs"])
    }

    @Test func hermesWithoutCron() async {
        let http = FakeHTTP { r in
            r.url!.path == "/api/me" ? (200, #"{"device":"phone","role":"viewer"}"#)
                : (503, #"{"error":{"code":"hermes_unavailable","message":"Hermes' cron scheduler is not available"}}"#)
        }
        let board = JobBoard(rest: RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http))
        await board.refresh()
        #expect(board.error?.code == .hermesUnavailable && board.role == .viewer && board.isLoaded && board.jobs.isEmpty)
    }

    @Test func writesKeepTheList() async throws {
        let paused = sampleJob.replacingOccurrences(of: #""enabled":true,"state":"scheduled""#, with: #""enabled":false,"state":"paused""#)
        let http = FakeHTTP { r in
            switch (r.httpMethod!, r.url!.path) {
            case ("GET", "/api/me"): (200, #"{"device":"mac","role":"manager"}"#)
            case ("GET", "/api/jobs"): (200, #"{"jobs":[\#(sampleJob)]}"#)
            case ("POST", "/api/jobs/0000000000a1/pause"): (200, #"{"job":\#(paused)}"#)
            case ("DELETE", _): (200, #"{"ok":true}"#)
            case ("PATCH", _): (500, #"{"error":{"code":"hermes_error","message":"Invalid cron expression"}}"#)
            default: (404, "")
            }
        }
        let board = JobBoard(rest: RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http))
        await board.refresh()
        let job = try #require(board.jobs.first)
        try await board.perform(.pause, on: job)
        #expect(board.jobs.count == 1 && board.jobs[0].isPaused)

        // Nothing changed: nothing sent.
        try await board.save(JobDraft(job: job), to: job)
        var draft = JobDraft(job: job)
        draft.schedule = "0 3 * * 9"
        await #expect(throws: RelayAPIError(status: 500, code: .hermesError, message: "Invalid cron expression")) {
            try await board.save(draft, to: job)
        }
        // The failed write reloaded the list.
        #expect(http.requests.current.suffix(3).map { "\($0.httpMethod!) \($0.url!.path)" } == ["PATCH /api/jobs/0000000000a1", "GET /api/me", "GET /api/jobs"])

        try await board.delete(board.jobs[0])
        #expect(board.jobs.isEmpty)
    }
}
