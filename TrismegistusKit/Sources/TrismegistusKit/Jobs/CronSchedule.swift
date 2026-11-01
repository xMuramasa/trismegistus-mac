import Foundation

/// A 5-field cron expression (minute, hour, day of month, month, day of week; 0 and 7 are Sunday) with `*`, lists,
/// ranges and steps, in the calendar's time zone: enough to preview a job's next runs. No names, `?`, `L` or `W`
/// (Hermes reads those; the preview then falls back to Hermes' own next run). When both day fields are restricted,
/// either one matches, as in cron.
public struct CronExpression: Sendable, Equatable {
    public let minutes: Set<Int>
    public let hours: Set<Int>
    public let days: Set<Int>
    public let months: Set<Int>
    public let weekdays: Set<Int>
    let anyDay: Bool
    let anyWeekday: Bool

    public init?(_ text: String) {
        let f = text.split(whereSeparator: \.isWhitespace)
        guard f.count == 5,
              let minutes = Self.field(f[0], 0...59), let hours = Self.field(f[1], 0...23),
              let days = Self.field(f[2], 1...31), let months = Self.field(f[3], 1...12),
              var weekdays = Self.field(f[4], 0...7)
        else { return nil }
        if weekdays.remove(7) != nil { weekdays.insert(0) }
        (self.minutes, self.hours, self.days, self.months, self.weekdays) = (minutes, hours, days, months, weekdays)
        anyDay = f[2] == "*"
        anyWeekday = f[4] == "*"
    }

    /// The next `count` times after `date`; fewer when nothing matches within five years (`0 0 30 2 *`).
    public func next(_ count: Int, after date: Date, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        let hours = self.hours.sorted(), minutes = self.minutes.sorted()
        var day = calendar.startOfDay(for: date)
        for _ in 0..<(366 * 5) {
            let c = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            if let month = c.month, let d = c.day, let weekday = c.weekday, months.contains(month), matches(day: d, weekday: weekday - 1) {
                for h in hours {
                    for m in minutes {
                        // A time skipped by a DST change comes back as the hour after; `>` keeps it once.
                        guard let t = calendar.date(from: DateComponents(year: c.year, month: month, day: d, hour: h, minute: m)),
                              t > (out.last ?? date) else { continue }
                        out.append(t)
                        if out.count == count { return out }
                    }
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return out
    }

    func matches(day: Int, weekday: Int) -> Bool {
        anyDay || anyWeekday
            ? days.contains(day) && weekdays.contains(weekday)
            : days.contains(day) || weekdays.contains(weekday)
    }

    /// `*`, `n`, `a-b`, each with an optional `/step`, comma-separated. `n/step` runs from n to the end of the range.
    static func field(_ text: Substring, _ range: ClosedRange<Int>) -> Set<Int>? {
        var values: Set<Int> = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(pieces.count) else { return nil }
            var step = 1
            if pieces.count == 2 {
                guard let n = Int(pieces[1]), n > 0 else { return nil }
                step = n
            }
            let span: ClosedRange<Int>
            if pieces[0] == "*" {
                span = range
            } else {
                let bounds = pieces[0].split(separator: "-", omittingEmptySubsequences: false)
                guard (1...2).contains(bounds.count), let lo = Int(bounds[0]), let hi = Int(bounds[bounds.count - 1]),
                      range.contains(lo), range.contains(hi), lo <= hi else { return nil }
                span = lo...(bounds.count == 1 && pieces.count == 2 ? range.upperBound : hi)
            }
            values.formUnion(stride(from: span.lowerBound, through: span.upperBound, by: step))
        }
        return values
    }
}

/// The schedule presets the job form offers; each writes a cron expression.
public struct SchedulePreset: Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable {
        case hourly, daily, weekdays, weekly
    }

    public var kind: Kind
    public var hour: Int
    public var minute: Int
    /// 0 is Sunday, as in cron; only `weekly` uses it.
    public var weekday: Int

    public static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    public init(_ kind: Kind, hour: Int = 9, minute: Int = 0, weekday: Int = 1) {
        self.kind = kind
        self.hour = hour
        self.minute = minute
        self.weekday = weekday
    }

    /// The preset an expression was written by, if it has one of their shapes.
    public init?(expression: String) {
        let f = expression.split(whereSeparator: \.isWhitespace)
        guard f.count == 5, f[2] == "*", f[3] == "*", let m = Int(f[0]), (0...59).contains(m) else { return nil }
        if f[1] == "*" {
            guard f[4] == "*" else { return nil }
            self.init(.hourly, minute: m)
            return
        }
        guard let h = Int(f[1]), (0...23).contains(h) else { return nil }
        switch f[4] {
        case "*": self.init(.daily, hour: h, minute: m)
        case "1-5": self.init(.weekdays, hour: h, minute: m)
        default:
            guard let d = Int(f[4]), (0...7).contains(d) else { return nil }
            self.init(.weekly, hour: h, minute: m, weekday: d % 7)
        }
    }

    public var expression: String {
        switch kind {
        case .hourly: "\(minute) * * * *"
        case .daily: "\(minute) \(hour) * * *"
        case .weekdays: "\(minute) \(hour) * * 1-5"
        case .weekly: "\(minute) \(hour) * * \(weekday)"
        }
    }

    /// "hourly at :15", "daily at 03:00", "weekdays at 09:00", "Mondays at 09:00".
    public var words: String {
        let clock = String(format: "%02d:%02d", hour, minute)
        return switch kind {
        case .hourly: String(format: "hourly at :%02d", minute)
        case .daily: "daily at \(clock)"
        case .weekdays: "weekdays at \(clock)"
        case .weekly: "\(Self.weekdayNames[weekday])s at \(clock)"
        }
    }
}
