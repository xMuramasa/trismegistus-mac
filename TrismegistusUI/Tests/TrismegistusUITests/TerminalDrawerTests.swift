import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The terminal button per section, the drawer's height, and the shipped drawer rendered through AppKit (the emulator is
/// an `NSView`, which `ImageRenderer` leaves out) to `.build/snapshots/TerminalDrawer*.png`.
@MainActor
final class TerminalDrawerTests: XCTestCase {
    private func rgb(_ rep: NSBitmapImageRep, x: Int, y: Int) -> [CGFloat] {
        let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
        return [c?.redComponent ?? -1, c?.greenComponent ?? -1, c?.blueComponent ?? -1]
    }

    private func contains(_ rep: NSBitmapImageRep, where match: ([CGFloat]) -> Bool) -> Bool {
        (0..<rep.pixelsHigh).contains { y in (0..<rep.pixelsWide).contains { x in match(rgb(rep, x: x, y: y)) } }
    }

    /// The drawer in a real window, at the stored height.
    private func snapshot(_ name: String, height: Double, _ fill: (TerminalScreen) -> Void) throws -> NSBitmapImageRep {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: TerminalDrawer.heightKey)
        defaults.set(height, forKey: TerminalDrawer.heightKey)
        defer { defaults.set(previous, forKey: TerminalDrawer.heightKey) }

