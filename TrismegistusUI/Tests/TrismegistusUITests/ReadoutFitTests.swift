import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The GitHub issue readout settles at every window width (#73). It used to try whole `ReadoutRow`s in a
/// `ViewThatFits` to show as many tags as fit; with the rows' native menu pickers inside, layout never settled at some
/// widths (AppKit's "more layout passes than views" at a 1595 pt window with a 492.6 pt list) and the app froze at
/// 100 % CPU. Now one row, and `ReadoutTags` fits its tags through `FittingTagsLayout`.
@MainActor
final class ReadoutFitTests: XCTestCase {
    func testTagsFitTheWidthOffered() {
        // Three 40 pt tags, spacing 4; "+1"/"+2"/"+3" are 12 pt.
        let tags: [CGFloat] = [40, 40, 40], more: [CGFloat] = [12, 12, 12]
        func fit(_ limit: CGFloat?) -> Int { FittingTagsLayout.fit(tags: tags, more: more, spacing: 4, limit: limit).shown }
        XCTAssertEqual(fit(nil), 3)
        XCTAssertEqual(fit(.infinity), 3)
        XCTAssertEqual(fit(128), 3)  // 40 + 4 + 40 + 4 + 40
        XCTAssertEqual(fit(127), 2)  // 40 + 4 + 40 + 4 + "+1"
        XCTAssertEqual(fit(100), 2)
        XCTAssertEqual(fit(99), 1)   // 40 + 4 + "+2"
        XCTAssertEqual(fit(55), 0)   // "+3" alone
        XCTAssertEqual(FittingTagsLayout.fit(tags: tags, more: more, spacing: 4, limit: 0).width, 12)
    }

    final class Passes { var count = 0 }

    /// Counts the layout passes of everything inside.
    struct Counting: Layout {
        let passes: Passes
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            subviews.first?.sizeThatFits(proposal) ?? .zero
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            passes.count += 1
            subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }

    /// The window's columns around an issue as `GitHubIssueView` lays it out (xMuramasa/tablet-kiosk#2's fields).
    struct Issue: View {
        var body: some View {
            WindowColumns(isPanelShown: .constant(true), listWidth: .constant(492.6)) {
                Color.clear
            } list: {
                ScrollView { VStack { ForEach(0..<20, id: \.self) { Text(verbatim: "row \($0)").frame(height: Size.rowCompact) } } }
            } detail: {
                VStack(spacing: 0) {
                    DetailHeader {
                        Text(verbatim: "App: full-screen WebView with a pull-down navigation bar, self-recovery, pinning and PIN-protected settings")
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    } subtitle: {
                        Text(verbatim: "xMuramasa/tablet-kiosk#2 · open · 9 d")
                    } trailing: {
                        EndfieldButton("Open in browser", symbol: "arrow.up.right", kind: .quiet, iconOnly: true) {}
                    }
                    ReadoutRow {
                        ReadoutCell("Status") { ReadoutMenu("Status", value: "Needs check", options: ["Todo", "In progress", "Needs check", "Done"]) { _ in } }
                        ReadoutCell("Priority") { ReadoutMenu("Priority", value: "P1", options: ["P0", "P1", "P2"], width: nil) { _ in } }
                        ReadoutCell("Tags") { ReadoutTags(["enhancement", "area: app"]) }.readoutFills()
                        ReadoutCell("Agent") { ReadoutTag("opus") }
                    } trailing: {
                        EndfieldButton("Close issue", symbol: "checkmark.circle") {}
                    }
                    ScrollView { Text(String(repeating: "word ", count: 400)).padding(Space.l) }
                }
            }
        }
    }

    func testIssueReadoutSettlesAtEveryWidth() {
        let passes = Passes()
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1603, height: 900), styleMask: [.titled, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Counting(passes: passes) { Issue() })
        window.orderFront(nil)
        defer { window.close() }
        var unsettled: [String] = []
        let widths = Array(stride(from: 900, through: 1700, by: 20)) + Array(1585...1612)
        for width in widths {
            window.setContentSize(NSSize(width: width, height: 900))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            passes.count = 0
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if passes.count > 2 { unsettled.append("\(width) pt: \(passes.count) passes while idle") }
        }
        XCTAssertEqual(unsettled, [], "the readout's layout never settled")
    }
}
