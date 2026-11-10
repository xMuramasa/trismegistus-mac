import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// A settled width must stop changing once the layout settles: a feedback loop between the measured width and the
/// content's frame kept the app laying out on every frame while idle (#28 after-trace).
@MainActor
final class SettledWidthTests: XCTestCase {
    private final class Panes: ObservableObject {
        @Published var sidebar = true
        @Published var width = 520.0
        @Published var inspector = true
    }

    private struct Window: View {
        @ObservedObject var panes: Panes
        var body: some View {
            WindowColumns(isPanelShown: $panes.sidebar, listWidth: $panes.width) {
                Color.black
            } list: {
                List(0..<20, id: \.self) { Text("Conversation \($0)") }
            } detail: {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(0..<40, id: \.self) { i in
                                Text(String(repeating: "word \(i) ", count: 40)).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                    }
                    .defaultScrollAnchor(.bottom)
                    .defaultScrollAnchor(.bottom, for: .sizeChanges)
                    .settledWidth()
                    Text("input").frame(maxWidth: .infinity).padding(8)
                }
                .inspector(isPresented: $panes.inspector) {
                    VStack(spacing: 0) {
                        Text("Terminal").frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 16) {
                                ForEach(0..<30, id: \.self) { i in Text("$ command \(i)\noutput line\noutput line") }
                            }
                            .padding(16)
                        }
                        .defaultScrollAnchor(.bottom)
                    }
                    .settledWidth(minimum: 280)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
                }
            }
        }
    }

    private func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testSettlesInAWindowWithSidebarAndInspector() throws {
        SettledWidth.settleCount = 0
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        let panes = Panes()
        window.contentView = NSHostingView(rootView: Window(panes: panes))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(1.5)
        let afterStart = SettledWidth.settleCount
        spin(2.0)
        let idle = SettledWidth.settleCount - afterStart
        print("settledWidth: \(afterStart) settles while starting, \(idle) while idle")
        XCTAssertEqual(idle, 0, "settled width keeps changing while idle: a layout loop")

        // One resize settles once per settledWidth (two here), not continuously.
        window.setContentSize(NSSize(width: 900, height: 700))
        spin(1.0)
        let resize = SettledWidth.settleCount - afterStart - idle
        spin(1.5)
        let afterResize = SettledWidth.settleCount - afterStart - idle - resize
        print("settledWidth: \(resize) settles after a resize, \(afterResize) after that")
        XCTAssertLessThanOrEqual(resize, 4)
        XCTAssertEqual(afterResize, 0, "settled width keeps changing after a resize")

        // Closing and opening the inspector, then the section panel (our own column, #32, #68), with animation: a few settles
        // each, not one per frame, then quiet.
        for (pane, toggle) in [("inspector", { panes.inspector.toggle() }), ("sidebar", { panes.sidebar.toggle() })] {
            for _ in 0..<2 {
                let before = SettledWidth.settleCount
                withAnimation { toggle() }
                spin(1.0)
                let toggled = SettledWidth.settleCount - before
                spin(1.0)
                let quiet = SettledWidth.settleCount - before - toggled
                print("settledWidth: \(toggled) settles after toggling the \(pane), \(quiet) after that")
                XCTAssertLessThanOrEqual(toggled, 3, "the \(pane)'s animation re-lays the chat out more than a few times")
                XCTAssertEqual(quiet, 0, "settled width keeps changing after toggling the \(pane)")
            }
        }
    }
}
