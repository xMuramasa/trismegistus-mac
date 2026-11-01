import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window as laid out since #32: the toolbar's steel strip across the whole window, our own `sunken` sidebar column
/// (`SidebarSplit`) with a rule, the conversation header continuing the strip with the title rule under it, the chat
/// and its key hints, the terminal as our own trailing column (`TrailingSplit`). Rendered from the window's frame view (toolbar included) to
/// `.build/snapshots/Window32*.png`, sidebar open and closed.
@MainActor
final class TopBarTests: XCTestCase {
    private final class Panes: ObservableObject {
        @Published var sidebar = true
        @Published var width = 260.0
        @Published var terminal = true
        @Published var terminalWidth = 360.0
    }

    private struct Window: View {
        @ObservedObject var panes: Panes
        @State private var filter = ""

        var body: some View {
            SidebarSplit(isShown: $panes.sidebar, width: $panes.width) {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("Conversations // 6").typeRole(.label).foregroundStyle(Theme.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        EndfieldTextField("Filter", text: $filter, ground: Theme.paper)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    // As ConversationSidebar lays its rows out: no insets, no separators.
                    List {
                        Group {
                            SessionRowView(name: "Endfield gallery", source: .trismegistus, activity: "1 min", runElapsed: "00:42")
                            SessionRowView(name: "trismegistus-mac UI", source: .trismegistus, activity: "now", isSelected: true)
                            SessionRowView(name: "Morning news", source: .cron, activity: "9 h", isReadOnly: true)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    Text("macbook · paired").typeRole(.monoSmall).foregroundStyle(Theme.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
                }
            } detail: {
                // As in the app: the terminal as our own trailing column, inside the detail.
                TrailingSplit(isShown: $panes.terminal, width: $panes.terminalWidth) {
                    detail
                } pane: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("TERMINAL").typeRole(.label).foregroundStyle(Theme.onSteel).padding(.horizontal, 16).padding(.vertical, 10)
                        Rectangle().fill(Theme.onSteel.opacity(0.12)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.ink, ignoresSafeAreaEdges: [])
                }
            }
            .endfieldPaper()
            .topBar()
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Image(systemName: "sidebar.left").foregroundStyle(Theme.onSteel)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .navigation) { Text("Trismegistus").typeRole(.heading).foregroundStyle(Theme.onSteel) }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .primaryAction) {
                    Image(systemName: Symbol.terminal).foregroundStyle(Theme.onSteel)
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .toolbar(removing: .title)
        }

        /// Header (steel, with the subtitle), the title rule, the chat column on paper, the key hints.
        private var detail: some View {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Conversation title").typeRole(.title)
                        Text("trismegistus · run 7f3a · started 23:46").typeRole(.monoSmall).opacity(0.7)
                    }
                    Spacer(minLength: 0)
                    Text("≈ 92K / 1M · 9%").typeRole(.monoSmall).opacity(0.7)
                }
                .foregroundStyle(Theme.onSteel)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background { TopBarBackdrop().padding(.top, -1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.steelRule).frame(height: 1) }
                SegmentRule((48, 120, 24), height: 4, stretches: true)
                Text("chat").frame(maxWidth: 700, maxHeight: .infinity).background(Theme.paper)
                KeyHintStrip([("⌘↩", "send"), ("⌘⌥T", "terminal"), ("⌘K", "conversations")]).background(Theme.paper)
            }
            .background(EndfieldBackdrop())
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

    /// Grays come back lighter than their hex through the offscreen bitmap's colour profile (sunken 0xE5 reads as
    /// about 0xEA), so the checks compare grounds with each other.
    private func assertDarker(_ a: [CGFloat], than b: [CGFloat], _ what: String) {
        for i in 0..<3 { XCTAssertLessThan(a[i], b[i] - 0.02, "\(what): \(a) vs \(b)") }
    }

    private func assertSteel(_ c: [CGFloat], _ what: String) {
        // Steel, not paper or glass: blue above red, darker than the paper.
        XCTAssertGreaterThan(c[2], c[0], "\(what) is not steel: \(c)")
        XCTAssertLessThan(c[0], 0.5, "\(what) is not steel: \(c)")
    }