        let screen = TerminalScreen()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: VStack(spacing: 0) {
            Spacer(minLength: 0)
            TerminalDrawer(screen: screen)
        })
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        fill(screen)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let content = try XCTUnwrap(window.contentView)
        let rep = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("\(name).png"))
        return rep
    }

    func testButtonPerSection() {
        for section in WindowSection.allCases {
            for open in [false, true] {
                let toggle = TerminalToggle(section: section, isOpen: open) {}
                XCTAssertEqual(toggle.isAvailable, section == .chat, "\(section)")
                XCTAssertEqual(toggle.isPressed, section == .chat && open, "\(section), open \(open)")
                XCTAssertEqual(toggle.help, section == .chat ? "Toggle terminal (⌘⌥T)" : "The terminal pane is Chat only")
            }
        }
    }

    func testHeightClamp() {
        XCTAssertEqual(TerminalDrawer.clamped(0), 120)
        XCTAssertEqual(TerminalDrawer.clamped(119), 120)
        XCTAssertEqual(TerminalDrawer.clamped(300), 300)
        XCTAssertEqual(TerminalDrawer.clamped(9000), 480)
    }

    /// Opens at the stored height, kept within the clamp.
    func testHeightIsRemembered() throws {
        for (stored, shown) in [(300.0, 300), (9000, 480)] as [(Double, Int)] {
            let rep = try snapshot("TerminalDrawerHeight\(shown)", height: stored) { _ in }
            let scale = rep.pixelsHigh / 520
            let x = rep.pixelsWide / 2
            let ground = rgb(rep, x: x, y: rep.pixelsHigh - 2)
            let inside = rgb(rep, x: x, y: rep.pixelsHigh - (shown - 2) * scale)
            let above = rgb(rep, x: x, y: rep.pixelsHigh - (shown + 2) * scale)
            for i in 0..<3 {
                XCTAssertEqual(inside[i], ground[i], accuracy: 0.02, "the drawer is shorter than \(shown) pt")
            }
            XCTAssertNotEqual(above[0], ground[0], accuracy: 0.02, "the drawer is taller than \(shown) pt")
        }
    }

    func testDrawerOpen() throws {
        let rep = try snapshot("TerminalDrawerOpen", height: Double(Size.terminalDrawer.default)) { screen in
            screen.feed(Data("""
                \u{1B}[92mmuramasa@optiplex\u{1B}[0m:\u{1B}[94m~\u{1B}[0m$ hostname\r
                optiplex\r
                \u{1B}[92mmuramasa@optiplex\u{1B}[0m:\u{1B}[94m~\u{1B}[0m$ ls ~/Projects\r
                \u{1B}[1;34mhomelab\u{1B}[0m  \u{1B}[1;34mtrismegistus\u{1B}[0m  \u{1B}[1;34mtrismegistus-mac\u{1B}[0m\r
                \u{1B}[31mred\u{1B}[0m \u{1B}[32mgreen\u{1B}[0m \u{1B}[33myellow\u{1B}[0m \u{1B}[34mblue\u{1B}[0m \u{1B}[35mmagenta\u{1B}[0m \u{1B}[36mcyan\u{1B}[0m\r
                \u{1B}[92mmuramasa@optiplex\u{1B}[0m:\u{1B}[94m~\u{1B}[0m$\u{20}
                """.utf8))
        }
        // No seam: the emulator's empty area is the padding's ground. Greys read lighter through the offscreen bitmap's
        // profile, so these compare with each other.
        let ground = rgb(rep, x: 4, y: rep.pixelsHigh - 4)
        let empty = rgb(rep, x: rep.pixelsWide - 120, y: rep.pixelsHigh - 120)
        for i in 0..<3 { XCTAssertEqual(ground[i], empty[i], accuracy: 0.01, "the emulator's ground isn't dark-panel") }
        // Our green, #00FFA2, thinned by antialiasing: blue above the ground, which SwiftTerm's own (0, 255, 0) wouldn't be.
        XCTAssertTrue(contains(rep) { $0[1] > $0[0] + 0.25 && $0[1] > $0[2] + 0.1 && $0[2] > 0.4 }, "no green prompt")
        XCTAssertTrue(contains(rep) { $0[2] > 0.8 && $0[0] < 0.65 && $0[1] < 0.8 }, "no blue directory")
    }

    func testDrawerRefusal() throws {
        var shown: TerminalScreen?
        let rep = try snapshot("TerminalDrawerRefusal", height: Double(Size.terminalDrawer.default)) { screen in
            shown = screen
            screen.notice("this device has no terminal grant; on the server: devices terminal macbook on")
            screen.notice("the terminal helper isn't running\nThe terminal helper isn't running on optiplex: systemctl --user start trismegistus-term")
            screen.notice("[shell ended · exit 0]")
        }
        // Each notice on its own line, none written over another (SwiftTerm's soft reset homes the cursor).
        let terminal = try XCTUnwrap(shown).view.getTerminal()
        let text = (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
        XCTAssertEqual(text.filter { $0.contains("no terminal grant") }.count, 1, "\(text)")
        XCTAssertEqual(text.filter { $0.hasPrefix("[shell ended · exit 0]") && $0.count == "[shell ended · exit 0]".count }.count, 1, "\(text)")
        // Muted: text is drawn, and none of it is as bright as on-steel.
        let ground = rgb(rep, x: 4, y: rep.pixelsHigh - 4)
        XCTAssertTrue(contains(rep) { $0[0] > ground[0] + 0.2 }, "no text")
        XCTAssertFalse(contains(rep) { $0[0] > 0.8 }, "a notice isn't muted")
    }

    /// A shell lost inside a full-screen program: the notice lands on the main screen, under what was there.
    func testNoticeLeavesTheAlternateScreen() {
        let screen = TerminalScreen()
        screen.view.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        screen.feed(Data("before\r\n\u{1B}[?1049hinside vim".utf8))
        let terminal = screen.view.getTerminal()
        XCTAssertTrue(terminal.isCurrentBufferAlternate)
        screen.notice("[connection lost]")
        XCTAssertFalse(terminal.isCurrentBufferAlternate)
        let text = (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }
        XCTAssertEqual(Array(text.prefix(2)), ["before", "[connection lost]"], "\(text)")
    }

    /// Hiding the drawer drops its SwiftUI view; the emulator stays the caller's, keeps taking output and comes back whole.
    func testHidingKeepsTheScreen() {
        final class Drawer: ObservableObject { @Published var isShown = true }
        struct Host: View {
            @ObservedObject var drawer: Drawer
            let screen: TerminalScreen
            var body: some View {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if drawer.isShown { TerminalDrawer(screen: screen) }
                }
            }
        }
        let screen = TerminalScreen()
        let drawer = Drawer()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 520), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Host(drawer: drawer, screen: screen))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        let spin = { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
        spin()
        XCTAssertNotNil(screen.view.window)
        let size = screen.size
        XCTAssertGreaterThan(size.cols, 80)
        var resizes = 0
        screen.onResize = { _, _ in resizes += 1 }

        drawer.isShown = false
        spin()
        XCTAssertNil(screen.view.window)
        screen.feed(Data("while hidden".utf8))

        drawer.isShown = true
        spin()
        XCTAssertNotNil(screen.view.window)
        XCTAssertEqual(screen.size.cols, size.cols)
        XCTAssertEqual(screen.size.rows, size.rows)
        XCTAssertEqual(resizes, 0, "hiding the drawer reached the shell as a resize")
        let line = screen.view.getTerminal().getLine(row: 0)?.translateToString(trimRight: true)
        XCTAssertEqual(line, "while hidden")
    }

    func testResizeReachesTheCaller() throws {
        let screen = TerminalScreen()
        var last: (cols: Int, rows: Int)?
        screen.onResize = { last = ($0, $1) }
        screen.view.setFrameSize(NSSize(width: 400, height: 120))
        let size = try XCTUnwrap(last)
        XCTAssertEqual(size.cols, screen.size.cols)
        XCTAssertEqual(size.rows, screen.size.rows)
        print("terminal: 400x120 pt is \(size.cols)x\(size.rows)")
        XCTAssertGreaterThan(size.rows, 1)
    }

    func testInputAndScrollback() {
        let screen = TerminalScreen()
        var input = Data()
        screen.onInput = { input.append($0) }
        screen.send(source: screen.view, data: ArraySlice(Data("ls\r".utf8)))
        XCTAssertEqual(input, Data("ls\r".utf8))

        screen.feed(Data(String(repeating: "line\r\n", count: 12_000).utf8))
        XCTAssertEqual(screen.view.getTerminal().buffer.yDisp, TerminalScreen.scrollback)
    }
}
