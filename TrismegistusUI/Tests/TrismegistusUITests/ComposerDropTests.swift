import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The composer under #45's drop target (#47): over the editor, AppKit still gives a file drag to the drop target in
/// front, and a text drag to the editor's text view (the target registers no text type).
@MainActor
final class ComposerDropTests: XCTestCase {
    struct Column: View {
        @State private var text = ""
        @State private var chosen = 0.0

        var body: some View {
            VStack(spacing: 0) {
                Spacer()
                Composer("Message Hermes", text: $text, maxLines: 10, chosenHeight: $chosen, maxHeight: 150).padding(Space.l)
            }
            .frame(width: 400, height: 300)
            .imageDrop(room: 4, limit: 4, refusal: nil, later: false) { _, _ in }
        }
    }

    /// `-[NSView _hitTest:dragTypes:]`, AppKit's own lookup of a drag's destination (private: tests only).
    private func dragDestination(_ window: NSWindow, at point: NSPoint, _ types: [NSPasteboard.PasteboardType]) throws -> NSView? {
        let frame = try XCTUnwrap(window.contentView?.superview)
        let selector = NSSelectorFromString("_hitTest:dragTypes:")
        guard frame.responds(to: selector) else { throw XCTSkip("AppKit no longer has _hitTest:dragTypes:") }
        typealias Lookup = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSPoint>, AnyObject) -> AnyObject?
        let lookup = unsafeBitCast(frame.method(for: selector), to: Lookup.self)
        var p = point
        return lookup(frame, selector, &p, NSSet(array: types.map(\.rawValue))) as? NSView
    }

    func testFilesGoToTheDropTargetTextToTheEditor() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Column())
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        // What a drag of a string and of a file carry: the UTIs (`public.utf8-plain-text`, `public.file-url`) and
        // their legacy names, which NSTextView registers.
        let board = NSPasteboard(name: .init("trismegistus-test-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("git status", forType: .string)
        let text = try XCTUnwrap(board.types)
        XCTAssertTrue(text.contains(.string))
        board.clearContents()
        board.writeObjects([URL(fileURLWithPath: "/tmp/shot.png")] as [NSURL])
        let file = try XCTUnwrap(board.types)
        XCTAssertTrue(file.contains(.fileURL))
        // The editor sits Space.l above the bottom, `Size.control` tall: its middle, left and right of centre.
        for x in [40.0, 200, 360] {
            let p = NSPoint(x: x, y: Space.l + Size.control / 2)
            XCTAssertTrue(try dragDestination(window, at: p, file) is ImageDropTarget.DropView, "file at \(x)")
            XCTAssertTrue(try dragDestination(window, at: p, text) is ComposerEditor.TextView, "text at \(x)")
        }
    }
}
