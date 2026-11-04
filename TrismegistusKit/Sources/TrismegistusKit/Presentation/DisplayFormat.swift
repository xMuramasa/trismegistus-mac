import Foundation

// How the app writes times and run ids, the same in every view and every region.

extension Locale {
    /// The same language and region (month and weekday names, field order) on a 24-hour clock.
    public var onTwentyFourHourClock: Locale {
        var components = Locale.Components(locale: self)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }
}

extension FormatStyle where Self == Date.FormatStyle {
    /// `.dateTime` in the user's language on a 24-hour clock: every time the app shows starts here
    /// (`.clock.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)` → `13:42`). On a 12-hour region (en_CL, Martin's
    /// Mac) `hour(.twoDigits(amPM: .omitted))` alone dropped the AM/PM and showed 13:42 as `01:42`, beside Jobs saying
    /// `1:42 PM`. `scripts/check-tokens.sh` (e) keeps views off `.dateTime` and the system time styles.
    public static var clock: Date.FormatStyle { .dateTime.locale(Locale.autoupdatingCurrent.onTwentyFourHourClock) }
}

public enum RunID {
    /// A run's id in four characters, as in `run 61db`: Hermes names its runs `run_<hex>`, so the first four
    /// characters were always `run_`.
    public static func short(_ id: String) -> String {
        let name = id.hasPrefix("run_") && id.count > 4 ? id.dropFirst(4) : Substring(id)
        return String(name.prefix(4))
    }
}
