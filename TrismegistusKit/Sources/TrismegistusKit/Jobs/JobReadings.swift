import Foundation

// What the Jobs views read off a job, in one style: short spans, the 24-hour clock.
extension Job {
    /// "daily 03:00", "every 5m": `scheduleWords` for a sidebar row.
    public var scheduleShort: String { scheduleWords.replacingOccurrences(of: " at ", with: " ") }

    /// "Daily at 03:00".
    public var cadence: String { scheduleWords.prefix(1).uppercased() + scheduleWords.dropFirst() }

    /// The cron expression, unless the words already are it.
    public var cron: String? {
        guard let expr = schedule?.expr, expr != scheduleWords, schedule?.kind == "cron" || CronExpression(expr) != nil else { return nil }
        return expr
    }

    /// The detail header's subtitle: "daily at 03:00 · claude-opus-5-5".
    public var subtitle: String { [scheduleWords, model].compactMap { $0 }.joined(separator: " · ") }

    /// The sidebar row: `daily 03:00 · next 13 h · ok 10 h`. "err", not "failed": the row has to fit the default sidebar.
    public func meta(now: Date) -> String {
        var parts = [scheduleShort]
        if !isPaused, let next = nextRun { parts.append("next \(Self.span(next.timeIntervalSince(now)))") }
        parts.append(lastRun.map { "\(lastRunFailed ? "err" : "ok") \(Self.span(now.timeIntervalSince($0)))" } ?? "no runs yet")
        return parts.joined(separator: " · ")
    }

    /// Up to three runs: Hermes' next one, then what its cron expression or interval says follows, as far as the job's
    /// repeat count reaches. None while paused. Hermes' words for anything else give only its next run.
    public func nextRuns(calendar: Calendar = .current) -> [Date] {
        guard !isPaused, let next = nextRun else { return [] }
        var runs = [next]
        if let expr = schedule?.expr, let cron = CronExpression(expr) {
            runs += cron.next(2, after: next, calendar: calendar)
        } else if let minutes = schedule?.minutes, minutes > 0 {
            runs += [1, 2].map { next.addingTimeInterval(Double($0 * minutes * 60)) }
        }
        guard let times = `repeat`?.times else { return runs }
        return Array(runs.prefix(max(1, times - (`repeat`?.completed ?? 0))))
    }

    /// The outcome and length of `run`, the job's newest run. Hermes keeps these for the last run only and the relay's
    /// run list has neither, so older runs have none. Nil while it runs (it started after Hermes' last run ended).
    /// shortcut: older rows go without until the relay's run list carries each session's end.
    public func outcome(ofNewest run: JobRun) -> (failed: Bool, duration: String)? {
        guard lastStatus != nil, let last = lastRun, let started = run.startedAt,
              last.timeIntervalSince1970 >= started else { return nil }
        return (lastRunFailed, Self.span(last.timeIntervalSince1970 - started))
    }

    /// "42 s", "3 min", "13 h", "5 d": whole units, rounded down.
    public static func span(_ seconds: TimeInterval) -> String {
        let s = Int(abs(seconds))
        return switch s {
        case ..<60: "\(s) s"
        case ..<3600: "\(s / 60) min"
        case ..<86400: "\(s / 3600) h"
        default: "\(s / 86400) d"
        }
    }

    /// "Thu 5 Nov 03:00": the run times, in English like the rest of the app.
    public static func clockLine(_ date: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE d MMM HH:mm"
        return f.string(from: date)
    }
}
