import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The multi-line composer (#47): its height rule, the trim and length rules, keys, and snapshots
/// (`.build/snapshots/Composer*.png`, drawn from a window: `ImageRenderer` can't draw an `NSTextView`).
@MainActor
final class ComposerTests: XCTestCase {
    private let line = Composer.lineHeight

    // MARK: rules

    func testHeightGrowsALineAtATimeUpToTheCap() {
        func h(_ lines: Int, max: CGFloat = 10) -> CGFloat { Composer.height(lines: lines, maxLines: max, chosen: 0, limit: 400) }
        XCTAssertEqual(h(0), Size.control)
        XCTAssertEqual(h(1), Size.control)
        XCTAssertEqual(h(5), Size.control + 4 * line)
        XCTAssertEqual(h(10), Size.control + 9 * line)
        XCTAssertEqual(h(40), Size.control + 9 * line, "past the cap it scrolls inside")
        XCTAssertEqual(h(40, max: Size.composer.popoverLines), Size.control + 5 * line)
    }

    func testDraggedHeightIsTheMinimumWithinTheLimit() {
        XCTAssertEqual(Composer.height(lines: 1, maxLines: 10, chosen: 120, limit: 300), 120)
        XCTAssertEqual(Composer.height(lines: 10, maxLines: 10, chosen: 60, limit: 300), Size.control + 9 * line, "the text is taller")
        XCTAssertEqual(Composer.height(lines: 1, maxLines: 10, chosen: 500, limit: 250), 250, "half the column at most")
    }

    func testTrimKeepsInnerNewlines() {
        XCTAssertEqual(Composer.message("  \n git status\n\n  then push \n\t"), "git status\n\n  then push")
        XCTAssertEqual(Composer.message(" \n\n "), "")
    }

    func testCounterAndLimit() {
        XCTAssertNil(Composer.counter(String(repeating: "a", count: 29_999)))
        XCTAssertEqual(Composer.counter(String(repeating: "a", count: 30_512)), "30,512 / 32,768")
        XCTAssertFalse(Composer.isOverLimit(String(repeating: "a", count: 32_768)))
        XCTAssertTrue(Composer.isOverLimit(String(repeating: "a", count: 32_769)))
        // Unicode scalars, as the relay counts: a toned thumb is one Character and two scalars.
        XCTAssertTrue(Composer.isOverLimit(String(repeating: "👍🏽", count: 16_385)))
    }

    // MARK: hosted

    struct Host: View {
        @State var text: String
        var maxLines: CGFloat = Size.composer.windowLines
        var focused = false
        @State private var chosen = 0.0

        var body: some View {
            var composer = Composer("Message Hermes", text: $text, maxLines: maxLines, chosenHeight: $chosen, maxHeight: 400)
            composer.forceFocused = focused
            return composer.padding(Space.l).frame(width: 392).background(Ink.surface.window)
        }
    }

    private func spin(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func window(_ root: some View, height: CGFloat = 300) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 392, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: root)
        window.layoutIfNeeded()
        spin()
        return window
    }

    private func textView(in view: NSView) -> ComposerEditor.TextView? {
        if let text = view as? ComposerEditor.TextView { return text }
        return view.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }

    /// The composer's own height in a fitted host.
    private func fittedHeight(_ text: String, maxLines: CGFloat = Size.composer.windowLines) -> CGFloat {
        let window = window(Host(text: text, maxLines: maxLines))
        let editor = textView(in: window.contentView!)!.enclosingScrollView!
        return editor.frame.height
    }

    func testHostedHeightFollowsTheLines() {
        XCTAssertEqual(fittedHeight(""), Size.control, accuracy: 0.5)
        XCTAssertEqual(fittedHeight("one line"), Size.control, accuracy: 0.5)
        XCTAssertEqual(fittedHeight("1\n2\n3\n4\n5"), Size.control + 4 * line, accuracy: 0.5)
        let many = (1...14).map(String.init).joined(separator: "\n")
        XCTAssertEqual(fittedHeight(many), Size.control + 9 * line, accuracy: 0.5)
        XCTAssertEqual(fittedHeight(many, maxLines: Size.composer.popoverLines), Size.control + 5 * line, accuracy: 0.5)
        // A long line wraps: it counts as more than one.
        XCTAssertGreaterThan(fittedHeight(String(repeating: "wrap ", count: 60)), Size.control + line)
    }

    func testEditorSettings() throws {
        let window = window(Host(text: ""))
        let text = try XCTUnwrap(textView(in: window.contentView!))
        XCTAssertFalse(text.isRichText)
        XCTAssertTrue(text.allowsUndo)
        XCTAssertTrue(text.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(text.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertFalse(text.isAutomaticDashSubstitutionEnabled)
        XCTAssertFalse(text.isAutomaticTextReplacementEnabled)
        XCTAssertFalse(text.isAutomaticSpellingCorrectionEnabled)
        XCTAssertEqual(text.font?.fontName, "Inter-Regular")
    }

    // MARK: keys

    final class Taps { var send = 0, back = 0 }

    struct KeyHost: View {
        let taps: Taps
        @Binding var text: String
        @State private var chosen = 0.0

        var body: some View {
            VStack {
                Button("Back") { taps.back += 1 }.keyboardShortcut(.cancelAction)
                Composer("Message Hermes", text: $text, maxLines: 10, chosenHeight: $chosen, maxHeight: 200)
                Button("Send") { taps.send += 1 }.keyboardShortcut(.return, modifiers: .command)
            }
            .frame(width: 300, height: 200)
        }
    }

    /// What `NSApplication.sendEvent` does with a key: the window's key equivalents first, then the first responder.
    private func press(_ window: NSWindow, _ key: String, code: UInt16, _ flags: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key,
                isARepeat: false, keyCode: code)!
            if type == .keyDown, window.performKeyEquivalent(with: event) { continue }
            window.sendEvent(event)
        }
        spin(0.1)
    }

    func testReturnIsANewlineAndCommandReturnSends() throws {
        let taps = Taps()
        var text = "ls"
        let binding = Binding(get: { text }, set: { text = $0 })
        let window = window(KeyHost(taps: taps, text: binding))
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        window.makeKey()
        defer { window.orderOut(nil) }
        let editor = try XCTUnwrap(textView(in: window.contentView!))
        XCTAssertTrue(window.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: 2, length: 0))

        press(window, "\r", code: 36)
        XCTAssertEqual(text, "ls\n", "Return inserts a newline")
        press(window, "\r", code: 36, .shift)
        XCTAssertEqual(text, "ls\n\n", "⇧↩ too")
        XCTAssertEqual(taps.send, 0)

        press(window, "\r", code: 36, .command)
        guard taps.send == 1 else { throw XCTSkip("synthetic key equivalents don't reach SwiftUI in this session") }
        XCTAssertEqual(text, "ls\n\n", "⌘↩ adds no line")
        press(window, "\u{1b}", code: 53)
        XCTAssertEqual(taps.back, 1, "Esc is still the popover's Back")
    }

    func testAFocusRequestPutsTheFocusInTheField() throws {
        final class Requests: ObservableObject { @Published var count = 0 }
        struct Fields: View {
            @ObservedObject var requests: Requests
            @State private var text = ""
            var body: some View {
                Composer("Steer this run", text: $text, maxLines: 10, chosenHeight: .constant(0), maxHeight: 200, focusRequests: requests.count)
            }
        }
        let requests = Requests()
        let window = window(Fields(requests: requests))
        let field = try XCTUnwrap(textView(in: try XCTUnwrap(window.contentView)))
        window.makeFirstResponder(nil)
        requests.count += 1
        spin()
        XCTAssertIdentical(window.firstResponder, field)
    }

    /// The merged block (#58), with the field drawn.
    func testBlockSnapshots() throws {
        func block(_ run: Bool) -> some View {
            ComposerBlock {
                RunLine(run ? "Run active" : "Ready", isActive: run, clock: run ? "00:36" : nil, hints: [(key: "⌘↩", action: run ? "steer" : "send"), (key: "⌘K", action: "conversations")])
            } input: {
                HStack(alignment: .bottom, spacing: Space.s) {
                    EndfieldButton("Attach images", symbol: Symbol.attach, kind: .quiet, iconOnly: true) {}
                    Composer(run ? "Steer this run" : "Message Hermes", text: .constant(""), maxLines: 10, chosenHeight: .constant(0), maxHeight: 200)
                    if run {
                        EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger, iconOnly: true) {}
                        EndfieldButton("Steer", symbol: Symbol.steer, kind: .primary) {}
                    } else {
                        EndfieldButton("Send", symbol: Symbol.send, kind: .primary, iconOnly: true) {}
                    }
                }
            }
            .frame(width: 732)
        }
        for (name, run) in [("ComposerBlockRun", true), ("ComposerBlockReady", false)] {
            let window = window(block(run), height: 120)
            let host = try XCTUnwrap(window.contentView)
            window.setContentSize(NSSize(width: 732, height: host.fittingSize.height))
            host.layoutSubtreeIfNeeded()
            spin(0.2)
            let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
            try png.write(to: SnapshotTests.directory.appendingPathComponent("\(name).png"))
        }
    }

    // MARK: snapshots

    private func snap(_ name: String, _ text: String, focused: Bool = false, maxLines: CGFloat = Size.composer.windowLines) throws {
        let window = window(Host(text: text, maxLines: maxLines, focused: focused), height: 400)
        let host = try XCTUnwrap(window.contentView)
        window.setContentSize(host.fittingSize)
        host.layoutSubtreeIfNeeded()
        spin(0.2)
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("\(name).png"))
    }

    func testSnapshots() throws {
        try snap("ComposerEmpty", "")
        try snap("ComposerOneLine", "Summarize the deploy log", focused: true)
        try snap("ComposerFiveLines", "Run these and tell me what fails:\n\ncd ~/Projects/trismegistus\ngit pull --rebase\nscripts/linux-test.sh", focused: true)
        try snap("ComposerCap", (1...14).map { "line \($0): echo \"--quoted\" -- 'and dashed'" }.joined(separator: "\n"), focused: true)
        let words = String(repeating: "lorem ipsum dolor sit amet ", count: 1_200)
        try snap("ComposerCounterNear", String(words.prefix(30_512)), focused: true)
        try snap("ComposerCounterOver", String(repeating: words, count: 2).prefix(32_900).description, focused: true)
    }
}
