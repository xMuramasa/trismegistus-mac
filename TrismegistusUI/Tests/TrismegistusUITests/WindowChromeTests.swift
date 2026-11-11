import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// What the window got wrong on screen after #32 (Martin's screenshot of the Commands log); the steel strip it also
/// checked went with the top bar (#68).
@MainActor
final class WindowChromeTests: XCTestCase {
    private func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private func rgb(_ rep: NSBitmapImageRep, _ view: NSView, _ x: CGFloat, _ y: CGFloat) -> [CGFloat] {
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let c = rep.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB)
        return [c?.redComponent ?? -1, c?.greenComponent ?? -1, c?.blueComponent ?? -1]
    }

    /// macOS draws its selection highlight across the full row, and keeps an 8 pt inset on list rows: the highlight
    /// showed in those margins beside the selected row (blue in a key window, grey here).
    func testNoSystemHighlightBesideTheSelectedRow() throws {
        struct Sidebar: View {
            @State var selection: Int? = 1
            var body: some View {
                List(selection: $selection) {
                    ForEach(0..<3, id: \.self) { i in
                        // The selected cell's margins carry the backing (#69); the card itself not `isSelected`: its
                        // glow and bracket corners lie in those margins too.
                        SessionRowView(name: "Row \(i)", source: .trismegistus, activity: "now")
                            .sidebarCardCell(isSelected: i == selection).tag(i).sidebarRow()
                    }
                }
                .sidebarList()
                .environment(\.onSidebar, true)
                // The list's translucent ground over paper, opaque: what the backing matches.
                .background(Ink.surface.sidebarSolid)
                .frame(width: 260, height: 190)
            }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 190), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: Sidebar())
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(1.0)
        let view = window.contentView!
        let rep = try bitmap(view)
        let ground = rgb(rep, view, 3, 60 * 2 + 30)         // beside an unselected row
        for x in [3.0, 257] {
            let margin = rgb(rep, view, x, 60 + 30)             // beside the selected row
            print("chrome: margin at x=\(x) \(margin), ground \(ground)")
            for i in 0..<3 { XCTAssertEqual(margin[i], ground[i], accuracy: 0.01, "the system highlight shows beside the selected row") }
        }
    }
}
