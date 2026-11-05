import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

@MainActor
final class TerminalEntryTests: XCTestCase {
    private func height(_ view: some View, width: CGFloat = 360) -> CGFloat {
        let host = NSHostingView(rootView: view.frame(width: width))
        host.frame = NSRect(x: 0, y: 0, width: width, height: 2000)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    /// The cap is "eight conversation rows": keep the constant in step with the sidebar row.
    func testRowHeightMatchesTheSidebarRow() {
        XCTAssertEqual(height(SessionRowView(name: "Homelab backup check", source: .telegram, activity: "2 h"), width: 260),
                       TerminalEntryView.rowHeight)
    }

    func testFoldedByDefault() {
        let folded = height(TerminalEntryView(time: "12:04:31", tool: "terminal", command: "ls", output: "a\nb", exitCode: 0))
        XCTAssertEqual(folded, TerminalEntryView.headerHeight, "a new entry shows its header only")
    }

    func testOneLineIsAToolRow() {
        let row = height(TerminalEntryView(time: "12:04:31", tool: "terminal", command: "ls", output: "a\nb", exitCode: 0, oneLine: true))
        XCTAssertEqual(row, Size.rowTool, "its output folded under it")
    }

    func testLongOutputScrollsInsideEightRows() {
        // One very long line: it wraps past the cap even though the preview keeps the first 12 lines.
        let long = String(repeating: "0123456789 ", count: 2000)
        let open = height(TerminalEntryView(time: "t", tool: "t", command: "seq 200", output: long, exitCode: 0, startsFolded: false))
        XCTAssertEqual(open, 8 * TerminalEntryView.rowHeight, accuracy: 0.5)
        let short = height(TerminalEntryView(time: "t", tool: "t", command: "ls", output: "a\nb", exitCode: 0, startsFolded: false))
        XCTAssertLessThan(short, 8 * TerminalEntryView.rowHeight / 2, "a short entry keeps its own height")
    }

    /// Review 2026-11-04: a failed card (chip + duration) in a 392 pt pane drew past its frame. The tool name gives way.
    /// The card sits over a white strip wider than its frame: nothing of it may land on the strip's far side.
    func testAFailedCardFitsANarrowPane() throws {
        for width: CGFloat in [300, 392] {
            let card = TerminalEntryView(time: "21:27:15", tool: "vision_analyze", command: "swift test --filter Snap", exitCode: 1, duration: 18.9)
            let view = ZStack(alignment: .topLeading) { Color.white.frame(width: width + 120, height: 40); card.frame(width: width) }
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: width + 120, height: 40)
            host.layoutSubtreeIfNeeded()
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(rep.pixelsWide) / host.bounds.width
            var spill = 0
            for x in Int((width + 6) * scale)..<rep.pixelsWide {  // past the card shadow's edge
                for y in 0..<Int(20 * scale) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent + c.greenComponent + c.blueComponent < 2.9 { spill += 1 }
                }
            }
            XCTAssertEqual(spill, 0, "the card drew past its \(Int(width)) pt frame")
        }
    }

    func testFirstLineIsTheFirstNonBlankLineVerbatim() {
        XCTAssertEqual(TerminalEntryView.firstLine("ls -la"), "ls -la")
        XCTAssertEqual(TerminalEntryView.firstLine("\n   \n\tcd /tmp  \nmake"), "cd /tmp", "as written, without its indent")
        XCTAssertEqual(TerminalEntryView.firstLine("grep -n 'a  b' x"), "grep -n 'a  b' x", "inner spaces stay")
        XCTAssertEqual(TerminalEntryView.firstLine("  \n"), "")
        XCTAssertEqual(TerminalEntryView.firstLine(""), "")
    }

    func testAccentByTool() {
        XCTAssertEqual(TerminalEntryView.accent("terminal"), Palette.accentCyan)
        XCTAssertEqual(TerminalEntryView.accent("vision_analyze"), Palette.accentMagenta)
        for tool in ["web_extract", "execute_code", "read_file"] {
            XCTAssertEqual(TerminalEntryView.accent(tool), Palette.yellow)
        }
    }
}
