import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// Decorative backdrops take no clicks (#53). `EndfieldBackdrop` draws a window-sized image at minus its origin and
/// clips it; clipping doesn't clip hit testing, so the chat's backdrop, laid out below the conversation header, covered
/// the header and swallowed every click there (the model menu and ⋯ never opened). Clicked in an on-screen window.
@MainActor
final class BackdropHitTests: XCTestCase {
    final class Clicks: ObservableObject { var button = 0 }

    struct Layout: View {
        let clicks: Clicks
        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Button("Above") { clicks.button += 1 }.buttonStyle(.plain)
                    Spacer()
                    Menu { Button("Item") {} } label: { Text("Menu") }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                .padding(Space.l)
                .background(Ink.surface.raised)
                // Below the header, drawn after it: the chat with its backdrop.
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity).background { EndfieldBackdrop() }
            }
            .endfieldPaper()
        }
    }

    private func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func click(_ window: NSWindow, at point: NSPoint) {
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            if let event { window.sendEvent(event) }
        }
    }

    func testControlsAboveABackdropTakeClicks() throws {
        let clicks = Clicks()
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Layout(clicks: clicks))
        window.orderFront(nil)
        defer { window.close() }
        spin(0.6)  // the paper renders once the size has held for `Motion.settle`

        // Both only touched on the main queue.
        nonisolated(unsafe) var opened = 0
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { note in
            opened += 1
            guard let tracked = note.object as? NSMenu else { return }
            nonisolated(unsafe) let menu = tracked
            RunLoop.main.add(Timer(timeInterval: 0.2, repeats: false) { _ in menu.cancelTracking() }, forMode: .common)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        // The header row is at the top of the content view (AppKit: y from the bottom).
        let height = try XCTUnwrap(window.contentView).bounds.height
        let rowY = height - Space.l - 8
        click(window, at: NSPoint(x: Space.l + 12, y: rowY))
        spin(0.4)
        XCTAssertEqual(clicks.button, 1, "a button above the chat's backdrop took no click")

        click(window, at: NSPoint(x: 600 - Space.l - 16, y: rowY))
        spin(0.8)
        XCTAssertEqual(opened, 1, "a menu above the chat's backdrop didn't open")
    }
}
