import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window in three columns, B2 rounded (#68, design 13 #a2), and the B2 parts it reuses (#65). Writes
/// `TrismegistusUI/.build/snapshots/A2-*.png` for review against `design/ui-draft/13c-opendesign-three-column-b2-rounded*.png`
/// and asserts what matters in the pixels and sizes themselves.
@MainActor
final class WindowA2Tests: XCTestCase {
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
        func first(_ color: Color, x: CGFloat, ys: StrideTo<CGFloat>) -> CGFloat? { ys.first { isColor(x, $0, color) } }

        /// Some pixel in the box is `color`.
        func contains(_ color: Color, in box: CGRect) -> Bool {
            stride(from: box.minX, to: box.maxX, by: 0.5).contains { x in
                stride(from: box.minY, to: box.maxY, by: 0.5).contains { y in isColor(x, y, color, tolerance: 0.06) }
            }
        }
    }

    private func save(_ rep: NSBitmapImageRep, _ name: String) throws {
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("A2-\(name).png"))
    }

    /// In a real window: `List`, `Menu` and text fields draw only there.
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
    static let badges: [WindowSection: PanelBadge] = [.chat: .mark(.approval), .github: .count(3), .agents: .count(1), .jobs: .mark(.failed)]
    static let linked = DeviceStatus(name: "macbook", state: .linked, detail: "hermes.lab.x-muramasa.dev")

    struct Panel: View {
        var section = WindowSection.chat
        var chatsOpen = true
        var device = WindowA2Tests.linked

        var body: some View {
            SectionPanel(section: .constant(section), badges: WindowA2Tests.badges, kinds: WindowA2Tests.kinds, kind: "app", onKind: { _ in },
                         chatsOpen: .constant(chatsOpen), device: device, onToggle: {}) {
                Button("Settings…") {}
                Button("Unpair…") {}
            }
        }
    }

    /// A card in its cell at the list column's card width (520 less the list's 8 pt margins).
    private static func card(_ row: SessionRowView, selected: Bool = false, hover: Bool = false) -> some View {
        row.sidebarCardCell(isSelected: selected).environment(\.rowHovered, hover)
            .frame(width: 504).padding(.horizontal, Space.s).environment(\.onSidebar, true)
    }

    /// `#a2-states`: one card per state, top to bottom.
    static var states: some View {
        VStack(spacing: 0) {
            card(SessionRowView(name: "The briefing project", source: .trismegistus, activity: "3 h", preview: "Outline v2: 6 sections, sources linked"))
            card(SessionRowView(name: "Mage-sys", source: .trismegistus, activity: "yesterday", preview: "Migration plan: 3 tables, no downtime"), hover: true)
            card(SessionRowView(name: "Swift app", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running",
                                isSelected: true, isPinned: true, runElapsed: "00:38"), selected: true)
            card(SessionRowView(name: "Swift app — second run", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running", runElapsed: "04:14"))
            card(SessionRowView(name: "Android app", source: .trismegistus, activity: "2 h", preview: "Wants to run ./gradlew assembleRelease", isPinned: true, needsApproval: true))
            card(SessionRowView(name: "Workflow refiner", source: .trismegistus, activity: "2 d", preview: "Step 4 timed out after 120 s", isPinned: true, finished: .failed))
            card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "1 h", preview: "Build passes; preview deployed for review", finished: .done))
            card(SessionRowView(name: "Trismegistus", source: .trismegistus, activity: "1 h", preview: "Relay handshake passes on macbook, pixel and ipad", isPinned: true))
            card(SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", preview: "07:00 digest: 12 items, 3 flagged for you", isReadOnly: true))
            card(SessionRowView(name: "xMuramasa/homelab#1: Add the Trismegistus relay", source: .trismegistus, activity: "1 h",
                                preview: "Relay config drafted, PR waiting for your review", tags: ["homelab", "relay", "mac"]))
        }
    }

    /// The list column with the design's Chat content, as `ConversationSidebar` puts it together.
    struct ListColumn: View {
        @State private var selection: String? = "swift"

        private func row(_ id: String, _ build: (Bool) -> SessionRowView) -> some View {
            build(selection == id).sidebarCardCell(isSelected: selection == id).tag(id).sidebarRow()
        }

        var body: some View {
            VStack(spacing: Space.s) {
                ListHeader(title: "App // 10") { IconCell(symbol: Symbol.ellipsis) } trailing: { PlusButton("New conversation", isPrimary: false) {} }
                EndfieldTextField("Filter", text: .constant(""), hint: "⌘K").padding(.horizontal, Space.l).padding(.bottom, Space.xs)
                List(selection: $selection) {
                    SectionHead(title: "Pinned", count: 3).padding(.vertical, Space.s).sidebarRow()
                    row("swift") { SessionRowView(name: "Swift app", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running", isSelected: $0, isPinned: true, runElapsed: "00:38") }
                    row("android") { SessionRowView(name: "Android app", source: .trismegistus, activity: "2 h", preview: "Wants to run ./gradlew assembleRelease", isSelected: $0, isPinned: true, needsApproval: true) }
                    row("refiner") { SessionRowView(name: "Workflow refiner", source: .trismegistus, activity: "2 d", preview: "Step 4 timed out after 120 s", isSelected: $0, isPinned: true, finished: .failed) }
                    SectionHead(title: "Conversations", count: 4).padding(.vertical, Space.s).sidebarRow()
                    row("compare") { SessionRowView(name: "Compare Open Design vs Penpot", source: .trismegistus, activity: "5 min", preview: "Penpot exports SVG per board; Open Design keeps HTML", isSelected: $0) }
                    row("xmur") { SessionRowView(name: "xMuramasa/homelab#1: Add the Trismegistus relay", source: .trismegistus, activity: "1 h", preview: "Relay config drafted, PR waiting for your review", isSelected: $0, tags: ["homelab", "relay", "mac"]) }
                    row("home") { SessionRowView(name: "Homepage project", source: .trismegistus, activity: "1 h", preview: "Build passes; preview deployed for review", isSelected: $0, finished: .done) }
                    row("digest") { SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", preview: "07:00 digest: 12 items, 3 flagged for you", isSelected: $0, isReadOnly: true) }
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
            Text(verbatim: "Trismegistus · run_7f3a2c · started 13:52")
        } trailing: {
            Text(verbatim: "350K / 1M · 35%").typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary)
            WindowTools(section: .chat, terminalOpen: false) {}
            IconCell(symbol: Symbol.ellipsis)
        }
    }

    static func composer(floating: Bool) -> some View {
        ComposerBlock(floating: floating) {
            RunLine("Run active", isActive: true, clock: "00:38", hints: [(key: "⌘↩", action: "steer"), (key: "⌘.", action: "stop"), (key: "⌘⌥T", action: "terminal")])
        } input: {
            HStack(alignment: .bottom, spacing: Space.s) {
                EndfieldButton("Attach images", symbol: Symbol.attach, kind: .quiet, iconOnly: true) {}
                Composer("Steer this run", text: .constant(""), maxLines: 10, chosenHeight: .constant(0), maxHeight: 200)
                EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger, iconOnly: true) {}
                EndfieldButton("Steer", symbol: Symbol.steer, kind: .primary) {}
            }
        }
    }

    /// The chat as the window draws it: labels, an answer with inline code, the commands chip, the work line.
    static var chat: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: "You // 13:42").typeRole(.label).foregroundStyle(Ink.text.secondary)
                Text("i already ran open, could you use cua-driver on my mac to test the ui?").typeRole(.body)
                    .padding(Space.m).frame(maxWidth: .infinity, alignment: .leading)
                    .rounded(Radius.l, fill: Ink.surface.raised, edge: Ink.line.rule)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(verbatim: "Hermes // 13:49").typeRole(.label).foregroundStyle(Ink.text.secondary)
                MarkdownView([MarkdownPart<Int>.prose(MarkdownText.styled("The cua-driver daemon is still running on your Mac. `cua-driver stop` ends it, see https://example.test/x."))]) { _ in EmptyView() }
                    .padding(.horizontal, Space.m)
            }
            WorkLine(detail: "00:38 · 2 tools") { CommandChip(commands: 4, duration: "6.1 s", isOpen: .constant(false)) }
        }
        .frame(maxWidth: Size.chatColumn)
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    struct Window: View {
        var panel = true
        @State private var listWidth = Double(Size.listColumn.default)

        var body: some View {
            WindowColumns(isPanelShown: .constant(panel), listWidth: $listWidth) {
                Panel()
            } list: {
                ListColumn()
            } detail: {
                VStack(spacing: 0) {
                    WindowA2Tests.detailHeader
                    WindowA2Tests.chat
                    WindowA2Tests.composer(floating: true)
                }
            }
            .endfieldPaper()
        }
    }

    // MARK: Window

    func testTheWindowInThreeColumns() throws {
        for (width, list) in [(CGFloat(1560), Size.listColumn.default), (1180, Size.listColumn.min)] {
            let shot = try shot("Window-\(Int(width))", width: width, height: 1122) { Window() }
            let panelEdge = Size.sectionPanel.width + 2 * Space.s
            // The panel: ink, 8 pt in, its corners rounded (xl), the soft shadow on its right.
            XCTAssertTrue(shot.isColor(150, 900, Ink.surface.panel), "\(width): the panel's ink")
            XCTAssertTrue(shot.isColor(4, 500, Ink.surface.window, tolerance: 0.06), "\(width): 8 pt of window left of the panel")
            XCTAssertFalse(shot.isColor(Space.s + 1, Space.s + 1, Ink.surface.panel), "\(width): a rounded corner")
            XCTAssertLessThan(shot.rgb(panelEdge - 2, 900)[0], shot.rgb(panelEdge + 40, 1100)[0] - 0.02, "\(width): the panel's shadow")
            // The list column's rule: the list is 520 wide, 380 at 1180 pt.
            let rule = panelEdge + list - 0.5
            XCTAssertTrue(shot.isColor(rule, 1000, Ink.line.rule, tolerance: 0.05), "\(width): the list's rule at x = \(rule)")
            XCTAssertWidthOfList(shot, from: panelEdge, list: list, width: width)
            // The detail header is white from the window's top, with the title rule under it.
            XCTAssertTrue(shot.isColor(rule + 300, 3, Ink.surface.raised), "\(width): the white detail header")
            XCTAssertTrue(shot.isColor(rule + 4, Size.sidebarHead + 2, Ink.titleRule[0]), "\(width): the title rule's magenta")
            // The composer floats: window under it, 8 pt from the bottom and the sides.
            XCTAssertFalse(shot.isColor(rule + 200, 1122 - 3, Ink.surface.raised), "\(width): the composer stops 8 pt above the bottom")
            XCTAssertTrue(shot.isColor(rule + 200, 1122 - 20, Ink.surface.raised), "\(width): the composer block")
        }
    }

    private func XCTAssertWidthOfList(_ shot: Shot, from left: CGFloat, list: CGFloat, width: CGFloat) {
        // No rule anywhere else in the list's span.
        let rules = stride(from: left + 2, to: left + list - 2, by: 1).filter { shot.isColor($0, 1000, Ink.line.rule, tolerance: 0.01) }
        XCTAssertTrue(rules.isEmpty, "\(width): a rule inside the list at \(rules)")
    }

    func testTheListGivesWayToTheDetail() {
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(520, available: 1560 - 316), 520)
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(520, available: 1180 - 316), 380)
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(900, available: 2000), Size.listColumn.max)
        XCTAssertEqual(WindowColumns<EmptyView, EmptyView, EmptyView>.listWidth(100, available: 600), Size.listColumn.min)
    }

    /// The panel hidden: list and detail; the list header keeps room for the window's buttons and the toggle.
    func testPanelHidden() throws {
        let shot = try shot("Window-no-panel", width: 1180, height: 700) {
            Window(panel: false).environment(\.revealPanel, PanelReveal {})
        }
        XCTAssertFalse(shot.contains(Ink.surface.panel, in: CGRect(x: 100, y: 600, width: 40, height: 40)), "the panel is gone")
        XCTAssertTrue(shot.isColor(Size.listColumn.default - 0.5, 600, Ink.line.rule, tolerance: 0.05), "the list starts at the window's edge")
        XCTAssertTrue(shot.contains(Ink.surface.sunken, in: CGRect(x: Space.l + Size.trafficLights + Space.s, y: 15, width: 24, height: 24)),
                      "the sidebar toggle after the window's buttons")
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

    // MARK: Section panel

    /// In a real window: the panel scrolls, and `ImageRenderer` leaves scroll views blank.
    func testSectionPanel() throws {
        for section in WindowSection.allCases {
            let shot = try shot("Panel-\(section.rawValue)", width: 316, height: 900) { Panel(section: section).padding(Space.s) }
            let rows = stride(from: CGFloat(60), to: 300, by: 1)
            let current = try XCTUnwrap(shot.first(Ink.selection, x: 250, ys: rows), "\(section): no yellow row")
            let index = WindowSection.allCases.firstIndex(of: section)!
            // 40 pt rows 2 pt apart, after the top row.
            XCTAssertEqual(current, 64 + CGFloat(index) * 42, accuracy: 1.5, "\(section): the yellow block's row")
            XCTAssertTrue(shot.isColor(250, current + 38, Ink.selection), "\(section): a 40 pt row")
            // The current kind (App) is marked only in Chat.
            let app = shot.first(Ink.surface.panelRow, x: 250, ys: stride(from: CGFloat(320), to: 380, by: 1))
            if section == .chat {
                XCTAssertNotNil(app, "the current kind's dark-panel fill")
                XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: 180, y: (app ?? 0) + 12, width: 60, height: 16)), "the kind's yellow square")
            }
        }
        let folded = try shot("Panel-folded", width: 316, height: 900) { Panel(chatsOpen: false).padding(Space.s) }
        XCTAssertNil(folded.first(Ink.surface.panelRow, x: 250, ys: stride(from: CGFloat(330), to: 380, by: 1)), "no kinds while folded")
        XCTAssertNotNil(folded.first(Ink.surface.panelRow, x: 250, ys: stride(from: CGFloat(280), to: 330, by: 1)), "the Chats head stays")
        XCTAssertFalse(folded.isColor(Space.s + 1, Space.s + 1, Ink.surface.panel), "xl corners")
        XCTAssertTrue(folded.isColor(Space.s + Radius.xl, Space.s + Radius.xl, Ink.surface.panel))
    }

    func testDeviceRowInItsThreeStates() throws {
        let states: [(String, DeviceStatus, Color?)] = [
            ("linked", Self.linked, Ink.status.online),
            ("connecting", DeviceStatus(name: "macbook", state: .reconnecting, detail: "hermes.lab.x-muramasa.dev"), Ink.selection),
            ("offline", DeviceStatus(name: "macbook", state: .offline, detail: "not connected"), nil),
        ]
        for (name, device, dot) in states {
            let shot = try flat("Device-\(name)", width: 300, height: 56, ground: Ink.surface.panel) {
                DeviceRow(device: device) { Button("Settings…") {} }
            }
            let box = CGRect(x: 48, y: 24, width: 24, height: 28)
            if let dot {
                XCTAssertTrue(shot.contains(dot, in: box), "\(name): the dot")
            } else {
                XCTAssertFalse(shot.contains(Ink.status.online, in: box) || shot.contains(Ink.selection, in: box), "offline: a hollow dot")
            }
            XCTAssertTrue(shot.isColor(Space.s + 2, 30, Ink.surface.panelRow), "\(name): the avatar")
        }
        XCTAssertEqual(Self.linked.line, "linked · hermes.lab.x-muramasa.dev")
        XCTAssertEqual(DeviceStatus(name: "m", state: .reconnecting, detail: "h").line, "connecting · h")
        XCTAssertEqual(DeviceStatus(name: "m", state: .offline, detail: "token refused").line, "offline · token refused")
    }

    // MARK: List column

    func testListHeader() throws {
        let shot = try flat("ListHeader", width: 520, height: 104) {
            VStack(spacing: 0) {
                ListHeader(title: "App // 10") { IconCell(symbol: Symbol.ellipsis) } trailing: { PlusButton("New conversation") {} }
                ListHeader(title: "App // 10") { IconCell(symbol: Symbol.ellipsis) } trailing: { PlusButton("New conversation", isPrimary: false) {} }
            }
            .environment(\.onSidebar, true)
        }
        XCTAssertTrue(shot.isColor(520 - Space.l - 4, 26, Ink.selection), "the yellow +")
        XCTAssertTrue(shot.isColor(520 - Space.l - 4, 52 + 26, Ink.surface.raised), "the + steps down to white during a run")
        XCTAssertTrue(shot.isColor(Space.l + 4, 26, Ink.surface.sunken), "the … button")
        XCTAssertEqual(fitting(PlusButton("New") {}), CGSize(width: Size.control, height: Size.control))
        // The title is centred.
        let inked = stride(from: CGFloat(100), to: 420, by: 0.5).filter { shot.isColor($0, 26, Ink.text.primary, tolerance: 0.2) }
        let middle = ((inked.first ?? 0) + (inked.last ?? 0)) / 2
        XCTAssertEqual(middle, 260, accuracy: 6, "the title's centre")
    }

    func testCardsInEveryState() throws {
        let heights: [CGFloat] = [60, 60, 72, 60, 60, 60, 60, 60, 60, 60]
        let shot = try flat("Cards", width: 520, height: heights.reduce(0, +)) { Self.states }
        let tops = heights.indices.map { heights[..<$0].reduce(0, +) }
        // Idle: white between the clipped head band and foot bar, the band following the corner.
        XCTAssertTrue(shot.isColor(400, tops[0] + 2 + 2, Ink.surface.cardHead), "the head band")
        XCTAssertTrue(shot.isColor(400, tops[0] + 2 + 54, Ink.surface.cardFoot), "the foot bar")
        XCTAssertTrue(shot.isColor(400, tops[0] + 2 + 16, Ink.surface.paperCard), "white")
        XCTAssertTrue(shot.isColor(Space.s + 0.5, tops[0] + 2 + 0.5, Ink.surface.window, tolerance: 0.05), "an l corner, not a square band")
        XCTAssertTrue(shot.isColor(Space.s + 12 + 2, tops[0] + 2 + 18, Ink.avatar.app), "the 36 pt avatar")
        // Hovered: sunken.
        XCTAssertTrue(shot.isColor(400, tops[1] + 2 + 16, Ink.surface.cardHover), "hover")
        // Selected: ink, the frame 4 pt out, arcs on its corners.
        let sel = tops[2] + Space.s
        XCTAssertTrue(shot.isColor(400, sel + 16, Ink.surface.inverse), "ink")
        XCTAssertTrue(shot.isColor(Space.s - Space.xs + 0.5, sel + 28, Ink.selection), "the frame's side")
        XCTAssertTrue(shot.isColor(260, sel - Space.xs + 0.5, Ink.selection), "the frame's top")
        XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: 6, y: sel - 3, width: 6, height: 6)), "a corner arc")
        // A sticker on the preview line, 12 pt in from the card's right edge (no pin on this row).
        let run = tops[3] + 2
        XCTAssertTrue(shot.isColor(Space.s + 504 - 12 - 0.5, run + 27 + 12, Ink.line.strong), "the sticker's right edge")
        XCTAssertTrue(shot.isColor(Space.s + 504 - 4, run + 27 + 12, Ink.surface.paperCard), "12 pt of card after it")
        XCTAssertEqual(fitting(Self.card(SessionRowView(name: "a", source: .trismegistus, activity: "now"))).height, 60, "a 60 pt pitch")
        XCTAssertEqual(fitting(SessionRowView(name: "a", source: .trismegistus, activity: "now").environment(\.onSidebar, true).frame(width: 504)).height, Size.card)
    }

    func testSlab() throws {
        let shot = try flat("Slab", width: 520, height: 44) {
            SectionHead(title: "Pinned", count: 4).padding(Space.s)
        }
        XCTAssertEqual(fitting(SectionHead(title: "Pinned").frame(width: 300)).height, Size.sectionHead)
        XCTAssertTrue(shot.isColor(Space.s + Space.l + 4, 22, Ink.selection), "the yellow square")
        XCTAssertTrue(shot.isColor(260, 22, Ink.surface.inverse), "ink")
        XCTAssertTrue(shot.isColor(Space.s + 0.5, Space.s + 0.5, Ink.surface.window, tolerance: 0.05), "m corners")
    }

    // MARK: Detail

    func testDetailHeader() throws {
        let shot = try shot("DetailHeader", width: 900, height: 60) { Self.detailHeader }
        XCTAssertTrue(shot.isColor(450, 3, Ink.surface.raised), "white")
        XCTAssertTrue(shot.isColor(Space.xxl + 4, 26, Ink.avatar.app), "the avatar")
        XCTAssertTrue(shot.isColor(10, Size.sidebarHead + 2, Ink.titleRule[0]), "magenta")
        XCTAssertTrue(shot.isColor(100, Size.sidebarHead + 2, Ink.titleRule[1]), "yellow")
        XCTAssertTrue(shot.isColor(800, Size.sidebarHead + 2, Ink.titleRule[2]), "green to the edge")
    }

    func testComposerFloats() throws {
        let block = try shot("Composer", width: 800, height: 150) {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Self.composer(floating: true)
            }
        }
        XCTAssertTrue(block.isColor(3, 120, Ink.surface.window, tolerance: 0.06), "8 pt in from the side")
        XCTAssertTrue(block.isColor(400, 150 - 3, Ink.surface.window, tolerance: 0.06), "8 pt up from the bottom")
        XCTAssertTrue(block.isColor(Space.s + 0.5, 120, Ink.line.rule, tolerance: 0.05), "the rule edge")
        XCTAssertTrue(block.isColor(Space.s + Space.xs, 120, Ink.surface.raised), "the block")
        XCTAssertFalse(block.isColor(Space.s + 1, 150 - Space.s - 1, Ink.surface.raised), "an xl corner")
        _ = try shot("Composer-popover", width: 380, height: 120) { VStack { Spacer(minLength: 0); Self.composer(floating: false) } }
    }

    // MARK: B2 parts kept from #65

    func testStickerInEveryState() throws {
        let shot = try flat("Stickers", width: 300, height: 196) {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(StickerState.allCases, id: \.self) { state in
                    HStack(spacing: Space.s) {
                        Sticker(state, time: state == .running ? "00:38" : nil)
                        Sticker(state, time: state == .running ? "00:38" : nil, showsWord: false)
                        Sticker(state, isBadge: true)
                        Sticker(state, time: state == .running ? "00:38" : nil, edge: Ink.text.onDark)
                    }
                }
            }
            .padding(Space.s)
        }
        XCTAssertTrue(shot.isColor(8.5, 20, Ink.line.strong), "the edge")
        XCTAssertTrue(shot.isColor(11, 20, Ink.surface.inverse), "approval's ink cell")
        XCTAssertFalse(shot.isColor(8.5, 8.5, Ink.line.strong), "s corners")
        for state in StickerState.allCases {
            XCTAssertEqual(fitting(Sticker(state)).height, Size.sticker.height, "\(state)")
            XCTAssertEqual(fitting(Sticker(state, isBadge: true)).height, Size.sticker.badge, "\(state)")
            XCTAssertEqual(fitting(Sticker(state, isBadge: true)).width, Size.sticker.cell + 2, "\(state)")
        }
        let bare = fitting(Sticker(.approval, showsWord: false))
        XCTAssertEqual(bare.width, Size.sticker.cell + 12 + 2, "the cell, the stripes and the edge")
    }

    /// Hard stripes, 2 pt each: ink and magenta, nothing between, at the sticker's end.
    func testApprovalEndsInStripes() throws {
        let width = fitting(Sticker(.approval)).width
        let shot = try flat("Stripes", width: width, height: Size.sticker.height, ground: Ink.surface.raised) { Sticker(.approval) }
        for bar in 0..<3 {
            let x = width - 2 - CGFloat(4 * bar)
            XCTAssertTrue(shot.isColor(x, 12, Ink.surface.inverse, tolerance: 0.05), "bar \(bar) ink")
            XCTAssertTrue(shot.isColor(x - 2, 12, Ink.marker, tolerance: 0.05), "bar \(bar) magenta")
        }
    }

    func testTheClockKeepsItsWidth() {
        let widths = ["00:11", "00:88", "11:11", "59:00"].map { fitting(Sticker(.running, time: $0)).width }
        XCTAssertEqual(Set(widths).count, 1, "tabular figures: \(widths)")
    }

    func testRowStatesInThePopover() throws {
        let rows = VStack(spacing: 1) {
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h")
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", isSelected: true)
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", runElapsed: "00:38")
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", needsApproval: true)
            SessionRowView(name: "Homepage project", source: .cron, activity: "2 h", isReadOnly: true, isPinned: true)
            SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", isPinned: true, tags: ["homelab", "relay", "mac"])
        }
        let shot = try flat("Row-popover", width: 380, height: 53 * 6, ground: Ink.line.rule) { rows }
        XCTAssertTrue(shot.isColor(200, 26, Ink.surface.raised), "white, as today")
        XCTAssertTrue(shot.isColor(1, 53 + 26, Ink.selection), "the yellow bar, as today")
        XCTAssertTrue(shot.isColor(379.5, 53 * 3 + 12, Ink.line.strong), "a sticker on the row's corner")
    }

    func testSpokenRow() {
        let row = SessionRowView(name: "Android app", source: .trismegistus, activity: "2 h", isReadOnly: true, isPinned: true, needsApproval: true)
        XCTAssertEqual(row.spoken, "Android app, approval waiting, 2 h, read-only, pinned")
        XCTAssertEqual(SessionRowView(name: "Swift app", source: .trismegistus, activity: "now", runElapsed: "00:38").spoken, "Swift app, running, now")
        XCTAssertEqual(SessionRowView(name: "Refiner", source: .trismegistus, activity: "2 d", finished: .failed).spoken, "Refiner, failed, unseen, 2 d")
        XCTAssertEqual(KindChip(id: "a", title: "App", symbol: "", count: 1, mark: .approval).spoken, "App, 1 conversation, approval waiting")
    }
}
