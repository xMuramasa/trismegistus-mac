import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The Agents detail (#60) as `AgentRunPane` puts it together from the shipped cards (`AgentCards.swift`): snapshots of
/// a finished, a failed and a live run, and its scrolling.
@MainActor
final class AgentRunTests: XCTestCase {
    struct Step {
        var tool: String?
        var text: String
        var failed: Bool?
        var output: String?
    }

    /// The prototype's run (`11e-opendesign-agents.png`), without the durations the transcript doesn't have.
    static let steps: [Step] = [
        Step(tool: "Grep", text: "\"sync|triangle|vector-square\" apps/homepage/theme/icons.json", failed: false, output: "12: \"sync\""),
        Step(tool: "Edit", text: "apps/homepage/theme/icons.json", failed: false, output: "/home/muramasa/Projects/homelab-wt/issue-1/apps/homepage/theme/icons.json\n1 replacement"),
        Step(tool: "Edit", text: "apps/homepage/services.yaml", failed: false, output: "1 replacement"),
        Step(text: "Edits to the three source files are in. Now I'm running the build and checking the YAML and the custom.css diff."),
        Step(tool: "Bash", text: "python3 apps/homepage/theme/build.py && python3 -c \"import yaml,sys; yaml.safe_load(open(sys.argv[1]))\" apps/homepage/services.yaml",
             failed: true, output: "Command requires approval"),
        Step(text: "Compound commands need approval, so I'll run them one at a time."),
        Step(tool: "Bash", text: "python3 apps/homepage/theme/build.py", failed: true, output: "Command requires approval"),
        Step(tool: "Write", text: "~/.local/state/hermes-runs/homelab-issue-1-report.md", failed: false, output: "File created"),
    ]

    static let report: [MarkdownPart<Int>] = [
        .prose(MarkdownText.styled("Every `python3` call was refused with \"requires approval\", so I ran no tests and haven't confirmed the build prints `11 tiles`.")),
        .list([
            MarkdownItem(.bullet, text: MarkdownText.styled("`services.yaml`: the `Trismegistus` entry is last in `Infrastructure`, as specced.")),
            MarkdownItem(.bullet, text: MarkdownText.styled("`build.py`: I added the `Trismegistus` line to `SERVICES` and set Claude Usage's wide flag to `False`.")),
            MarkdownItem(.bullet, text: MarkdownText.styled("`icons.json`: I added `cellphone-link` in sorted position, before `chart-line`.")),
        ]),
        .prose(MarkdownText.styled("**For you to do:** run `python3 apps/homepage/theme/build.py` in the worktree, then the YAML parse, then check that the `custom.css` diff covers only the new tile, the icon variable and Claude Usage's span. The report spells this out.")),
        .prose(MarkdownText.styled("I haven't looked at the 1280×800 layout or the 4-row claim. The Kuma monitor stays on homelab#3, as the issue says.")),
    ]

    private func run(_ chip: StatusChip, meta: String, title: String, report: [MarkdownPart<Int>] = [], steps: [Step], open: Set<Int> = []) -> some View {
        VStack(spacing: Space.xxl) {
            AgentResultCard(chip: chip, meta: meta, title: MarkdownText.styled(title)) {
                if !report.isEmpty { MarkdownView(report) { _ in EmptyView() } }
            }
            AgentStepsCard(
                line: "\(steps.count { $0.tool != nil }) steps · \(steps.count { $0.failed == true }) failed", isOpen: .constant(true)
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(steps.indices, id: \.self) { i in
                        let step = steps[i]
                        if let tool = step.tool {
                            ToolCallRow(symbol: agentToolSymbol(tool), tool: tool, command: step.text, failed: step.failed, output: step.output,
                                        isOpen: .constant(open.contains(i)))
                        } else {
                            ToolNarration(step.text)
                        }
                    }
                }
            }
        }
    }

    private func spin(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Hosted: `ImageRenderer` leaves out the code chips, and one pass leaves out what a view measures first (Show all).
    private func snap(_ name: String, _ content: some View) throws {
        let host = NSHostingView(rootView: content.padding(Space.l).frame(width: Size.runColumn + 2 * Space.l).background(Palette.paper))
        host.appearance = NSAppearance(named: .aqua)
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        spin(0.1)
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("\(name).png"))
    }

    /// A long report folded, every step OK or failed, one step open with its full path.
    func testFinishedRun() throws {
        try snap("AgentRunDone", run(
            StatusChip("done", kind: .ok), meta: "14 turns · 53 s · ended 3 h ago",
            title: "The three source edits for the Trismegistus tile are in, but the build never ran, so `custom.css` is stale.",
            report: Self.report, steps: Self.steps, open: [1]))
    }

    /// A short report in full, a failed step open in terminal-red.
    func testFailedRun() throws {
        try snap("AgentRunFailed", run(
            StatusChip("out of turns", kind: .err), meta: "120 turns · 16 min, 40 sec · ended 2 h ago", title: "Stopped at the turn limit.",
            report: [.prose(MarkdownText.styled("The build still fails; the report has the last error."))], steps: Self.steps, open: [4]))
    }

    /// The last progress line and no report, a tool with no status yet; a run stopped without a report.
    func testLiveAndStoppedRuns() throws {
        let live = Self.steps.prefix(6) + [Step(tool: "Bash", text: "python3 apps/homepage/theme/build.py")]
        try snap("AgentRunLive", run(StatusChip("running", kind: .warn), meta: "started 5 min ago", title: "Item 2 done, tests green", steps: Array(live)))
        try snap("AgentRunStopped", run(StatusChip("ended", kind: .neutral), meta: "ended 1 h ago", title: "No report.", steps: Array(Self.steps.prefix(3))))
    }

    private func height(_ card: some View) -> CGFloat {
        let host = NSHostingView(rootView: card.frame(width: Size.runColumn))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        spin(0.1)
        return host.fittingSize.height
    }

    func testTheReportFoldsAfterEightLinesAndOnlyThen() {
        func card(_ report: some View) -> some View {
            AgentResultCard(chip: StatusChip("done", kind: .ok), meta: "1 turn", title: AttributedString("Title")) { report }
        }
        let line = Text(verbatim: "one line").typeRole(.body)
        let none = height(card(EmptyView()))
        let short = height(card(line))
        let exact = height(card(Color.clear.frame(height: Size.reportFold)))
        let long = height(card(Color.clear.frame(height: 10 * Size.reportFold)))
        XCTAssertGreaterThan(short, none + Space.m, "the line and its gap")
        XCTAssertEqual(exact - none, Size.reportFold + Space.m, accuracy: 1, "a report of exactly 8 lines has no fold button")
        XCTAssertEqual(long - exact, Space.m + Size.rowTool, accuracy: 1, "a longer one stops at 8 lines, with the button")
    }

    final class LiveRun: ObservableObject {
        @Published var rows = 120
    }

    struct Scrolled: View {
        @ObservedObject var live: LiveRun
        let alive: Bool

        var body: some View {
            AgentRunScroll(alive: alive) {
                VStack(spacing: Space.xxl) {
                    AgentResultCard(chip: StatusChip("running", kind: .warn), meta: "", title: AttributedString("progress")) { EmptyView() }
                    AgentStepsCard(line: "steps", isOpen: .constant(true)) {
                        LazyVStack(spacing: 0) {
                            ForEach(0..<live.rows, id: \.self) { i in
                                if i % 3 == 0 {
                                    ToolNarration(String(repeating: "narration \(i) ", count: 4 + i % 40))
                                } else {
                                    ToolCallRow(symbol: Symbol.terminal, tool: "Bash", command: "step \(i)", isOpen: .constant(false))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func scroll(_ live: LiveRun, alive: Bool) throws -> (window: NSWindow, scroll: NSScrollView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: Scrolled(live: live, alive: alive))
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        addTeardownBlock { @MainActor in window.orderOut(nil) }
        spin(0.5)
        func scrollView(in view: NSView) -> NSScrollView? {
            (view as? NSScrollView) ?? view.subviews.lazy.compactMap(scrollView).first
        }
        return (window, try XCTUnwrap(scrollView(in: window.contentView!)))
    }

    private func gapToBottom(_ scroll: NSScrollView) -> CGFloat {
        (scroll.documentView?.frame.height ?? 0) - scroll.documentVisibleRect.maxY
    }

    func testAFinishedRunOpensOnItsResult() throws {
        let (_, scroll) = try scroll(LiveRun(), alive: false)
        XCTAssertEqual(scroll.documentVisibleRect.minY, 0, accuracy: 1)
    }

    func testALiveRunOpensOnItsTailAndFollowsIt() throws {
        let live = LiveRun()
        let (_, scroll) = try scroll(live, alive: true)
        XCTAssertLessThanOrEqual(gapToBottom(scroll), Space.xxl)
        for _ in 0..<3 {
            live.rows += 4
            spin()
            XCTAssertLessThanOrEqual(gapToBottom(scroll), Space.xxl, "the tail stays in view as steps arrive")
        }
    }

    func testNewStepsDoNotMoveARunScrolledUp() throws {
        let live = LiveRun()
        let (_, scroll) = try scroll(live, alive: true)
        let up = NSPoint(x: 0, y: scroll.documentVisibleRect.minY - 1500)
        scroll.contentView.scroll(to: up)
        scroll.reflectScrolledClipView(scroll.contentView)
        spin()
        let before = scroll.documentVisibleRect.minY
        XCTAssertGreaterThan(gapToBottom(scroll), Space.xxl)
        for _ in 0..<3 {
            live.rows += 4
            spin()
            XCTAssertEqual(scroll.documentVisibleRect.minY, before, accuracy: 1, "the reader's place holds")
        }
    }
}
