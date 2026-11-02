import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// Two things the window got wrong on screen after #32 (Martin's screenshot of the Commands log).
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

    private struct PlainDetail: View {
        @State private var shown = true
        @State private var width = 260.0
        var body: some View {
            SidebarSplit(isShown: $shown, width: $width) {
                Text("Conversations").frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } detail: {
                // Like the Commands log: a ground that reaches up under the toolbar.
                Text("Commands // 426").frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
                    .topBarColumn(.window)
            }
            .topBar()
            .toolbar { ToolbarItem(placement: .navigation) { Text("Trismegistus").foregroundStyle(Palette.onSteel) } }
        }
    }

    /// The strip above a detail without a conversation header (Commands, News, the empty state).
    func testStripAboveAPlainDetail() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 500),
                              styleMask: [.titled, .resizable, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: PlainDetail())
        host.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(1.5)
        let frame = window.contentView!.superview!
        let rep = try bitmap(frame)
        let top = window.contentView!.bounds.height - window.contentLayoutRect.maxY
        let above = rgb(rep, frame, 700, top / 2)
        print("chrome: toolbar above the plain detail \(above)")
        XCTAssertLessThan(above[0], 0.5, "the detail's ground covers the strip: \(above)")
    }

    /// macOS draws its selection highlight across the full row, and keeps an 8 pt inset on list rows: the highlight
    /// showed in those margins beside the selected row (blue in a key window, grey here).
    func testNoSystemHighlightBesideTheSelectedRow() throws {
        struct Sidebar: View {
            @State var selection: Int? = 1
            var body: some View {
                List(selection: $selection) {
                    ForEach(0..<3, id: \.self) { i in
                        SessionRowView(name: "Row \(i)", source: .trismegistus, activity: "now", isSelected: selection == i)
                            .tag(i).listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Ink.surface.sidebar)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .environment(\.onSidebar, true)
                .background(Ink.surface.sidebar)
                .frame(width: 260, height: 170)
            }
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 170), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: Sidebar())
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(1.0)
        let view = window.contentView!
        let rep = try bitmap(view)
        let ground = rgb(rep, view, 130, 52 * 2 + 26)       // an unselected row
        for x in [3.0, 257] {
            let margin = rgb(rep, view, x, 52 + 26)             // beside the selected row
            print("chrome: margin at x=\(x) \(margin), ground \(ground)")
            for i in 0..<3 { XCTAssertEqual(margin[i], ground[i], accuracy: 0.01, "the system highlight shows beside the selected row") }
        }
    }
}
