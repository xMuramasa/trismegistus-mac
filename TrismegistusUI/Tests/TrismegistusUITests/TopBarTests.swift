import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The toolbar and the conversation header are one steel strip: rendered from the window's frame view (toolbar
/// included) to `.build/snapshots/TopBar*.png`, sidebar open and closed (#30).
@MainActor
final class TopBarTests: XCTestCase {
    private final class Panes: ObservableObject {
        @Published var columns = NavigationSplitViewVisibility.all
        @Published var inspector = true
    }

    private struct Window: View {
        @ObservedObject var panes: Panes
        var body: some View {
            NavigationSplitView(columnVisibility: $panes.columns) {
                List(0..<20, id: \.self) { Text("Conversation \($0)") }
                    .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
            } detail: {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Conversation title").typeRole(.title)
                        Spacer(minLength: 0)
                        Text("≈ 92K / 1M · 9%").typeRole(.monoSmall).opacity(0.7)
                    }
                    .foregroundStyle(Theme.onSteel)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background { TopBarBackdrop().padding(.top, -1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.steelRule).frame(height: 1) }
                    Text("chat").frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
                }
                .inspector(isPresented: $panes.inspector) {
                    Text("Terminal").frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.raised)
                        .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
                }
            }
            .topBar()
            .toolbar {
                ToolbarItem(placement: .navigation) { Text("Trismegistus").typeRole(.heading).foregroundStyle(Theme.onSteel) }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) {
                    Image(systemName: Symbol.terminal).foregroundStyle(Theme.onSteel)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbar(removing: .title)
        }
    }

    private func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// The frame view (toolbar included) as a bitmap; writes it to the snapshots folder.
    private func render(_ view: NSView, _ name: String) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("\(name).png"))
        return rep
    }

    private func rgb(_ rep: NSBitmapImageRep, _ point: CGPoint, scale: CGFloat) -> [CGFloat] {
        let c = rep.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))?.usingColorSpace(.sRGB)
        return [c?.redComponent ?? -1, c?.greenComponent ?? -1, c?.blueComponent ?? -1]
    }

    func testOneStripUnderToolbarAndHeader() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .resizable, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        let panes = Panes()
        let host = NSHostingView(rootView: Window(panes: panes))
        host.sceneBridgingOptions = [.toolbars, .title]
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(1.5)

        // The header's colour at x = 600 per sidebar state: in window coordinates it doesn't depend on the sidebar.
        var headers: [[CGFloat]] = []
        for (columns, name) in [(NavigationSplitViewVisibility.all, "TopBarSidebarOpen"), (.detailOnly, "TopBarSidebarClosed")] {
            withAnimation { panes.columns = columns }
            spin(1.5)
            let rep = try render(window.contentView!.superview!, name)
            let scale = CGFloat(rep.pixelsWide) / window.contentView!.bounds.width
            // The toolbar's height: where the content area starts, from the window's top edge.
            let top = window.contentView!.bounds.height - window.contentLayoutRect.maxY
            XCTAssertGreaterThan(top, 30, "no toolbar")
            // Away from the toolbar items, in the detail column (the inspector doesn't render offscreen).
            for x in [450.0, 600] {
                let toolbar = rgb(rep, CGPoint(x: x, y: top / 2), scale: scale)
                let rule = rgb(rep, CGPoint(x: x, y: top - 0.5), scale: scale)
                let header = rgb(rep, CGPoint(x: x, y: top + 4), scale: scale)
                if x == 600 { headers.append(header) }
                print("topBar \(name) x=\(x): toolbar \(toolbar), toolbar's last row \(rule), header \(header)")
                // Steel, not paper or glass: blue above red, darker than the paper.
                XCTAssertGreaterThan(header[2], header[0], "header is not steel")
                XCTAssertLessThan(header[0], 0.5, "header is not steel")
                for i in 0..<3 {
                    XCTAssertEqual(toolbar[i], header[i], accuracy: 0.02, "a step between the toolbar and the header at x = \(x)")
                    XCTAssertEqual(rule[i], header[i], accuracy: 0.02, "a seam between the toolbar and the header at x = \(x)")
                }
            }
        }
        XCTAssertEqual(headers.count, 2)
        for i in 0..<3 where headers.count == 2 { XCTAssertEqual(headers[0][i], headers[1][i], accuracy: 0.01, "the gradient moved with the sidebar") }
    }
}
