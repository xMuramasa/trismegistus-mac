import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The background is drawn once per window size: opening or closing a pane must not redraw it (#28, #29).
@MainActor
final class EndfieldBackgroundTests: XCTestCase {
    private final class Panes: ObservableObject {
        @Published var inspector = true
    }

    private struct Window: View {
        @ObservedObject var panes: Panes
        var body: some View {
            NavigationSplitView {
                List(0..<20, id: \.self) { Text("Conversation \($0)") }
            } detail: {
                Text("No conversation selected")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EndfieldBackdrop())
                    .inspector(isPresented: $panes.inspector) {
                        Text("Terminal").inspectorColumnWidth(min: 280, ideal: 360, max: 560)
                    }
            }
            .endfieldPaper()
        }
    }

    private func spin(_ seconds: Double) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    func testSnapshot() throws {
        let renderer = ImageRenderer(content: EndfieldBackground().frame(width: 1100, height: 700).environment(\.colorScheme, .light))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "EndfieldBackground did not render")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("EndfieldBackground.png"))
        XCTAssertEqual(image.width, 2200)
        XCTAssertEqual(image.height, 1400)
    }

    func testDrawsOncePerWindowSize() {
        EndfieldPaper.renderCount = 0
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                              styleMask: [.titled, .resizable, .closable], backing: .buffered, defer: false)
        let panes = Panes()
        window.contentView = NSHostingView(rootView: Window(panes: panes))
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        spin(1.5)
        XCTAssertEqual(EndfieldPaper.renderCount, 1, "one render at start")

        for _ in 0..<2 {
            withAnimation { panes.inspector.toggle() }
            spin(1.5)
            XCTAssertEqual(EndfieldPaper.renderCount, 1, "toggling the inspector redrew the background")
        }

        window.setContentSize(NSSize(width: 900, height: 650))
        spin(1.5)
        XCTAssertEqual(EndfieldPaper.renderCount, 2, "one render after a resize")
        spin(1.0)
        XCTAssertEqual(EndfieldPaper.renderCount, 2, "keeps rendering while idle")
    }
}
