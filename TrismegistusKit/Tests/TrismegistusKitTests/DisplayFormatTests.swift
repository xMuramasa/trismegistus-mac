import Foundation
import Testing
@testable import TrismegistusKit

struct DisplayFormatTests {
    /// 2026-11-04 16:42:07 UTC.
    let afternoon = Date(timeIntervalSince1970: 1_793_810_527)
    let utc = TimeZone(identifier: "UTC")!

    func text(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = utc
        return afternoon.formatted(style)
    }

    /// Martin's Mac runs en_CL on a 12-hour clock: the app's `hour(.twoDigits(amPM: .omitted))` showed 16:42 as `04:42`.
    @Test(arguments: ["en_CL", "en_US", "es_CL", "en_GB", "de_DE"])
    func timesReadOnTheTwentyFourHourClockInEveryRegion(_ id: String) {
        let locale = Locale(identifier: id).onTwentyFourHourClock
        #expect(text(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale)) == "16:42")
        #expect(text(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second().locale(locale)) == "16:42:07")
        #expect(text(.dateTime.day().month(.abbreviated).hour().minute().locale(locale)).contains("16:42"))
    }

    @Test func theClockKeepsTheLanguageForNames() {
        let spanish = Locale(identifier: "es_CL").onTwentyFourHourClock
        #expect(text(.dateTime.day().month(.abbreviated).locale(spanish)).contains("nov"))
        #expect(spanish.language == Locale(identifier: "es_CL").language)
        #expect(Date.FormatStyle.clock.locale.hourCycle == .zeroToTwentyThree)
        #expect(Date.FormatStyle.clock.locale.language == Locale.autoupdatingCurrent.language)
    }

    @Test func aRunIDDropsHermesPrefix() {
        #expect(RunID.short("run_61dbc6eab5414f2680e50f21051342ca") == "61db")
        #expect(RunID.short("7f3a9c01") == "7f3a")
        #expect(RunID.short("run_") == "run_")
        #expect(RunID.short("r1") == "r1")
    }
}
