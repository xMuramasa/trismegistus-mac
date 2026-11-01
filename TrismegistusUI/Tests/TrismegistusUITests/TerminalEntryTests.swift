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
        let folded = height(TerminalEntryView(title: "12:04:31 terminal", command: "ls", output: "a\nb", exitCode: 0))
        XCTAssertEqual(folded, TerminalEntryView.headerHeight + 1, "a new entry shows its header only")
    }

    func testLongOutputScrollsInsideEightRows() {
        // One very long line: it wraps past the cap even though the preview keeps the first 12 lines.
        let long = String(repeating: "0123456789 ", count: 2000)
        let open = height(TerminalEntryView(title: "t", command: "seq 200", output: long, exitCode: 0, startsFolded: false))
        XCTAssertEqual(open, 8 * TerminalEntryView.rowHeight, accuracy: 0.5)
        let short = height(TerminalEntryView(title: "t", command: "ls", output: "a\nb", exitCode: 0, startsFolded: false))
        XCTAssertLessThan(short, 8 * TerminalEntryView.rowHeight / 2, "a short entry keeps its own height")
    }
}
