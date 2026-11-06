import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window sidebar's B2 look (#65). Writes `TrismegistusUI/.build/snapshots/B2-*.png` for review against
/// `design/ui-draft/12a-opendesign-sidebar-b2*.png`, and asserts what matters in the pixels and sizes themselves.
@MainActor
final class SidebarB2Tests: XCTestCase {
    private struct Shot {
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
    }

    private func save(_ rep: NSBitmapImageRep, _ name: String) throws {
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("B2-\(name).png"))
    }

    /// In a real window: `List`, `Menu` and text fields draw only there.
    private func shot<V: View>(_ name: String, width: CGFloat, height: CGFloat, ground: Color = Ink.surface.sidebar, @ViewBuilder _ content: () -> V) throws -> Shot {
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
    private func flat<V: View>(_ name: String, width: CGFloat, height: CGFloat, ground: Color = Ink.surface.sidebar, @ViewBuilder _ content: () -> V) throws -> Shot {
        let renderer = ImageRenderer(content: content().frame(width: width, height: height, alignment: .topLeading).background(ground).environment(\.colorScheme, .light))
        renderer.scale = 2
        let rep = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage, "\(name) did not render"))
        try save(rep, name)
        return Shot(rep: rep, size: CGSize(width: width, height: height))
    }

    /// A row in its cell at the sidebar's card width, on the grey ground.
    private func card(_ row: SessionRowView, width: CGFloat = 288) -> some View {
        row.sidebarCardCell().frame(width: width).padding(.horizontal, Space.s).environment(\.onSidebar, true)
    }

    private func fitting(_ view: some View) -> CGSize { NSHostingView(rootView: view).fittingSize }

    /// The sidebar's parts as `ConversationSidebar` puts them together, with the design's content.
    private struct Sidebar: View {
        var narrow = false
        var count = 10
        @State private var selection: String? = "swift"

        private func row(_ id: String, hover: Bool = false, _ build: (Bool) -> SessionRowView) -> some View {
            build(selection == id).sidebarCardCell().environment(\.rowHovered, hover).tag(id).sidebarRow()
        }

        var body: some View {
            VStack(spacing: 0) {
                VStack(spacing: Space.s) {
                    HStack(spacing: Space.s) {
                        SidebarTitle("App // \(count)")
                        Spacer(minLength: Space.s)
                        EndfieldButton("New conversation", symbol: Symbol.plus, kind: .quiet, iconOnly: true) {}
                    }
                    .frame(height: Size.sidebarHead)
                    .padding(.bottom, -Space.s)
                    KindTabs(tabs: [KindChip(id: "app", title: "App", symbol: Symbol.kindApp, count: 10, mark: .approval),
                                    KindChip(id: "telegram", title: "Telegram", symbol: Symbol.kindTelegram, count: 4),
                                    KindChip(id: "terminal", title: "Terminal", symbol: Symbol.kindTerminal, count: 9)],
                             more: [], selection: "app") { _ in }
                    EndfieldTextField("Filter conversations", text: .constant("")).padding(.trailing, Space.xs)
                }
                .padding(.horizontal, Space.l).padding(.bottom, Space.m)
                List(selection: $selection) {
                    SectionHead(title: "Pinned").padding(.horizontal, -Space.s).padding(.bottom, Space.xs).sidebarRow()
                    row("swift") { SessionRowView(name: "Swift app", source: .trismegistus, activity: "now", isSelected: $0, isPinned: true, runElapsed: "00:38") }
                    row("trism") { SessionRowView(name: "Trismegistus", source: .trismegistus, activity: "1 h", isSelected: $0, isPinned: true) }
                    row("android") { SessionRowView(name: "Android app", source: .trismegistus, activity: "2 h", isSelected: $0, isPinned: true, needsApproval: true) }
                    SectionHead(title: "Conversations").padding(.horizontal, -Space.s).padding(.bottom, Space.xs).padding(.top, Space.l).sidebarRow()
                    row("compare", hover: true) { SessionRowView(name: "Compare Open Design vs Penpot", source: .trismegistus, activity: "5 min", isSelected: $0) }
                    row("xmur") {
                        SessionRowView(name: "xMuramasa/homelab#1: Add the Trismegistus relay", source: .trismegistus, activity: "1 h", isSelected: $0, tags: ["homelab", "relay", "mac"])
                    }
                    row("brief") { SessionRowView(name: "The briefing project", source: .telegram, activity: "yesterday", isSelected: $0) }
                    row("digest") { SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", isSelected: $0, isReadOnly: true) }
                    SidebarFlare(count: count).sidebarRow()
                }
                .sidebarList()
                SectionBar(selection: .constant(.chat), device: "macbook · paired")
            }
            .environment(\.onSidebar, true)
            .environment(\.sidebarNarrow, narrow)
        }
    }

    func testWindowSidebarInARealList() throws {
        let shot = try shot("Sidebar", width: 304, height: 880) { Sidebar() }
        XCTAssertTrue(shot.isColor(2, 880 - 40, Ink.surface.inverse), "the footer's ink bar reaches the column's edge")
        // The grey head bands of the plain cards, top to bottom: 60 pt apart.
        var bands: [CGFloat] = []
        var y: CGFloat = 0
        while y < 880 {
            if shot.isColor(200, y, Ink.surface.cardHead, tolerance: 0.01) {
                bands.append(y)
                y += Stroke.rule + 1
            } else {
                y += 0.5
            }
        }
        print("b2: head bands at \(bands)")
        XCTAssertGreaterThanOrEqual(bands.count, 3)
        for (a, b) in zip(bands, bands.dropFirst()).suffix(2) { XCTAssertEqual(b - a, 60, accuracy: 0.5) }
        // The slab runs over the list's 8 pt margins, edge to edge.
        var slab: CGFloat?
        for y in stride(from: CGFloat(100), to: 300, by: 1) where shot.isColor(292, y, Ink.surface.inverse) && shot.isColor(292, y + 20, Ink.surface.inverse) {
            slab = y
            break
        }
        let top = try XCTUnwrap(slab, "no section head")
        XCTAssertTrue(shot.isColor(1, top + 12, Ink.surface.inverse), "the section head stops short of the left edge")
        XCTAssertTrue(shot.isColor(302, top + 22, Ink.surface.inverse), "the section head stops short of the right edge")
        // A `List` clips each row (measured): the selected card's frame has to fit its 60 pt cell, 4 pt under the slab.
        let cell = top + Size.sectionHead + Space.xs
        XCTAssertTrue(shot.isColor(150, cell + 0.5, Ink.selection), "the frame's top edge is clipped")
        XCTAssertTrue(shot.isColor(150, cell + 59.5, Ink.selection), "the frame's bottom edge is clipped")
    }

    func testNarrowSidebar() throws {
        _ = try shot("Sidebar-220", width: 220, height: 880) { Sidebar(narrow: true) }
        let word = fitting(Sticker(.approval))
        let bare = fitting(Sticker(.approval, showsWord: false))
        XCTAssertEqual(bare.width, Size.sticker.cell + 12 + 2, "the cell, the stripes and the edge")
        XCTAssertGreaterThan(word.width, bare.width)
        let clock = fitting(Sticker(.running, time: "00:38", showsWord: false))
        XCTAssertGreaterThan(clock.width, fitting(Sticker(.running, showsWord: false)).width, "a run keeps its time")
    }

    func testStickerInEveryState() throws {
        let shot = try flat("Stickers", width: 300, height: 196, ground: Ink.surface.window) {
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
        XCTAssertTrue(shot.isColor(9, 12, Ink.line.strong), "the edge")
        XCTAssertTrue(shot.isColor(11, 12, Ink.surface.inverse), "approval's ink cell")
        for state in StickerState.allCases {
            XCTAssertEqual(fitting(Sticker(state)).height, Size.sticker.height, "\(state)")
            XCTAssertEqual(fitting(Sticker(state, isBadge: true)).height, Size.sticker.badge, "\(state)")
            XCTAssertEqual(fitting(Sticker(state, isBadge: true)).width, Size.sticker.cell + 2, "\(state)")
        }
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

    func testRowStatesOnTheSidebar() throws {
        let height: CGFloat = 60 * 8
        let shot = try flat("Row-sidebar", width: 304, height: height) {
            VStack(spacing: 0) {
                card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h"))
                card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", runElapsed: "00:38"))
                card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h")).environment(\.rowHovered, true)
                card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", needsApproval: true))
                card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", isSelected: true))
                card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", isSelected: true, runElapsed: "00:38"))
                card(SessionRowView(name: "Homepage project", source: .cron, activity: "2 h", isReadOnly: true, isPinned: true))
                card(SessionRowView(name: "Homepage project", source: .trismegistus, activity: "2 h", tags: ["homelab", "relay", "mac"]))
            }
        }
        // Idle: paper between a muted head band and a dark foot bar, no edge, no shadow.
        XCTAssertTrue(shot.isColor(150, 4 + 2, Ink.surface.cardHead), "the head band")
        XCTAssertTrue(shot.isColor(150, 4 + 8, Ink.surface.paperCard), "paper")
        XCTAssertTrue(shot.isColor(150, 4 + 49, Ink.surface.cardFoot), "the foot bar")
        XCTAssertTrue(shot.isColor(8, 4 + 26, Ink.surface.paperCard), "no edge at rest")
        XCTAssertTrue(shot.isColor(298, 4 + 26, Ink.surface.sidebar), "no shadow at rest")
        // Hovered: the ink edge and a shadow to the right.
        XCTAssertTrue(shot.isColor(8.5, 120 + 4 + 26, Ink.line.strong), "the hover edge")
        XCTAssertLessThan(shot.rgb(297, 120 + 4 + 26)[0], shot.rgb(297, 4 + 26)[0] - 0.02, "the hover shadow")
        XCTAssertLessThan(shot.rgb(150, 120 + 4 + 52 + 2)[0], shot.rgb(150, 120 + 4 - 2)[0] - 0.02, "the shadow falls below the card, not above it")
        XCTAssertTrue(shot.isColor(150, 120 + 12, Ink.surface.paperCard), "the head band casts nothing on the paper")
        // Selected: ink, the frame 4 pt out, nodes on its corners.
        XCTAssertTrue(shot.isColor(150, 240 + 30, Ink.surface.inverse), "ink fill")
        XCTAssertTrue(shot.isColor(4.5, 240 + 30, Ink.selection), "the frame")
        XCTAssertTrue(shot.isColor(6.5, 240 + 1.5, Ink.selection), "a corner node")
        XCTAssertTrue(shot.isColor(24, 240 + 4 + 16, Ink.selection), "the marker square before the title")
        // Sticker: on the card's corner, inside it, on the selected card with the light edge.
        XCTAssertTrue(shot.isColor(295.5, 60 + 4 + 12, Ink.line.strong), "the sticker's edge at the card's right")
        XCTAssertTrue(shot.isColor(290, 60 + 4.5, Ink.line.strong), "its top edge on the card's top")
        XCTAssertGreaterThan(shot.rgb(290, 60 + 3.5)[0], 0.3, "no overhang onto the card above (its soft shadow may tint the gap)")
        XCTAssertTrue(shot.isColor(295.5, 300 + 4 + 12, Ink.text.onDark), "on-steel on the ink card")
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
    }

    func testKindTabs() throws {
        let tabs = [KindChip(id: "app", title: "App", symbol: Symbol.kindApp, count: 10, mark: .approval),
                    KindChip(id: "telegram", title: "Telegram", symbol: Symbol.kindTelegram, count: 4, mark: .running),
                    KindChip(id: "terminal", title: "Terminal", symbol: Symbol.kindTerminal, count: 9)]
        let more = [KindChip(id: "cron", title: "Cron", symbol: Symbol.clock, count: 3)]
        let shot = try shot("KindTabs", width: 304, height: 100) {
            VStack(spacing: Space.s) {
                KindTabs(tabs: tabs, more: more, selection: "app") { _ in }
                KindTabs(tabs: tabs, more: more, selection: "cron") { _ in }.environment(\.sidebarNarrow, true)
            }
            .padding(Space.s)
            .environment(\.onSidebar, true)
        }
        XCTAssertTrue(shot.isColor(11, 12, Ink.selection), "the current tab is solid yellow")
        XCTAssertTrue(shot.isColor(8.5, 22, Ink.line.strong), "a 1 pt ink edge")
        XCTAssertEqual(KindChip(id: "a", title: "App", symbol: "", count: 1, mark: .approval).spoken, "App, 1 conversation, approval waiting")
    }

    func testFooter() throws {
        let shot = try flat("Footer", width: 304, height: 200) {
            VStack(spacing: Space.s) {
                SectionBar(selection: .constant(.chat), device: "macbook · paired")
                SectionBar(selection: .constant(.commands), device: "macbook · paired").environment(\.sidebarNarrow, true)
            }
        }
        XCTAssertTrue(shot.isColor(2, 8, Ink.surface.inverse), "the ink bar")
        XCTAssertTrue(shot.isColor(14, 60, Ink.selection), "the current section's block")
        XCTAssertTrue(shot.isColor(70, 60, Ink.surface.inverse), "the others on ink")
    }

    func testHeaderAndFilter() throws {
        var focused = EndfieldTextField("Filter conversations", text: .constant(""))
        focused.forceFocused = true
        let shot = try shot("Header", width: 304, height: 190) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack {
                    SidebarTitle("App // 10")
                    Spacer()
                    EndfieldButton("New conversation", symbol: Symbol.plus, kind: .quiet, iconOnly: true) {}
                }
                EndfieldTextField("Filter conversations", text: .constant(""))
                focused
                HStack { SidebarTitle("Agents // 12 running"); Spacer() }
            }
            .padding(Space.l)
            .environment(\.onSidebar, true)
        }
        let plus = fitting(EndfieldButton("New", symbol: Symbol.plus, kind: .quiet, iconOnly: true) {}.environment(\.onSidebar, true))
        XCTAssertEqual(plus.width, Size.headAction)
        XCTAssertEqual(plus.height, Size.headAction)
        XCTAssertTrue(shot.isColor(304 - 18, 20, Ink.surface.inverse), "the `+` is an ink block")
        // Filter: white, an ink edge, the soft shadow, yellow while focused.
        let field = fitting(EndfieldTextField("Filter", text: .constant("")).frame(width: 272).environment(\.onSidebar, true))
        XCTAssertEqual(field.height, Size.control)
        let ground = shot.rgb(2, 2)
        XCTAssertLessThan(shot.rgb(290, 72)[0], ground[0] - 0.02, "the ink shadow")
        let yellow = shot.rgb(290, 118)
        XCTAssertGreaterThan(yellow[0], ground[0] + 0.02, "the yellow shadow")
        XCTAssertLessThan(yellow[2], ground[2] - 0.02, "the yellow shadow")
        XCTAssertTrue(shot.isColor(200, 72, Ink.surface.raised, tolerance: 0.001), "no shadow inside the field, on the text")
    }

    func testSectionHead() throws {
        let shot = try flat("SectionHead", width: 304, height: 56) {
            VStack(spacing: Space.s) {
                SectionHead(title: "Pinned")
                SectionHead(title: "Conversations")
            }
        }
        XCTAssertEqual(fitting(SectionHead(title: "Pinned").frame(width: 304)).height, Size.sectionHead)
        XCTAssertTrue(shot.isColor(12, 12, Ink.selection), "the yellow square")
        func peak(_ range: ClosedRange<CGFloat>) -> CGFloat {
            var peak: CGFloat = 0
            for x in stride(from: range.lowerBound, through: range.upperBound, by: 0.5) {
                for y in stride(from: CGFloat(1), to: 23, by: 0.5) { peak = max(peak, shot.rgb(x, y)[0]) }
            }
            return peak
        }
        print("b2: contour peaks \(peak(100...125)) \(peak(250...300))")
        XCTAssertLessThan(peak(100...125), peak(250...300) * 0.6, "the lines fade out towards the label")
        XCTAssertLessThan(fitting(SectionHead(title: "Conversations").frame(width: 220)).width, 221, "the slab keeps the column's width")
    }

    /// Decorative: no clicks, nothing for VoiceOver.
    func testFlare() throws {
        let shot = try flat("Flare", width: 304, height: 130) { SidebarFlare(count: 10) }
        XCTAssertFalse(shot.isColor(60, 70, Ink.surface.sidebar, tolerance: 0.01) && shot.isColor(30, 70, Ink.surface.sidebar, tolerance: 0.01), "the count")
        let host = NSHostingView(rootView: SidebarFlare(count: 10).frame(width: 304, height: 130))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.accessibilityChildren()?.count ?? 0, 0)
    }

    /// Data on the sidebar is Inter: nothing the sidebar's parts draw asks for the mono family, and the same row off
    /// the sidebar still does.
    func testTheSidebarUsesNoMonoFace() throws {
        TypeSpec.drawn = []
        _ = try shot("Sidebar-mono-check", width: 304, height: 880) { Sidebar() }
        XCTAssertTrue(TypeSpec.drawn.contains(.ui))
        XCTAssertFalse(TypeSpec.drawn.contains(.mono), "a mono role on the sidebar")
        TypeSpec.drawn = []
        _ = try shot("Sidebar-mono-check", width: 304, height: 60) {
            SessionRowView(name: "Popover", source: .trismegistus, activity: "2 h", tags: ["relay"])
        }
        XCTAssertTrue(TypeSpec.drawn.contains(.mono), "the check itself sees mono")
    }
}
