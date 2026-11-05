import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The Jobs detail (#61) as `JobDetail` puts it together from the shipped `JobPanels.swift`: snapshots of a job, a failed
/// job and the editor, and the prompt's fold.
@MainActor
final class JobDetailTests: XCTestCase {
    /// The prototype's prompt (`11f-opendesign-jobs.png`).
    static let prompt: [MarkdownPart<Int>] = [
        .heading(MarkdownText.styled("Daily AI news digest")),
        .prose(MarkdownText.styled("Produce a daily AI news digest for a personal news reader (a web app, plus a short notice in Telegram), covering the last ~24 hours (since the previous edition). Use `web_search` and `web_extract` to find and verify real, dated news from reputable sources (official lab blogs, arXiv, The Verge, Ars Technica, TechCrunch, Reuters, The Information, Hugging Face, GitHub trending, etc.). Only include items published in the last ~24 hours; verify dates. Never invent items or links.")),
        .prose(MarkdownText.styled("Your previous edition (JSON) may be provided via continuity. Avoid repeating stories already covered unless there is a significant update, which you mark as an update (see CONTINUITY below).")),
        .list([
            MarkdownItem(.bullet, text: MarkdownText.styled("**Lead:** the one story that matters most today.")),
            MarkdownItem(.bullet, text: MarkdownText.styled("**Items:** five to eight, each with its source and date.")),
        ]),
        .prose(MarkdownText.styled("End with the Telegram notice, two lines at most.")),
    ]

    static let runs = ["Wed 4 Nov 03:00", "Tue 3 Nov 03:00", "Mon 2 Nov 03:00"]

    private func spin(_ seconds: Double = 0.1) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Hosted: `ImageRenderer` leaves out the code chips, native controls and what a view measures first (Show all).
    private func snap(_ name: String, _ content: some View) throws {
        let host = NSHostingView(rootView: content.frame(width: Size.runColumn + 2 * Space.l).background(Ink.surface.window))
        host.appearance = NSAppearance(named: .aqua)
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        spin()
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("\(name).png"))
    }

    /// `JobDetail`'s body with the scroll view left out: a snapshot has no window to scroll in.
    private func page(title: String, subtitle: String, @ViewBuilder trailing: () -> some View, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) {
            DetailHeader { Text(verbatim: title) } subtitle: { Text(verbatim: subtitle) } trailing: { trailing() }
            VStack(alignment: .leading, spacing: Space.l) { content() }
                .padding(Space.l)
                .frame(maxWidth: Size.jobColumn + 2 * Space.l)
                .frame(maxWidth: .infinity)
        }
    }

    private func actions(paused: Bool = false) -> JobActions {
        JobActions(isPaused: paused, isBusy: false, onPause: {}, onRun: {}, onEdit: {})
    }

    private func runRows(_ first: JobRunRow) -> some View {
        JobPanel("Runs // 3") {
            first
            ForEach(Self.runs.dropFirst(), id: \.self) { JobRunRow(time: $0, onOpen: {}) }
        }
    }

    private static let settings = [
        ("Deliver to", "telegram"), ("Skills", "none"), ("Repeat", "forever"), ("Model", "claude-opus-5-5"), ("Provider", "anthropic"),
        ("Toolsets", "web, file"), ("Script", "none"), ("Workdir", "none"), ("Context from", "none"), ("On failure", "same as delivery"),
    ]

    func testAJob() throws {
        try snap("JobDetail", page(title: "Daily AI news feed", subtitle: "daily at 03:00 · claude-opus-5-5") {
            actions()
        } content: {
            JobReadout(cadence: "Daily at 03:00", cron: "0 3 * * *", nextRuns: ["Thu 5 Nov 03:00", "Fri 6 Nov 03:00", "Sat 7 Nov 03:00"], noRuns: "none scheduled",
                       last: .init(failed: false, time: "Wed 4 Nov 03:00", ago: "10 h ago"))
            JobPromptPanel { MarkdownView(Self.prompt, lineGap: Space.xs) { _ in EmptyView() } }
            runRows(JobRunRow(time: Self.runs[0], failed: false, duration: "4 min", onOpen: {}))
            JobPanel("Settings") { JobValues(rows: Self.settings) }
        })
    }

    /// The error line under the chip, the prompt unfolded, a paused job's Resume.
    func testAFailedJob() throws {
        try snap("JobDetailFailed", page(title: "Daily cyber news feed", subtitle: "daily at 03:00 · claude-opus-5-5") {
            actions(paused: true)
        } content: {
            JobReadout(cadence: "Daily at 03:00", cron: "0 3 * * *", nextRuns: [], noRuns: "paused: provider outage",
                       last: .init(failed: true, time: "Wed 4 Nov 03:00", ago: "10 h ago", error: "Provider timed out after 120 s waiting for the first token"))
            JobPromptPanel(isOpen: true) { MarkdownView(Self.prompt, lineGap: Space.xs) { _ in EmptyView() } }
            runRows(JobRunRow(time: Self.runs[0], failed: true, duration: "2 min", onOpen: {}))
        })
    }

    private func form(new: Bool) -> some View {
        JobForm(
            name: .constant(new ? "" : "Daily AI news feed"), schedule: .constant(new ? "" : "0 3 * * *"),
            prompt: .constant(new ? "" : "Produce a daily AI news digest for a personal news reader.\n\n## Sources\n- official lab blogs\n- arXiv"),
            deliver: .constant("telegram"), skills: .constant(""), repeatTimes: .constant(""), paused: new ? .constant(false) : nil,
            picker: JobSchedulePicker(
                kind: new ? nil : "daily", kinds: ["hourly", "daily", "weekdays", "weekly"], choose: { _ in }, weekdays: [], weekday: nil, minute: nil,
                time: new ? nil : .constant(Calendar.current.date(bySettingHour: 3, minute: 0, second: 0, of: .now)!)),  // 03:00 here, as the cron
            preview: new ? "Hermes reads this schedule when the job is saved." : "next Thu 5 Nov 03:00 · Fri 6 Nov 03:00 · Sat 7 Nov 03:00",
            onDelete: new ? nil : {})
            .environment(\.locale, Self.twentyFourHourCL)
            .environment(\.timeZone, TimeZone(identifier: "America/Santiago")!)
    }

    /// What `JobDetail` gives the form on Martin's Mac: en_CL (12-hour system clock), `Locale.onTwentyFourHourClock`.
    private static let twentyFourHourCL: Locale = {
        var components = Locale.Components(locale: Locale(identifier: "en_CL@hours=h12"))
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }()

    func testTheEditor() throws {
        try snap("JobEditor", page(title: "Daily AI news feed", subtitle: "editing") {
            JobEditActions(canSave: true, onCancel: {}, onSave: {})
        } content: { form(new: false) })
    }

    func testANewJob() throws {
        try snap("JobEditorNew", page(title: "New job", subtitle: "editing") {
            JobEditActions(canSave: false, onCancel: {}, onSave: {})
        } content: { form(new: true) })
    }

    /// The schedule's time picker reads 03:00, not 3:00 AM, under en_CL.
    func testTheTimePickerIsOnTheTwentyFourHourClock() throws {
        let host = NSHostingView(rootView: form(new: false).frame(width: Size.jobColumn))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        spin()
        func picker(in view: NSView) -> NSDatePicker? {
            (view as? NSDatePicker) ?? view.subviews.lazy.compactMap(picker).first
        }
        let found = try XCTUnwrap(picker(in: host))
        XCTAssertEqual(found.locale?.hourCycle, .zeroToTwentyThree)
    }

    private func height(_ panel: some View) -> CGFloat {
        let host = NSHostingView(rootView: panel.frame(width: Size.jobColumn))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        spin()
        return host.fittingSize.height
    }

    func testThePromptFoldsAfterEightLinesAndOnlyThen() {
        func panel(_ height: CGFloat, isOpen: Bool = false) -> some View {
            JobPromptPanel(isOpen: isOpen) { Color.clear.frame(height: height) }
        }
        let exact = height(panel(Size.jobPromptFold))
        let long = height(panel(10 * Size.jobPromptFold))
        let open = height(panel(10 * Size.jobPromptFold, isOpen: true))
        XCTAssertEqual(long - exact, Space.s + Size.rowTool, accuracy: 1, "a longer prompt stops at 8 lines, with Show all")
        XCTAssertEqual(open - long, 9 * Size.jobPromptFold, accuracy: 1, "Show all opens it in full")
        XCTAssertEqual(height(panel(Size.jobPromptFold - Space.xl)), exact - Space.xl, accuracy: 1, "a short prompt has no button")
    }
}