    func testWindowLayout() throws {
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
        for (shown, name) in [(true, "Window32SidebarOpen"), (false, "Window32SidebarClosed")] {
            withAnimation { panes.sidebar = shown }
            spin(1.5)
            let rep = try render(window.contentView!.superview!, name)
            let scale = CGFloat(rep.pixelsWide) / window.contentView!.bounds.width
            // The toolbar's height: where the content area starts, from the window's top edge.
            let top = window.contentView!.bounds.height - window.contentLayoutRect.maxY
            XCTAssertGreaterThan(top, 30, "no toolbar")

            // The strip runs from the window's left edge, above the sidebar too.
            assertSteel(rgb(rep, CGPoint(x: 150, y: top / 2), scale: scale), "\(name): toolbar above the sidebar")
            let low = window.contentView!.bounds.height - 60
            if shown {
                // One flat sunken column from under the toolbar to the bottom, darker than the chat's paper, then the
                // 1 pt rule at x = 260, darker again.
                let under = rgb(rep, CGPoint(x: 150, y: top + 2), scale: scale)
                let ground = rgb(rep, CGPoint(x: 150, y: low), scale: scale)
                let rule = rgb(rep, CGPoint(x: 260.5, y: low), scale: scale)
                let paper = rgb(rep, CGPoint(x: 600, y: low), scale: scale)
                print("window32 \(name): sidebar under the toolbar \(under), ground \(ground), rule \(rule), chat paper \(paper)")
                for i in 0..<3 { XCTAssertEqual(under[i], ground[i], accuracy: 0.01, "the sidebar is not one flat ground") }
                assertDarker(ground, than: paper, "\(name): sidebar ground against the paper")
                assertDarker(rule, than: ground, "\(name): sidebar rule against its ground")
                // The second row (selected) is white: under the 89 pt header and the first 52 pt row.
                assertDarker(ground, than: rgb(rep, CGPoint(x: 200, y: top + 89 + 52 + 26), scale: scale), "\(name): selected row")
            } else {
                assertSteel(rgb(rep, CGPoint(x: 150, y: top + 4), scale: scale), "\(name): header at the window's left")
            }

            // Away from the toolbar items, in the detail column.
            for x in [450.0, 600] {
                let toolbar = rgb(rep, CGPoint(x: x, y: top / 2), scale: scale)
                let rule = rgb(rep, CGPoint(x: x, y: top - 0.5), scale: scale)
                let header = rgb(rep, CGPoint(x: x, y: top + 4), scale: scale)
                if x == 600 { headers.append(header) }
                print("topBar \(name) x=\(x): toolbar \(toolbar), toolbar's last row \(rule), header \(header)")
                assertSteel(header, "\(name): header at x = \(x)")
                for i in 0..<3 {
                    XCTAssertEqual(toolbar[i], header[i], accuracy: 0.02, "a step between the toolbar and the header at x = \(x)")
                    XCTAssertEqual(rule[i], header[i], accuracy: 0.02, "a seam between the toolbar and the header at x = \(x)")
                }
            }
            // The terminal column (ours since the toolbar's items moved to the window's right edge): the strip runs on
            // above it into ink, and its own ground starts under the toolbar.
            let width = window.contentView!.bounds.width
            let aboveTerminal = rgb(rep, CGPoint(x: width - 180, y: top / 2), scale: scale)
            let terminalGround = rgb(rep, CGPoint(x: width - 180, y: low), scale: scale)
            print("window32 \(name): strip above the terminal \(aboveTerminal), terminal ground \(terminalGround)")
            XCTAssertLessThan(aboveTerminal[0], 0.2, "the strip doesn't reach ink above the terminal")
            XCTAssertLessThan(terminalGround[0], 0.15, "the terminal column isn't ink")
        }
        XCTAssertEqual(headers.count, 2)
        for i in 0..<3 where headers.count == 2 { XCTAssertEqual(headers[0][i], headers[1][i], accuracy: 0.01, "the gradient moved with the sidebar") }
    }
}
