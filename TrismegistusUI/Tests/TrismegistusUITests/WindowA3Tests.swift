import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window in three columns in the a3 skin (#69, design 13 #a3, Endfield-faithful). Writes
/// `TrismegistusUI/.build/snapshots/A3-*.png` for review against `design/ui-draft/13d-*` and `13e-a3-*`, and asserts what
/// matters in the pixels and sizes themselves.
@MainActor
final class WindowA3Tests: XCTestCase {
    struct Shot {
        let rep: NSBitmapImageRep
        let size: CGSize

        private var scale: CGFloat { CGFloat(rep.pixelsWide) / size.width }

        /// The raw components: the rep is tagged Generic RGB over sRGB values, so converting it would shift them.
        func rgb(_ x: CGFloat, _ y: CGFloat) -> [CGFloat] {
            let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))
            return [c?.redComponent ?? -1, c?.greenComponent ?? -1, c?.blueComponent ?? -1]
        }

        func isColor(_ x: CGFloat, _ y: CGFloat, _ color: Color, tolerance: CGFloat = 0.03) -> Bool {
            let want = NSColor(color).usingColorSpace(.sRGB)!
            return zip(rgb(x, y), [want.redComponent, want.greenComponent, want.blueComponent]).allSatisfy { abs($0 - $1) <= tolerance }
        }

        /// The first y in `ys` where the pixel at `x` is `color`.
        func first(_ color: Color, x: CGFloat, ys: StrideTo<CGFloat>) -> CGFloat? { ys.first { isColor(x, $0, color, tolerance: 0.08) } }

        /// Some pixel in the box is `color`.
        func contains(_ color: Color, in box: CGRect, tolerance: CGFloat = 0.06) -> Bool {
            stride(from: box.minX, to: box.maxX, by: 0.5).contains { x in
                stride(from: box.minY, to: box.maxY, by: 0.5).contains { y in isColor(x, y, color, tolerance: tolerance) }
            }
        }

        /// How light the pixel is (its red component; the window's greys are neutral).
        func light(_ x: CGFloat, _ y: CGFloat) -> CGFloat { rgb(x, y)[0] }
    }

    private func save(_ rep: NSBitmapImageRep, _ name: String) throws {
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("A3-\(name).png"))
    }

    /// In a real window: `List`, `Menu`, scroll views and text fields draw only there.
    private func shot<V: View>(_ name: String, width: CGFloat, height: CGFloat, ground: Color = Ink.surface.window, @ViewBuilder _ content: () -> V) throws -> Shot {
        let root = content().frame(width: width, height: height, alignment: .topLeading).background(ground).environment(\.colorScheme, .light)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.colorSpace = .sRGB  // or saturated colours come back in the display's gamut
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let view = try XCTUnwrap(window.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        try save(rep, name)
        return Shot(rep: rep, size: view.bounds.size)
    }

    /// Through `ImageRenderer` at 2x, for what has no native control: `cacheDisplay` flips a shadow's y.
    private func flat<V: View>(_ name: String, width: CGFloat, height: CGFloat, ground: Color = Ink.surface.window, @ViewBuilder _ content: () -> V) throws -> Shot {
        let renderer = ImageRenderer(content: content().frame(width: width, height: height, alignment: .topLeading).background(ground).environment(\.colorScheme, .light))
        renderer.scale = 2
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage, "\(name) did not render"))
        try save(rep, name)
        return Shot(rep: rep, size: CGSize(width: width, height: height))
    }

    private func fitting(_ view: some View) -> CGSize { NSHostingView(rootView: view).fittingSize }

    // MARK: The design's content

    static let kinds = [
        KindChip(id: "app", title: "App", symbol: Symbol.kindApp, count: 10, mark: .approval),
        KindChip(id: "telegram", title: "Telegram", symbol: Symbol.kindTelegram, count: 4),
        KindChip(id: "terminal", title: "Terminal", symbol: Symbol.kindTerminal, count: 9),
        KindChip(id: "oneshot", title: "One-shots", symbol: Symbol.kindOneShot, count: 2),
        KindChip(id: "cron", title: "Cron", symbol: Symbol.clock, count: 6),
        KindChip(id: "all", title: "All", symbol: Symbol.kindAll, count: 31),
    ]
    static let badges: [WindowSection: PanelBadge] = [.chat: .mark(.approval), .github: .count(11), .jobs: .mark(.failed)]
    static let linked = DeviceStatus(name: "macbook", state: .linked, detail: "hermes.lab.x-muramasa.dev")

    struct Panel: View {
        var section = WindowSection.chat
        var chatsOpen = true

        var body: some View {
            SectionPanel(section: .constant(section), badges: WindowA3Tests.badges, kinds: WindowA3Tests.kinds, kind: "app", onKind: { _ in },
                         chatsOpen: .constant(chatsOpen), device: WindowA3Tests.linked, version: "v0.9", onToggle: {}) {
                Button("Settings…") {}
                Button("Unpair…") {}
            }
        }
    }

    /// Where the panel's rows start, with the panel 8 pt in: its padding, the top row, the label line and their gaps.
    static let firstRow = Space.s + Space.s + Size.rowCompact + Space.s + Size.sectionPanel.label + Space.s
    static let rowPitch = Size.sectionPanel.row + Space.xxs

    /// A row's top in the open tree: Chats, the six kinds (then the group's 8 pt), then the other sections.
    static func rowTop(section: WindowSection?, kind: Int? = nil) -> CGFloat {
        if let kind { return firstRow + rowPitch * CGFloat(1 + kind) }
        guard let section, section != .chat else { return firstRow }
        let others = WindowSection.allCases.filter { $0 != .chat }
        return firstRow + rowPitch * CGFloat(1 + kinds.count) + Space.s + rowPitch * CGFloat(others.firstIndex(of: section)!)
    }

    /// A card in its cell at the list column's card width (520 less the list's 8 pt margins), on the list's ground.
    private static func card(_ row: SessionRowView, selected: Bool = false, hover: Bool = false) -> some View {
        row.sidebarCardCell(isSelected: selected).environment(\.rowHovered, hover)
            .frame(width: 504).padding(.horizontal, Space.s)
            .environment(\.onSidebar, true).environment(\.hairlineControls, true)
    }

    /// `#a3-states`: one card per state, top to bottom.
    static var states: some View {
        VStack(spacing: 0) {
            card(SessionRowView(name: "The briefing project", source: .trismegistus, activity: "3 h", preview: "Outline v2: 6 sections, sources linked", index: 1))
            card(SessionRowView(name: "Mage-sys", source: .trismegistus, activity: "yesterday", preview: "Migration plan: 3 tables, no downtime", index: 2), hover: true)
            card(SessionRowView(name: "Swift app", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running",
                                isSelected: true, isPinned: true, runElapsed: "00:38", index: 3), selected: true)
            card(SessionRowView(name: "Swift app — second run", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running", runElapsed: "04:14", index: 4))
            card(SessionRowView(name: "Android app", source: .trismegistus, activity: "2 h", preview: "Wants to run ./gradlew assembleRelease", isPinned: true, needsApproval: true, index: 5))
            card(SessionRowView(name: "Workflow refiner", source: .trismegistus, activity: "2 d", preview: "Step 4 timed out after 120 s", isPinned: true, finished: .failed, index: 6))
            card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "1 h", preview: "Build passes; preview deployed for review", finished: .done, index: 7))
            card(SessionRowView(name: "Trismegistus", source: .trismegistus, activity: "1 h", preview: "Relay handshake passes on macbook, pixel and ipad", isPinned: true, index: 8))
            card(SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", preview: "07:00 digest: 12 items, 3 flagged for you", isReadOnly: true, index: 9))
            card(SessionRowView(name: "xMuramasa/homelab#1: Add the Trismegistus relay", source: .trismegistus, activity: "1 h",
                                preview: "Relay config drafted, PR waiting for your review", tags: ["homelab", "relay", "mac"], index: 10))
        }
    }

    /// A list column as the sections put it together: the header, the filter, whatever the section adds, the list.
    struct ListColumn<Extra: View, Rows: View>: View {
        let title: String
        var plus: Bool? = nil
        @ViewBuilder let extra: () -> Extra
        @ViewBuilder let rows: () -> Rows

        var body: some View {
            VStack(spacing: Space.s) {
                ListHeader(title: title) { IconCell(symbol: Symbol.ellipsis) } trailing: {
                    if let plus { PlusButton("New conversation", isPrimary: plus) {} } else {
                        EndfieldButton("Refresh", symbol: Symbol.retry, kind: .quiet, iconOnly: true) {}
                    }
                }
                EndfieldTextField("Filter", text: .constant(""), hint: "⌘K").padding(.horizontal, Space.l)
                extra().padding(.horizontal, Space.l)
                List { rows() }.sidebarList()
            }
        }
    }

    /// Chat's list with the design's content, as `ConversationSidebar` puts it together.
    struct ChatList: View {
        @State private var selection: String? = "swift"

        private func row(_ id: String, _ index: Int, _ build: (Bool, Int) -> SessionRowView) -> some View {
            build(selection == id, index).sidebarCardCell(isSelected: selection == id).tag(id).sidebarRow()
        }

        var body: some View {
            VStack(spacing: Space.s) {
                ListHeader(title: "App // 10") { IconCell(symbol: Symbol.ellipsis) } trailing: { PlusButton("New conversation", isPrimary: false) {} }
                EndfieldTextField("Filter", text: .constant(""), hint: "⌘K").padding(.horizontal, Space.l).padding(.bottom, Space.xs)
                List(selection: $selection) {
                    SectionHead(title: "Pinned", count: 3).padding(.top, Space.s).padding(.bottom, Space.xs).sidebarRow()
                    row("swift", 1) { SessionRowView(name: "Swift app", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running", isSelected: $0, isPinned: true, runElapsed: "00:38", index: $1) }
                    row("android", 2) { SessionRowView(name: "Android app", source: .trismegistus, activity: "2 h", preview: "Wants to run ./gradlew assembleRelease", isSelected: $0, isPinned: true, needsApproval: true, index: $1) }
                    row("refiner", 3) { SessionRowView(name: "Workflow refiner", source: .trismegistus, activity: "2 d", preview: "Step 4 timed out after 120 s", isSelected: $0, isPinned: true, finished: .failed, index: $1) }
                    SectionHead(title: "Conversations", count: 4).padding(.top, Space.s).padding(.bottom, Space.xs).sidebarRow()
                    row("compare", 4) { SessionRowView(name: "Compare Open Design vs Penpot", source: .trismegistus, activity: "5 min", preview: "Penpot exports SVG per board; Open Design keeps HTML", isSelected: $0, index: $1) }
                    row("xmur", 5) { SessionRowView(name: "xMuramasa/homelab#1: Add the Trismegistus relay", source: .trismegistus, activity: "1 h", preview: "Relay config drafted, PR waiting for your review", isSelected: $0, tags: ["homelab", "relay", "mac"], index: $1) }
                    row("home", 6) { SessionRowView(name: "Homepage project", source: .trismegistus, activity: "1 h", preview: "Build passes; preview deployed for review", isSelected: $0, finished: .done, index: $1) }
                    row("digest", 7) { SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", preview: "07:00 digest: 12 items, 3 flagged for you", isSelected: $0, isReadOnly: true, index: $1) }
                }
                .sidebarList()
            }
        }
    }

    static var detailHeader: some View {
        DetailHeader {
            SourceAvatar(.trismegistus, size: Size.avatar.header)
        } title: {
            Text("Swift app")
        } subtitle: {
            Text(verbatim: "Trismegistus · run_7f3a2c · seq 214 · 38 ms · started 13:52")
        } trailing: {
            Text(verbatim: "350K / 1M · 35%").typeRole(.caption).monospacedDigit().foregroundStyle(Ink.text.secondary)
            WindowTools(section: .chat, terminalOpen: false) {}
            IconCell(symbol: Symbol.ellipsis)
        }
    }

    static var composer: some View {
        ComposerBlock(floating: true) {
            RunLine("Run active", isActive: true, clock: "00:38", hints: [(key: "⌘↩", action: "steer"), (key: "⌘.", action: "stop")])
        } input: {
            HStack(alignment: .bottom, spacing: Space.s) {
                Composer("Steer this run", text: .constant(""), maxLines: 10, chosenHeight: .constant(0), maxHeight: 200)
                EndfieldButton("Steer", symbol: Symbol.steer, kind: .primary) {}
            }
        }
    }

    /// The chat as the window draws it (#68's look, out of #69's scope).
    static var chat: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            Text(verbatim: "You // 13:42").typeRole(.label).foregroundStyle(Ink.text.secondary)
            MarkdownView([MarkdownPart<Int>.prose(MarkdownText.styled("The cua-driver daemon is still running on your Mac. `cua-driver stop` ends it."))]) { _ in EmptyView() }
            WorkLine(detail: "00:38 · 2 tools") { CommandChip(commands: 4, duration: "6.1 s", isOpen: .constant(false)) }
        }
        .frame(maxWidth: Size.chatColumn)
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The whole window with `section` current, as `MainWindow` puts it together.
    struct Window: View {
        var section = WindowSection.chat
        var check = false
        @State private var listWidth = Double(Size.listColumn.default)

        var body: some View {
            WindowColumns(isPanelShown: .constant(true), listWidth: $listWidth) {
                Panel(section: section)
            } list: {
                WindowA3Tests.list(section, check: check)
            } detail: {
                if section == .chat {
                    VStack(spacing: 0) {
                        WindowA3Tests.detailHeader
                        WindowA3Tests.chat
                        WindowA3Tests.composer
                    }
                } else {
                    WindowA3Tests.detail(section, check: check).environment(\.hairlineControls, true)
                }
            }
            .background(EndfieldBackdrop())
            .endfieldPaper()
        }
    }

    @ViewBuilder static func list(_ section: WindowSection, check: Bool) -> some View {
        switch section {
        case .chat: ChatList()
        case .github:
            ListColumn(title: check ? "Needs check // 11" : "GitHub // 14 open") {
                Segmented {
                    SegmentTab(title: "Board", symbol: "rectangle.split.3x1", isOn: !check) {}
                    SegmentTab(title: "Needs check", symbol: "eye", count: 11, isOn: check) {}
                }
            } rows: {
                SectionHead(title: check ? "trismegistus-mac" : "In progress", count: check ? 11 : 1).sidebarRow()
                SidebarRow(title: "Window: the a3 skin for the three-column window", meta: "trismegistus-mac#69 · In progress", isSelected: true).sidebarRow()
                SidebarRow(title: "Sections in the three-column layout", meta: "trismegistus-mac#68 · Needs check", isSelected: false).sidebarRow()
                SectionHead(title: "Done", count: 54, folded: true).sidebarRow()
            }
        case .agents:
            ListColumn(title: "Agents // 0 running") { EmptyView() } rows: {
                SectionHead(title: "Finished", count: 6).sidebarRow()
                SidebarRow(title: "trismegistus-mac#68", meta: "run_68 · opus · 34 min", isSelected: true) { _ in StatusChip("success", kind: .ok) }.sidebarRow()
                SidebarRow(title: "trismegistus-mac#67", meta: "run_67 · opus · 21 min", isSelected: false) { _ in StatusChip("success", kind: .ok) }.sidebarRow()
            }
        case .jobs:
            ListColumn(title: "Jobs // 5") { EmptyView() } rows: {
                SectionHead(title: "Scheduled", count: 5).sidebarRow()
                SidebarRow(title: "Morning news digest", meta: "daily 07:00 · next 9 h · ok 15 h", isSelected: true) { _ in StatusChip("ok", kind: .ok) }.sidebarRow()
                SidebarRow(title: "Homelab backup check", meta: "daily 03:00 · next 13 h · failed 10 h", isSelected: false) { _ in StatusChip("failed", kind: .err) }.sidebarRow()
            }
        case .commands:
            ListColumn(title: "Commands // 9") { EmptyView() } rows: {
                SectionHead(title: "By conversation", count: 2).sidebarRow()
                SidebarRow(title: "All conversations", meta: "9 calls", isSelected: true).sidebarRow()
                SidebarRow(title: "Trismegistus window", meta: "6 calls", isSelected: false).sidebarRow()
            }
        }
    }

    static func header(_ title: String, _ subtitle: String, @ViewBuilder actions: () -> some View) -> some View {
        DetailHeader {
            Text(verbatim: title)
        } subtitle: {
            Text(verbatim: subtitle)
        } trailing: {
            actions()
            WindowTools(section: .github, terminalOpen: false) {}
        }
    }

    @ViewBuilder static func detail(_ section: WindowSection, check: Bool) -> some View {
        VStack(spacing: 0) {
            switch section {
            case .chat: EmptyView()
            case .github:
                header("Window: the a3 skin for the three-column window", "xMuramasa/trismegistus-mac#69 · open · 1 h") {
                    TaskReading("0/7")
                    EndfieldButton("Start conversation", symbol: "bubble.left.and.text.bubble.right", kind: .secondary) {}
                    EndfieldButton("Dispatch", symbol: "play.fill", kind: check ? .secondary : .primary) {}
                }
                ReadoutRow {
                    ReadoutCell("Status") { Text(verbatim: check ? "Needs check" : "In progress").typeRole(.callout) }
                    ReadoutCell("Tags") { ReadoutTags(["ui", "window"], shown: 2) }
                    ReadoutCell("Agent") { ReadoutTag("none") }
                } trailing: {
                    EndfieldButton("Close issue", symbol: "checkmark.circle") {}
                }
                VStack(spacing: Space.l) {
                    if check {
                        CheckPanel(lines: ["The panel is translucent grey with the cut corner", "The selected card is white with a yellow frame",
                                           "Tags are 18 pt light chips"], source: "from Hermes · 10 Nov 11:26", canAct: true, busy: false,
                                   note: .constant(""), ticked: ["The panel is translucent grey with the cut corner"], tick: { _ in },
                                   looksGood: {}, notRight: {})
                    }
                    Text("Martin, 2026-11-10: \"i like a3 lets keep developing that one\".").typeRole(.body)
                        .padding(Space.l).frame(maxWidth: .infinity, alignment: .leading)
                        .rounded(Radius.control, fill: Ink.surface.sectionCard, edge: Ink.line.rule)
                }
                .frame(maxWidth: Size.issueColumn).padding(Space.l)
            case .agents:
                header("trismegistus-mac#68", "success · delegate · opus · finished 11:20 · 179 turns · 34 min") {
                    EndfieldButton("Open issue #68", symbol: "arrow.up.right") {}
                }
                VStack(spacing: Space.l) {
                    AgentResultCard(chip: StatusChip("success", kind: .ok), meta: "opus · 34 min", title: AttributedString("Three columns in the B2 skin")) {
                        Text("Built the panel, the list and the detail; the gates pass.").typeRole(.body)
                    }
                    AgentStepsCard(line: "9 steps", isOpen: .constant(true)) {
                        ToolRowView(tool: "Bash", summary: "scripts/mac-test.sh", duration: "48 s", isExpanded: .constant(false))
                    }
                }
                .frame(maxWidth: Size.runColumn).padding(Space.l)
            case .jobs:
                header("Morning news digest", "daily 07:00 · next 9 h") {
                    JobActions(isPaused: false, isBusy: false, onPause: {}, onRun: {}, onEdit: {})
                }
                VStack(spacing: Space.l) {
                    JobReadout(cadence: "daily 07:00", cron: "0 7 * * *", nextRuns: ["11 Nov 07:00", "12 Nov 07:00", "13 Nov 07:00"],
                               noRuns: "", last: .init(failed: false, time: "10 Nov 07:00", ago: "15 h ago"))
                    JobPromptPanel { Text("Read the feeds and write the digest.").typeRole(.body) }
                }
                .frame(maxWidth: Size.jobColumn).padding(Space.l)
            case .commands:
                header("All conversations", "9 calls · 1 failed") {
                    FilterChip(title: "One line", symbol: "text.justify", isOn: true) {}
                    FilterChip(title: "Failed", symbol: "exclamationmark.triangle", isOn: false) {}
                }
                VStack(alignment: .leading, spacing: Space.m) {
                    CommandGroupHead(title: "Trismegistus window", calls: 6, failed: 1, isOpen: true, onOpen: {}, onFold: {})
                    VStack(spacing: Space.xs) {
                        TerminalEntryView(time: "13:42:10", tool: "terminal", command: "swift build", exitCode: 0, duration: 6.1, oneLine: true)
                        TerminalEntryView(time: "13:42:18", tool: "terminal", command: "cua-driver status", exitCode: 127, duration: 0.1, oneLine: true)
                    }
                }
                .padding(Space.l)
            }
            Spacer(minLength: 0)
        }
    }

    /// The detail's left edge in a 1560 pt window.
    static let detailX = Size.sectionPanel.width + 2 * Space.s + Size.listColumn.default

    // MARK: Window

    func testTheWindowInThreeColumns() throws {
        for (width, list) in [(CGFloat(1560), Size.listColumn.default), (1180, Size.listColumn.min)] {
            let shot = try shot("Window-\(Int(width))", width: width, height: 1122) { Window() }
            let panelEdge = Size.sectionPanel.width + 2 * Space.s
            // The panel: translucent dark-panel grey, 8 pt in, the top-right corner cut, no shadow.
            XCTAssertTrue(shot.rgb(150, 900).allSatisfy { $0 < 0.4 }, "\(width): the panel's grey \(shot.rgb(150, 900))")
            XCTAssertGreaterThan(shot.light(4, 500), 0.85, "\(width): 8 pt of window left of the panel")
            XCTAssertGreaterThan(shot.light(Space.s + 300 - 3, Space.s + 3), 0.8, "\(width): the cut corner")
            XCTAssertLessThan(shot.light(Space.s + 300 - 30, Space.s + 3), 0.4, "\(width): the panel left of the cut")
            XCTAssertGreaterThan(shot.light(panelEdge - 2, 1100), 0.85, "\(width): no shadow right of the panel")
            // The list column's rule: the list is 520 wide, 380 at 1180 pt; its ground sunken at 42 %.
            let rule = panelEdge + list - 0.5
            XCTAssertTrue(shot.isColor(rule, 1000, Ink.line.rule, tolerance: 0.05), "\(width): the list's rule at x = \(rule)")
            XCTAssertTrue(shot.isColor(panelEdge + list / 2, 1100, Ink.surface.sidebarSolid, tolerance: 0.02), "\(width): the list's ground \(shot.rgb(panelEdge + list / 2, 1100))")
            // The frosted detail header, the 2 pt rule: tick, gap, yellow, grey.
            XCTAssertTrue(shot.isColor(rule + 300, 3, Ink.surface.raised, tolerance: 0.03), "\(width): the frosted header")
            XCTAssertTrue(shot.isColor(rule + 4, Size.sidebarHead + 1, Ink.surface.darkPanel, tolerance: 0.05), "\(width): the rule's tick")
            XCTAssertTrue(shot.isColor(rule + 30, Size.sidebarHead + 1, Ink.selection, tolerance: 0.05), "\(width): the rule's yellow")
            XCTAssertTrue(shot.isColor(rule + 300, Size.sidebarHead + 1, Ink.line.rule, tolerance: 0.05), "\(width): the rule's grey")
            // The composer floats as in #68.
            XCTAssertFalse(shot.isColor(rule + 200, 1122 - 3, Ink.surface.raised), "\(width): the composer stops 8 pt above the bottom")
            XCTAssertTrue(shot.isColor(rule + 200, 1122 - 20, Ink.surface.raised), "\(width): the composer block")
        }
    }

    func testTheListGivesWayToTheDetail() {
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(520, available: 1560 - 316), 520)
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(520, available: 1180 - 316), 380)
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(900, available: 2000), Size.listColumn.max)
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(100, available: 600), Size.listColumn.min)
    }

    /// The popover keeps its white rows and yellow bar; the shared tag shows on their corner (#69).
    func testRowStatesInThePopover() throws {
        let rows = VStack(spacing: 1) {
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h")
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", isSelected: true)
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", runElapsed: "00:38")
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", needsApproval: true)
        }
        let shot = try flat("Row-popover", width: 380, height: 53 * 4, ground: Ink.line.rule) { rows }
        XCTAssertTrue(shot.isColor(200, 26, Ink.surface.raised), "white, as before")
        XCTAssertTrue(shot.isColor(1, 53 + 26, Ink.selection), "the yellow bar, as before")
        XCTAssertTrue(shot.contains(Ink.marker, in: CGRect(x: 280, y: 53 * 3, width: 100, height: 18), tolerance: 0.1), "the approval tag on the corner")
    }

    func testSpokenRow() {
        let row = SessionRowView(name: "Android app", source: .trismegistus, activity: "2 h", isReadOnly: true, isPinned: true, needsApproval: true, index: 2)
        XCTAssertEqual(row.spoken, "Android app, approval waiting, 2 h, read-only, pinned")
        XCTAssertEqual(SessionRowView(name: "Swift app", source: .trismegistus, activity: "now", runElapsed: "00:38").spoken, "Swift app, running, now")
        XCTAssertEqual(KindChip(id: "a", title: "App", symbol: "", count: 1, mark: .approval).spoken, "App, 1 conversation, approval waiting")
    }

    /// Nothing the window draws outside code blocks and the terminal asks for the mono family (#68), and the check sees
    /// mono where it is.
    func testTheWindowUsesNoMonoOutsideCode() throws {
        TypeSpec.drawn = []
        _ = try shot("Window-mono-check", width: 1560, height: 1122) { Window() }
        XCTAssertTrue(TypeSpec.drawn.contains(.ui))
        XCTAssertFalse(TypeSpec.drawn.contains(.mono), "a mono role in the window")
        TypeSpec.drawn = []
        _ = try shot("Window-mono-check", width: 600, height: 120) { CodeBlockView(language: "sh", code: "cua-driver stop") }
        XCTAssertTrue(TypeSpec.drawn.contains(.mono), "the check itself sees mono")
    }

    /// No window text, in any section, uses a weight above 600 (#69); the check sees a heavier one where it is.
    func testNoWeightAbove600() throws {
        TypeSpec.drawnWeights = []
        _ = try shot("Window-weight-check", width: 1560, height: 1122) { Window() }
        for section in WindowSection.allCases where section != .chat {
            _ = try shot("Window-weight-check", width: 1560, height: 1122) { Window(section: section) }
        }
        _ = try shot("Window-weight-check", width: 1560, height: 1122) { Window(section: .github, check: true) }
        XCTAssertFalse(TypeSpec.drawnWeights.isEmpty)
        XCTAssertLessThanOrEqual(TypeSpec.drawnWeights.max() ?? 0, 600, "weights drawn: \(TypeSpec.drawnWeights.sorted())")
        TypeSpec.drawnWeights = []
        _ = try shot("Window-weight-check", width: 300, height: 40) { TitleRule("Settings") }
        XCTAssertEqual(TypeSpec.drawnWeights.max(), 700, "the check itself sees 700")
    }

    // MARK: Section panel

    /// The lit row (a 3 pt yellow bar at its left edge) on the deepest current row you can see; one per panel.
    func testSectionPanel() throws {
        let barX = Space.s + Space.s + 1.5
        for section in WindowSection.allCases {
            let shot = try shot("Panel-\(section.rawValue)", width: 316, height: 900) { Panel(section: section).padding(Space.s) }
            let top = section == .chat ? Self.rowTop(section: nil, kind: 0) : Self.rowTop(section: section)
            let bar = try XCTUnwrap(shot.first(Ink.selection, x: barX, ys: stride(from: CGFloat(60), to: 800, by: 0.5)), "\(section): no yellow bar")
            XCTAssertEqual(bar, top + Space.s, accuracy: 1.5, "\(section): the bar's row")
            XCTAssertTrue(shot.isColor(barX, top + Space.s + 18, Ink.selection, tolerance: 0.08), "\(section): a 20 pt bar")
            XCTAssertNil(shot.first(Ink.selection, x: barX, ys: stride(from: top + Size.sectionPanel.row, to: 800, by: 0.5)), "\(section): one bar")
            // The lit row is lighter than an unlit one.
            let unlit = section == .github ? Self.rowTop(section: .agents) : Self.rowTop(section: .github)
            XCTAssertGreaterThan(shot.light(150, top + 18), shot.light(150, unlit + 18) + 0.02, "\(section): the lit row")
        }
        // The kinds are children: App's icon starts one icon column further in than Chats'; the guide line runs under
        // Chats' icon.
        let open = try shot("Panel-tree", width: 316, height: 900) { Panel(section: .github).padding(Space.s) }
        func icon(_ y: CGFloat) -> CGFloat? { stride(from: CGFloat(Space.s), to: 120, by: 0.5).first { open.light($0, y) > 0.75 } }
        let chats = try XCTUnwrap(icon(Self.firstRow + 18)), app = try XCTUnwrap(icon(Self.rowTop(section: nil, kind: 0) + 18))
        XCTAssertEqual(app - chats, SectionPanel<EmptyView>.childIndent, accuracy: 3, "the kinds are indented")
        let gap = Self.rowTop(section: nil, kind: 1) - 1
        XCTAssertGreaterThan(open.light(Space.s + Space.s + Space.m + Icon.panel / 2 + 0.5, gap), open.light(100, gap) + 0.02, "the guide line")
        // Folded: no kinds, Chats is lit (in Chat) and GitHub follows it; the cut corner.
        let folded = try shot("Panel-folded", width: 316, height: 900) { Panel(chatsOpen: false).padding(Space.s) }
        XCTAssertEqual(try XCTUnwrap(folded.first(Ink.selection, x: barX, ys: stride(from: CGFloat(60), to: 800, by: 0.5))), Self.firstRow + Space.s,
                       accuracy: 1.5, "folded: Chats is lit")
        XCTAssertNil(folded.first(Ink.selection, x: barX, ys: stride(from: Self.firstRow + Size.sectionPanel.row, to: 800, by: 0.5)), "folded: one bar")
        XCTAssertGreaterThan(folded.light(Space.s + 300 - 3, Space.s + 3), 0.8, "the cut corner")
        XCTAssertLessThan(folded.light(Space.s + 300 - 30, Space.s + 3), 0.4)
        XCTAssertGreaterThan(folded.light(Space.s + 0.5, Space.s + 0.5), 0.8, "an m corner")
    }

    func testDeviceRowInItsThreeStates() throws {
        let states: [(String, DeviceStatus, Color?)] = [
            ("linked", Self.linked, Ink.status.online),
            ("connecting", DeviceStatus(name: "macbook", state: .reconnecting, detail: "hermes.lab.x-muramasa.dev"), Ink.selection),
            ("offline", DeviceStatus(name: "macbook", state: .offline, detail: "not connected"), nil),
        ]
        for (name, device, dot) in states {
            let shot = try flat("Device-\(name)", width: 300, height: 56, ground: Ink.surface.darkPanel) {
                DeviceRow(device: device) { Button("Settings…") {} }
            }
            let box = CGRect(x: 44, y: 24, width: 24, height: 28)
            if let dot {
                XCTAssertTrue(shot.contains(dot, in: box), "\(name): the dot")
            } else {
                XCTAssertFalse(shot.contains(Ink.status.online, in: box) || shot.contains(Ink.selection, in: box), "offline: a hollow dot")
            }
            XCTAssertGreaterThan(shot.light(Space.s + 2, 30), shot.light(150, 50) + 0.03, "\(name): the 28 pt avatar")
        }
        XCTAssertEqual(Self.linked.line, "linked · hermes.lab.x-muramasa.dev")
        XCTAssertEqual(DeviceStatus(name: "m", state: .offline, detail: "token refused").line, "offline · token refused")
    }

    // MARK: List column

    func testListHeader() throws {
        let shot = try flat("ListHeader", width: 520, height: 104, ground: Ink.surface.sidebarSolid) {
            VStack(spacing: 0) {
                ListHeader(title: "App // 10") { IconCell(symbol: Symbol.ellipsis) } trailing: { PlusButton("New conversation") {} }
                ListHeader(title: "App // 10") { IconCell(symbol: Symbol.ellipsis) } trailing: { PlusButton("New conversation", isPrimary: false) {} }
            }
            .environment(\.onSidebar, true)
        }
        XCTAssertTrue(shot.isColor(520 - Space.l - 4, 26, Ink.selection), "the yellow +")
        XCTAssertTrue(shot.isColor(520 - Space.l - 4, 52 + 26, Ink.surface.raised, tolerance: 0.03), "the + steps down to white during a run")
        XCTAssertTrue(shot.isColor(520 - Space.l - 0.5, 52 + 26, Ink.line.rule, tolerance: 0.05), "a thin rule edge")
        XCTAssertTrue(shot.isColor(Space.l + 4, 26, Ink.surface.raised, tolerance: 0.03), "the … button")
        XCTAssertTrue(shot.contains(Ink.line.contour, in: CGRect(x: 520 - Size.hatch.inset - Size.hatch.headWidth, y: Space.xxl, width: Size.hatch.headWidth, height: 4)), "the hatch")
        XCTAssertEqual(fitting(PlusButton("New") {}), CGSize(width: Size.control, height: Size.control))
        // The title is centred; the count is the one large numeral.
        let dark = stride(from: CGFloat(60), to: 420, by: 0.5).filter { x in stride(from: CGFloat(8), to: 46, by: 1).contains { shot.light(x, $0) < 0.6 } }
        XCTAssertEqual(((dark.first ?? 0) + (dark.last ?? 0)) / 2, 260, accuracy: 8, "the title's centre")
        let inked = stride(from: CGFloat(4), to: 50, by: 0.5).filter { y in stride(from: CGFloat(240), to: 320, by: 1).contains { shot.isColor($0, y, Ink.text.primary, tolerance: 0.2) } }
        XCTAssertGreaterThan((inked.last ?? 0) - (inked.first ?? 0), 16, "a 28 pt count")
        XCTAssertEqual(SidebarTitle.parts("GitHub // 14 open").count, "14")
        XCTAssertEqual(SidebarTitle.parts("GitHub // 14 open").suffix, "open")
        XCTAssertEqual(SidebarTitle.parts("App // 10").label, "App")
        XCTAssertNil(SidebarTitle.parts("All conversations").count)
    }

    func testCardsInEveryState() throws {
        let heights: [CGFloat] = [50, 50, 62, 50, 50, 50, 50, 50, 50, 50]
        let shot = try flat("Cards", width: 520, height: heights.reduce(0, +), ground: Ink.surface.sidebarSolid) { Self.states }
        let tops = heights.indices.map { heights[..<$0].reduce(0, +) + (heights[$0] > 50 ? Space.s : Space.xxs) }
        // Idle: white stepping down, a contour hairline, control corners, the 26 pt dark-panel avatar after the index.
        XCTAssertGreaterThan(shot.light(400, tops[0] + 3), shot.light(400, tops[0] + 43) + 0.008, "lit from above")
        XCTAssertTrue(shot.isColor(Space.s + 0.25, tops[0] + 0.25, Ink.surface.sidebarSolid, tolerance: 0.02), "a control corner")
        XCTAssertLessThan(shot.light(Space.s + 0.25, tops[0] + 23), 0.92, "the hairline")
        XCTAssertTrue(shot.isColor(Space.s + Space.xs + Size.cardIndex + Space.s + 2, tops[0] + 14, Ink.avatar.app), "the 26 pt avatar")
        XCTAssertTrue(shot.contains(Ink.text.muted, in: CGRect(x: Space.s + Space.xs, y: tops[0] + 16, width: Size.cardIndex, height: 14), tolerance: 0.1), "the index")
        // Hovered: white with a contour edge.
        XCTAssertTrue(shot.isColor(400, tops[1] + 23, Ink.surface.raised, tolerance: 0.01), "hover is white")
        XCTAssertTrue(shot.isColor(Space.s + 0.25, tops[1] + 23, Ink.line.contour, tolerance: 0.06), "hover's contour edge")
        // Selected: white, the yellow frame with its glow, grey brackets 6 pt out, the hatch on the top edge.
        let sel = tops[2]
        XCTAssertTrue(shot.isColor(300, sel + 3, Ink.surface.raised, tolerance: 0.01), "the selection is white")
        XCTAssertTrue(shot.isColor(Space.s + 0.75, sel + 23, Ink.selection, tolerance: 0.1), "the yellow frame")
        let glow = shot.rgb(Space.s - 2, sel + 23)
        XCTAssertLessThan(glow[2], glow[0] - 0.03, "the glow outside it \(glow)")
        XCTAssertTrue(shot.isColor(Space.s - Size.bracket + 0.5, sel - Size.bracket + 3, Ink.text.secondary, tolerance: 0.15), "a bracket's arm")
        XCTAssertFalse(shot.isColor(Space.s - Size.bracket + 0.5, sel + 23, Ink.text.secondary, tolerance: 0.15), "brackets, not a frame")
        XCTAssertTrue(shot.contains(Ink.line.contour, in: CGRect(x: Space.s + 504 - Size.hatch.inset - Size.hatch.width, y: sel + 2, width: Size.hatch.width, height: 3)), "the hatch")
        // The tags on the preview line: RUN dark with its yellow, APPROVAL's magenta, FAILED red, DONE green.
        func tagBox(_ i: Int) -> CGRect { CGRect(x: 300, y: tops[i] + 24, width: 212, height: 20) }
        XCTAssertTrue(shot.contains(Ink.surface.darkPanel, in: tagBox(3)), "RUN's dark chip")
        XCTAssertTrue(shot.contains(Ink.selection, in: tagBox(3), tolerance: 0.1), "RUN's yellow")
        XCTAssertTrue(shot.contains(Ink.marker, in: tagBox(4), tolerance: 0.1), "APPROVAL's magenta")
        XCTAssertTrue(shot.contains(Ink.status.error, in: tagBox(5), tolerance: 0.1), "FAILED's red")
        XCTAssertTrue(shot.contains(Ink.status.ok, in: tagBox(6), tolerance: 0.1), "DONE's green")
        XCTAssertEqual(fitting(Self.card(SessionRowView(name: "a", source: .trismegistus, activity: "now"))).height, 50, "a 50 pt pitch")
        XCTAssertEqual(fitting(SessionRowView(name: "a", source: .trismegistus, activity: "now").environment(\.onSidebar, true).frame(width: 504)).height, Size.card)
    }

    func testStateTags() throws {
        let shot = try flat("Tags", width: 300, height: 120, ground: Ink.surface.raised) {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(StickerState.allCases, id: \.self) { state in
                    HStack(spacing: Space.s) {
                        Sticker(state, time: state == .running ? "00:38" : nil)
                        Sticker(state, isBadge: true)
                    }
                }
            }
            .padding(Space.s)
        }
        XCTAssertTrue(shot.isColor(Space.s + 1, Space.s + 9, Ink.marker, tolerance: 0.1), "approval's 2 pt bar")
        XCTAssertTrue(shot.isColor(Space.s + 4, Space.s + 9, Ink.surface.raised, tolerance: 0.03), "a light chip")
        XCTAssertFalse(shot.isColor(Space.s + 0.25, Space.s + 0.25, Ink.marker, tolerance: 0.1), "tag corners")
        let run = Space.s + Size.sticker.height + Space.xs
        XCTAssertTrue(shot.isColor(Space.s + 1, run + 9, Ink.selection, tolerance: 0.1), "RUN's yellow bar")
        XCTAssertTrue(shot.contains(Ink.surface.darkPanel, in: CGRect(x: Space.s + 3, y: run + 2, width: 40, height: 14)), "RUN's dark chip")
        for state in StickerState.allCases {
            XCTAssertEqual(fitting(Sticker(state)).height, Size.sticker.height, "\(state)")
            XCTAssertEqual(fitting(Sticker(state, isBadge: true)), CGSize(width: Size.sticker.badgeCell + Stroke.accent, height: Size.sticker.badge), "\(state)")
        }
        let widths = ["00:11", "00:88", "11:11", "59:00"].map { fitting(Sticker(.running, time: $0)).width }
        XCTAssertEqual(Set(widths).count, 1, "tabular figures: \(widths)")
    }

    func testLabelLine() throws {
        let shot = try flat("LabelLine", width: 520, height: Size.labelLine, ground: Ink.surface.sidebarSolid) {
            SectionHead(title: "Pinned", count: 4).frame(width: 520)
        }
        XCTAssertEqual(fitting(SectionHead(title: "Pinned").frame(width: 300)).height, Size.labelLine)
        XCTAssertTrue(shot.contains(Ink.line.contour, in: CGRect(x: 200, y: 11, width: 200, height: 2), tolerance: 0.03), "the hairline")
        XCTAssertTrue(shot.contains(Ink.text.secondary, in: CGRect(x: Space.l, y: 6, width: 80, height: 12), tolerance: 0.12), "the label")
        XCTAssertFalse(shot.contains(Ink.surface.inverse, in: CGRect(x: 0, y: 0, width: 520, height: Size.labelLine), tolerance: 0.02), "no ink slab")
    }

    // MARK: Detail

    func testDetailHeader() throws {
        let shot = try shot("DetailHeader", width: 900, height: 60) { Self.detailHeader }
        XCTAssertTrue(shot.isColor(450, 3, Ink.surface.raised, tolerance: 0.03), "frosted white")
        XCTAssertTrue(shot.isColor(Space.xxl + 3, 26, Ink.avatar.app), "the 28 pt avatar")
        XCTAssertFalse(shot.isColor(Space.xxl + 3, 26 - 14 + 0.25, Ink.avatar.app), "28 pt, not 32")
        XCTAssertTrue(shot.isColor(4, Size.sidebarHead + 1, Ink.surface.darkPanel, tolerance: 0.05), "the tick")
        XCTAssertTrue(shot.isColor(Size.titleRule.tick + 2, Size.sidebarHead + 1, Ink.line.rule, tolerance: 0.05), "the gap")
        XCTAssertTrue(shot.isColor(Size.titleRule.tick + Space.xs + 20, Size.sidebarHead + 1, Ink.selection, tolerance: 0.05), "the yellow segment")
        XCTAssertTrue(shot.isColor(800, Size.sidebarHead + 1, Ink.line.rule, tolerance: 0.05), "grey to the edge")
        XCTAssertFalse(shot.isColor(800, Size.sidebarHead + 3, Ink.line.rule, tolerance: 0.02), "2 pt")
    }

    // MARK: Sections

    /// Each section's list and detail in the window, its row lit in the panel.
    func testSectionsInTheA3Skin() throws {
        let detail = CGRect(x: Self.detailX + 1, y: Size.sidebarHead + 4, width: 1560 - Self.detailX - 2, height: 600)
        for (name, section, check) in [("github", WindowSection.github, false), ("github-check", .github, true), ("agents", .agents, false),
                                       ("jobs", .jobs, false), ("commands", .commands, false)] {
            let shot = try shot("Section-\(name)", width: 1560, height: 1122) { Window(section: section, check: check) }
            let top = Self.rowTop(section: section)
            XCTAssertEqual(try XCTUnwrap(shot.first(Ink.selection, x: Space.s + Space.s + 1.5, ys: stride(from: CGFloat(60), to: 800, by: 0.5))),
                           top + Space.s, accuracy: 1.5, "\(name): the panel's lit row")
            // Rows are cards; the selected one has the yellow frame.
            let list = CGRect(x: Size.sectionPanel.width + 2 * Space.s, y: 100, width: Size.listColumn.default - 2, height: 400)
            XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: list.minX + Space.s, y: list.minY, width: 2, height: list.height), tolerance: 0.1),
                          "\(name): the selected card's frame")
            XCTAssertFalse(shot.contains(Ink.card.header, in: detail, tolerance: 0.04), "\(name): no orange in the detail")
            switch name {
            case "github":
                XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: list.minX, y: 100, width: list.width / 2, height: 100), tolerance: 0.05),
                              "the segmented control's yellow underline")
            case "github-check":
                // The check panel's yellow 2 pt top line, wider than any button.
                let line = stride(from: Size.sidebarHead + 20, to: 400, by: 0.5).first { y in
                    stride(from: Self.detailX + 40, to: Self.detailX + 400, by: 8).allSatisfy { shot.isColor($0, y, Ink.selection, tolerance: 0.08) }
                }
                XCTAssertNotNil(line, "the check panel's top line")
            case "jobs":
                XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: Self.detailX + 300, y: 8, width: 1560 - Self.detailX - 300, height: 36)), "Run now is the yellow")
            case "commands":
                let edge = CGRect(x: Self.detailX + Space.l + 0.5, y: Size.sidebarHead, width: 2, height: 300)
                XCTAssertTrue(shot.contains(Ink.status.ok, in: edge), "a green edge on exit 0")
                XCTAssertTrue(shot.contains(Ink.status.error, in: edge), "a red edge on a failed call")
            default: break
            }
        }
    }
}
