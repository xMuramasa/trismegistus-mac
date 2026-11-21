import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The chat stays visible and at the bottom while the composer under it grows or shrinks (#52), as a conversation's
/// history arrives, and when something appears above it (Martin, 2026-11-21). `Chat` puts varied rows in a `TailStack`
/// and a `Composer` in `DockedScroll`, as `ChatView` does.
///
/// With the composer stacked under the scroll view instead (`docked: false`, the layout before the fix), every line
/// shrank the scroll view; the lazy stack re-estimated its height and the bottom anchor either fell behind or landed
/// where no rows were laid out: a blank viewport (`ink` 0.00, 0 rows laid out) until a scroll.
@MainActor
final class ChatScrollTests: XCTestCase {
    final class ChatState: ObservableObject {
        @Published var text = ""
        @Published var chosen = 0.0
        @Published var conversation = "a"
        @Published var rows = 150
        /// Real conversations: mostly short rows, now and then a huge one (a code answer, an image): see `extra`.
        @Published var spread = false
        /// Something above the messages (an approval banner, the find bar), laid over the scroll view's top.
        @Published var banner: CGFloat = 0
        /// Rows the lazy stack has laid out, in its own coordinates.
        var laidOut: [String: CGRect] = [:]
    }

    struct Chat: View {
        @ObservedObject var chat: ChatState
        let compact: Bool
        let docked: Bool
        @State private var columnHeight: CGFloat = 0

        /// Deterministic and varied: 4…63 words a row.
        static func words(_ id: String) -> Int { 4 + id.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 9973 } % 60 }

        /// With `spread`: conversation `a` has a 1600 pt row every 13 rows, `b` a 2400 pt one every 41, the rest none.
        static func extra(_ id: String) -> CGFloat {
            guard let n = Int(id.drop { !$0.isNumber }) else { return 0 }
            switch id.first {
            case "a": return n % 13 == 5 ? 1600 : 0
            case "b": return n % 41 == 7 ? 2400 : 0
            default: return 0
            }
        }

        private func row(_ id: String) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(repeating: "word \(id) ", count: Self.words(id)))
                    .typeRole(.body).foregroundStyle(Ink.surface.window)
                if chat.spread { Color.clear.frame(height: Self.extra(id)) }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.text.primary)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: { [chat] in chat.laidOut[id] = $0 }
            .onDisappear { [chat] in chat.laidOut[id] = nil }
        }

        private var ids: [String] { (0..<chat.rows).map { "\(chat.conversation)\($0)" } }

        /// As `ChatView`: the newest rows in full under a lazy stack of the older ones (`TailStack`).
        private var rows: some View {
            let ids = self.ids
            let split = ChatTail.split(ids.count)
            return TailStack(spacing: compact ? Space.m : Space.xl) {
                ForEach(ids[..<split], id: \.self) { row($0) }
            } tail: {
                ForEach(ids[split...], id: \.self) { row($0) }
            }
            .coordinateSpace(.named("rows"))
            .padding(compact ? Space.l : Space.xl)
            .frame(maxWidth: Size.chatColumn)
            .frame(maxWidth: .infinity)
        }

        private var input: some View {
            ComposerBlock {
                RunLine("Run active", isActive: true, clock: "00:36")
            } input: {
                Composer(
                    "Message Hermes", text: $chat.text, maxLines: compact ? Size.composer.popoverLines : Size.composer.windowLines,
                    chosenHeight: $chat.chosen, maxHeight: columnHeight / 2)
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                if docked {
                    // The real layout: ChatView uses this view.
                    DockedScroll { rows } top: {
                        if chat.banner > 0 { Color.red.frame(height: chat.banner) }
                    } dock: { input }
                } else {
                    ScrollView { rows }
                        .defaultScrollAnchor(.bottom)
                        .defaultScrollAnchor(.bottom, for: .sizeChanges)
                        .settledWidth()
                    input
                }
            }
            .background(Ink.surface.window)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { columnHeight = $0 }
        }
    }

    /// One measurement of the chat's scroll view.
    struct Step: CustomStringConvertible {
        let label: String, composer: CGFloat, document: CGFloat, top: CGFloat, bottom: CGFloat
        /// The share of the visible part (above the composer) that is row ink: the rows are dark blocks.
        let ink: Double
        /// Laid-out rows over the visible rect.
        let laidOut: Int
        var shows: Bool { ink > 0.2 && laidOut > 0 }
        var atBottom: Bool { abs(document - bottom) <= 2 }
        var description: String {
            String(format: "%@: composer %5.1f, document %7.1f, visible %7.1f…%7.1f (%5.1f short of the bottom), ink %.2f, %d rows laid out",
                   label, composer, document, top, bottom, document - bottom, ink, laidOut)
        }
    }

    private func spin(_ seconds: Double = 0.3) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func window(_ chat: ChatState, compact: Bool, docked: Bool = true) -> NSWindow {
        window(Chat(chat: chat, compact: compact, docked: docked), compact: compact)
    }

    /// On screen, far off the visible area: the display cycle runs as in the app (fully offscreen, nothing went blank).
    private func window(_ root: some View, compact: Bool) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: compact ? 360 : 700, height: compact ? 560 : 600), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: root)
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        addTeardownBlock { @MainActor in window.orderOut(nil) }
        spin(0.5)
        return window
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    /// The chat's scroll view (the composer has its own).
    private func chatScroll(_ window: NSWindow) throws -> NSScrollView {
        try XCTUnwrap(scrollViews(in: window.contentView!).first { !($0 is ComposerEditor.ScrollView) })
    }

    private func measure(_ window: NSWindow, _ chat: ChatState, compact: Bool, _ label: String) throws -> Step {
        let host = try XCTUnwrap(window.contentView)
        let scroll = try chatScroll(window)
        let editor = try XCTUnwrap(scrollViews(in: host).first { $0 is ComposerEditor.ScrollView })
        let visible = scroll.documentVisibleRect
        // Only the part above the composer shows (the host is flipped).
        var rect = scroll.convert(scroll.bounds, to: host)
        let input = editor.convert(editor.bounds, to: host)
        if input.minY < rect.maxY { rect.size.height = input.minY - Space.l - rect.minY }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: rect))
        host.cacheDisplay(in: rect, to: rep)
        var dark = 0, total = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                total += 1
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.brightnessComponent < 0.5 { dark += 1 }
            }
        }
        let pad = (compact ? Space.l : Space.xl) + chat.banner
        let rows = chat.laidOut.values.map { $0.offsetBy(dx: 0, dy: pad) }
        return Step(
            label: label, composer: editor.frame.height, document: scroll.documentView?.frame.height ?? 0,
            top: visible.minY, bottom: visible.maxY, ink: Double(dark) / Double(max(total, 1)),
            laidOut: rows.filter { $0.intersects(visible) }.count)
    }

    private static func lines(_ n: Int) -> String { (0..<n).map { "line \($0 + 1)" }.joined(separator: "\n") }

    /// At the bottom: typing to 10 lines a line at a time, a 30-line paste, Send clearing it, the grabber dragged up and
    /// double-clicked back.
    private func grow(compact: Bool, conversation: String) throws -> [Step] {
        let chat = ChatState()
        chat.conversation = conversation
        let window = window(chat, compact: compact)
        var steps = [try measure(window, chat, compact: compact, "open")]
        for n in Array(1...10) + [30, 0] {
            chat.text = Self.lines(n)
            spin()
            steps.append(try measure(window, chat, compact: compact, "\(n) lines"))
        }
        for chosen in [200.0, 0] {
            chat.chosen = chosen
            spin()
            steps.append(try measure(window, chat, compact: compact, "dragged to \(Int(chosen))"))
        }
        return steps
    }

    func testStaysVisibleAtTheBottomWhileTheComposerGrows() throws {
        for compact in [false, true] {
            // Five conversations: where the estimate goes wrong depends on the rows' heights.
            for seed in 0..<5 {
                for step in try grow(compact: compact, conversation: "s\(seed)-") {
                    let at = "\(compact ? "popover" : "window"), conversation \(seed), \(step)"
                    XCTAssertTrue(step.shows, "rows show: \(at)")
                    XCTAssertTrue(step.atBottom, "at the bottom: \(at)")
                }
            }
        }
    }

    /// Fixed content, so the document's height is exact: it ends the merged block's height (run line, input line,
    /// padding, rule) further down, at any height of the field.
    func testTheContentIsPaddedByTheBlocksHeight() throws {
        final class Block: ObservableObject {
            @Published var text = ""
            var height: CGFloat = 0
        }
        struct Fixed: View {
            @ObservedObject var block: Block

            var body: some View {
                DockedScroll {
                    Color.clear.frame(height: 2000)
                } dock: {
                    ComposerBlock {
                        RunLine("Run active", isActive: true, clock: "00:36")
                    } input: {
                        Composer("Steer this run", text: $block.text, maxLines: Size.composer.windowLines, chosenHeight: .constant(0), maxHeight: 300)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { [block] in block.height = $0 }
                }
            }
        }
        let block = Block()
        let window = window(Fixed(block: block), compact: false)
        let scroll = try chatScroll(window)
        var heights: [CGFloat] = []
        for n in [1, 5, 10] {
            block.text = Self.lines(n)
            spin()
            XCTAssertEqual(scroll.documentView?.frame.height ?? 0, 2000 + block.height, accuracy: 1, "\(n) lines")
            heights.append(block.height)
        }
        XCTAssertEqual(heights, heights.sorted(), "the block grows with the field")
        XCTAssertGreaterThan(heights[0], Space.xl + Space.s + Size.control + 2 * Space.m - 1, "the run line is part of it")
    }

    func testScrolledUpItStaysWhereItWas() throws {
        for compact in [false, true] {
            let chat = ChatState()
            let window = window(chat, compact: compact)
            let scroll = try chatScroll(window)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: (scroll.documentView?.frame.height ?? 0) / 2))
            scroll.reflectScrolledClipView(scroll.contentView)
            spin()
            let start = try measure(window, chat, compact: compact, "scrolled up")
            for n in 1...10 {
                chat.text = Self.lines(n)
                spin()
                let step = try measure(window, chat, compact: compact, "\(n) lines")
                XCTAssertTrue(step.shows, "\(step)")
                XCTAssertEqual(step.top, start.top, accuracy: 2, "not pulled down: \(step)")
            }
        }
    }

    func testNewMessagesAndAnotherConversationLandAtTheBottom() throws {
        for compact in [false, true] {
            let chat = ChatState()
            let window = window(chat, compact: compact)
            chat.text = Self.lines(5)
            spin()
            for _ in 1...3 {
                chat.rows += 1
                spin()
                let step = try measure(window, chat, compact: compact, "a new message")
                XCTAssertTrue(step.shows && step.atBottom, "\(step)")
            }
            chat.conversation = "b"
            chat.rows = 80
            spin(0.5)
            let step = try measure(window, chat, compact: compact, "another conversation")
            XCTAssertTrue(step.shows && step.atBottom, "\(step)")
        }
    }

    /// Rows of very different heights (one-line chips, then a long code answer or an image), and a switch to a
    /// conversation not opened yet: no rows for a frame, the Loading row while its history comes, then all of it. With
    /// every row lazy, the stack's height estimate was far off and the bottom anchor landed in it: a blank chat with a
    /// long empty scroll, until a scroll (Martin, 2026-11-21). The newest rows are laid out in full (`TailStack`).
    func testAConversationWhoseHistoryArrivesLandsAtTheBottom() throws {
        for compact in [false, true] {
            let chat = ChatState()
            chat.spread = true
            chat.conversation = "a"
            chat.rows = 300
            let window = window(chat, compact: compact)
            for (next, count) in [("b", 300), ("c", 120), ("a", 260), ("b", 200)] {
                chat.conversation = next
                chat.rows = 0
                spin(0.016)
                chat.rows = 1 // the Loading row
                spin(0.3)
                chat.rows = count
                spin(0.6)
                let step = try measure(window, chat, compact: compact, "\(compact ? "popover" : "window"), opened \(next)")
                XCTAssertTrue(step.shows && step.atBottom, "\(step)")
            }
        }
    }

    /// An approval banner or the find bar appearing above the messages: they lie over the scroll view, which keeps its
    /// height, so the chat stays at the bottom. Beside it, every change knocked the chat off the bottom, further with
    /// each new message.
    func testABannerAboveKeepsTheChatAtTheBottom() throws {
        let chat = ChatState()
        let window = window(chat, compact: false)
        for height in [60.0, 4, 44] {
            chat.banner = height
            spin()
            chat.rows += 1
            spin(0.6)
            let shown = try measure(window, chat, compact: false, "banner \(Int(height)), a new message")
            XCTAssertTrue(shown.shows && shown.atBottom, "\(shown)")
            chat.banner = 0
            spin(0.6)
            let gone = try measure(window, chat, compact: false, "banner \(Int(height)) gone")
            XCTAssertTrue(gone.shows && gone.atBottom, "\(gone)")
        }
    }
}
