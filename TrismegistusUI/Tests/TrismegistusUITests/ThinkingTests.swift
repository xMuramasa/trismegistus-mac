import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// #74, design 16: the thinking chip and panel (16a, the 16-states rows), the WORKING line's thought, the effort pill's
/// forms (16d) and the conversation header's narrow-window rule. Writes `TrismegistusUI/.build/snapshots/Thinking-*.png`.
@MainActor
final class ThinkingTests: XCTestCase {
    static let steps = [
        ThinkingPanel.Step(
            thought: "I want to check what the window exposes before clicking anything, so I'll read the accessibility tree first "
                + "rather than take a screenshot. The tree should list the sidebar sections as buttons with their titles, and if "
                + "it doesn't I'll fall back to pressing each section in turn and reading the list title back, which takes longer.",
            tool: "terminal", detail: "cua-driver inspect"),
        ThinkingPanel.Step(thought: "Everything I was asked to check works. I should tell him the daemon is still running so he can stop it."),
    ]

    /// In a real window: menus, text selection and geometry callbacks run only there.
    private func shot<V: View>(_ name: String, width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> V) throws -> NSBitmapImageRep {
        let root = content().frame(width: width, height: height, alignment: .topLeading).background(Ink.surface.window)
            .environment(\.colorScheme, .light)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.colorSpace = .sRGB
        window.contentView = NSHostingView(rootView: root)
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let view = try XCTUnwrap(window.contentView)
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("Thinking-\(name).png"))
        return rep
    }

    private func fitting(_ view: some View, width: CGFloat? = nil) -> CGSize {
        let host = NSHostingView(rootView: view.frame(width: width).fixedSize(horizontal: width == nil, vertical: true))
        return host.fittingSize
    }

    private func light(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> CGFloat {
        let scale = CGFloat(rep.pixelsWide) / rep.size.width
        return rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.redComponent ?? -1
    }

    // MARK: 16-states

    func testTheStatesRows() throws {
        let width: CGFloat = 640
        let commands = CommandChip(commands: 4, duration: "6.1 s", isOpen: .constant(false))
        _ = try shot("States", width: width, height: 520) {
            VStack(alignment: .leading, spacing: Space.xl) {
                ThinkingBlock(steps: Self.steps, isOpen: .constant(false)) { commands }
                ThinkingBlock(steps: Self.steps, isOpen: .constant(true)) { commands }
                WorkLine(detail: "00:38 · 2 tools · thinking: “The Settings tabs are buttons too; I'll press each and read the title back before I report.”") {
                    EmptyView()
                }
                .lineLimit(1)
                commands
            }
            .padding(Space.l)
            .environment(\.hairlineControls, true)
        }
        // The chip is the commands chip's height; unfolding adds the panel under the row.
        XCTAssertEqual(fitting(ThinkingChip(steps: 4, isOpen: .constant(false))).height, Size.cardHeader)
        let folded = fitting(ThinkingBlock(steps: Self.steps, isOpen: .constant(false)), width: width).height
        let open = fitting(ThinkingBlock(steps: Self.steps, isOpen: .constant(true)), width: width).height
        XCTAssertEqual(folded, Size.cardHeader)
        XCTAssertGreaterThan(open, folded + 3 * 13)
    }

    func testTheOpenChipIsFramedInInk() throws {
        let rep = try shot("Chip", width: 240, height: 40) {
            HStack(spacing: Space.s) {
                ThinkingChip(steps: 4, isOpen: .constant(true))
                ThinkingChip(steps: 4, isOpen: .constant(false))
            }
            .padding(Space.s)
        }
        let open = fitting(ThinkingChip(steps: 4, isOpen: .constant(true))).width
        XCTAssertLessThan(light(rep, Space.s + 0.25, Space.s + Size.cardHeader / 2), 0.3, "the open chip's ink edge")
        XCTAssertGreaterThan(light(rep, Space.s + open + Space.s + 0.25, Space.s + Size.cardHeader / 2), 0.7, "the folded chip's rule edge")
    }

    /// A long thought folds to 3 lines with `more`; a short one shows whole, with no `more`.
    func testALongThoughtFoldsToThreeLines() throws {
        let long = Self.steps[0].thought
        let short = Self.steps[1].thought
        func height(_ text: String, lines: Int?) -> CGFloat {
            fitting(Text(verbatim: text).typeRole(.body).lineSpacing(Size.thinking.lineGap).lineLimit(lines), width: 300).height
        }
        let frames = Frames()
        _ = try shot("Fold", width: 360, height: 220) {
            VStack(alignment: .leading, spacing: Space.l) {
                FoldingThought(text: long).frame(width: 300)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.title = $0 }
                FoldingThought(text: short).frame(width: 300)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.avatar = $0 }
            }
            .padding(Space.l)
        }
        // Fitting sizes don't run the fold's measurements; the window does.
        let folded = frames.title.height
        XCTAssertGreaterThan(height(long, lines: nil), height(long, lines: 3), "the long thought runs past 3 lines at 300 pt")
        XCTAssertGreaterThan(folded, height(long, lines: 3) + Space.s, "3 lines and the `more` under them")
        XCTAssertLessThan(folded, height(long, lines: nil))
        XCTAssertEqual(frames.avatar.height, height(short, lines: nil), accuracy: 0.5, "no `more`")
    }

    /// The WORKING line stays one line with a thought that wouldn't fit.
    func testTheWorkingLineKeepsToOneLine() {
        func height(_ detail: String) -> CGFloat {
            fitting(WorkLine(detail: detail) { EmptyView() }.lineLimit(1).environment(\.hairlineControls, true), width: 452).height
        }
        let thought = "00:38 · 2 tools · thinking: “" + String(repeating: "The Settings tabs are buttons too. ", count: 6) + "”"
        XCTAssertEqual(height(thought), height("00:38 · 2 tools"))
    }

    // MARK: 16d

    func testTheEffortPillsForms() throws {
        let forms = ["Default", "Off", "Low", "Medium", "High", "Extra high", "Max"]
        _ = try shot("Effort", width: 760, height: 46) {
            HStack(spacing: Space.s) {
                PillLabel("claude-opus-5-5")
                ForEach(forms, id: \.self) { PillLabel($0, glyph: "∴", placeholder: $0 == "Default") }
            }
            .padding(Space.s)
        }
        for form in forms { XCTAssertEqual(fitting(PillLabel(form, glyph: "∴")).height, Size.control, form) }
        XCTAssertGreaterThan(fitting(PillLabel("High", glyph: "∴")).width, fitting(PillLabel("High")).width, "the ∴ shows")
    }

    // MARK: The header's narrow-window rule

    final class Frames {
        var avatar = CGRect.zero
        var title = CGRect.zero
        /// The meter's left edge, the last button's right edge.
        var trailingMinX: CGFloat = 0
        var trailingMaxX: CGFloat = 0
        var stage = -1
    }

    struct Header: View {
        let frames: Frames

        var body: some View {
            FittedHeader {
                SourceAvatar(.trismegistus, size: Size.avatar.header).onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.avatar = $0 }
            } title: {
                Text(verbatim: "Swift app: the thinking chip and the effort pill").onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.title = $0 }
            } subtitle: {
                Text(verbatim: "Trismegistus · run_7f3a2c · started 13:52")
            } trailing: { fit in
                HStack(spacing: Space.s) {
                    // The context meter as ContextMeter draws it: the reading, then its 10 cells (the percentage alone at stage 1).
                    Text(verbatim: fit.meterCompact ? "35%" : "≈ 350K / 1M · 35%").typeRole(.caption).monospacedDigit().fixedSize()
                    if !fit.meterCompact { Rectangle().frame(width: 10 * Size.meterCell.width + 9, height: Size.meterCell.height) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minX } action: { frames.trailingMinX = $0 }
                // As ModelMenu and EffortMenu place them: never squeezed.
                PillLabel(fit.model("claude-opus-5-5 1M")).fixedSize()
                PillLabel(fit.effortShort ? "" : "Extra high", glyph: "∴").fixedSize()
                IconCell(symbol: Symbol.terminal)
                IconCell(symbol: Symbol.settings)
                IconCell(symbol: Symbol.ellipsis)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.trailingMaxX = $0.maxX }
                    .onChange(of: fit.stage, initial: true) { frames.stage = fit.stage }
            }
        }
    }

    /// At 1560 the title keeps 120 pt (the meter shows its percentage alone). At 1180 it can't: with both steps taken the
    /// readings and buttons still take about 365 pt of the 484, leaving the title about 20 (the report has the numbers);
    /// nothing overlaps there either.
    func testTheHeaderAt1180And1560() throws {
        // The detail column: the window less the panel (8 pt in each side) and the list (380 at 1180 pt, 520 at 1560).
        for (window, list) in [(CGFloat(1180), Size.listColumn.min), (1560, Size.listColumn.default)] {
            let width = window - Size.sectionPanel.width - 2 * Space.s - list
            let frames = Frames()
            _ = try shot("Header-\(Int(window))", width: width, height: Size.sidebarHead + Size.titleRule.height) { Header(frames: frames) }
            let room = frames.title.width
            print("Header \(Int(window)): detail \(width), stage \(frames.stage), title \(frames.title), trailing \(frames.trailingMinX)…\(frames.trailingMaxX)")
            if window == 1180 {
                XCTAssertEqual(frames.stage, 3, "all three steps taken")
                XCTAssertGreaterThanOrEqual(room, 80, "the title keeps about 85 pt at 1180")
            } else {
                XCTAssertGreaterThanOrEqual(room, Size.thinking.titleMin - 0.5, "\(window): the title keeps 120 pt")
            }
            XCTAssertLessThanOrEqual(frames.title.maxX, frames.trailingMinX, "\(window): the title ends before the meter")
            XCTAssertLessThanOrEqual(frames.trailingMaxX, width - Space.l + 0.5, "\(window): the last button inside the header")
            XCTAssertGreaterThanOrEqual(frames.title.minX, frames.avatar.maxX, "\(window): the title right of the avatar")
        }
    }

    func testHeaderFitStepsAndStepsBack() {
        var fit = HeaderFit()
        let narrow = HeaderFit.chrome + Size.thinking.titleMin + 300
        fit.fit(width: narrow, trailing: 420)
        XCTAssertEqual(fit.stage, 1)
        fit.fit(width: narrow, trailing: 340) // the meter's percentage alone isn't enough
        XCTAssertEqual(fit.stage, 2)
        XCTAssertEqual(fit.model("claude-opus-5-5"), "opus-5-5")
        fit.fit(width: narrow, trailing: 300)
        XCTAssertEqual(fit.stage, 2, "fits: stays")
        fit.fit(width: narrow, trailing: 440) // wider again at stage 2 (a longer level): stage 3
        XCTAssertEqual(fit.stage, 3)
        XCTAssertTrue(fit.effortShort)
        fit.fit(width: narrow, trailing: 360)
        XCTAssertEqual(fit.stage, 3, "the cap: no stage 4")
        fit.fit(width: narrow + 200, trailing: 300)
        XCTAssertEqual(fit.stage, 2, "room for stage 2's 440 again")
        fit.fit(width: narrow + 40, trailing: 300)
        XCTAssertEqual(fit.stage, 1, "room for stage 1's 340 again")
        fit.fit(width: narrow + 200, trailing: 340)
        XCTAssertEqual(fit.stage, 0)
        XCTAssertEqual(HeaderFit().model("claude-opus-5-5"), "claude-opus-5-5")
    }
}
