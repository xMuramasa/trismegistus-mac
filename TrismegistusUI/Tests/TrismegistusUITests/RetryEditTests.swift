import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// Retry and edit (#75, design 16 `#17-states` and `#17a`, frames `17-a3-retry-edit-states.png` and
/// `17a-a3-edit-in-place.png`). Writes `A3-Retry-*.png` and `A3-Edit-*.png`, and asserts the sizes and colours in the
/// pixels themselves.
extension WindowA3Tests {
    static let ask1 = "i already ran open, could you use cua-driver on my mac to test the ui?"
    static let ask2 = "go ahead i set it up a second screen for me to work while you check"

    /// A thumbnail for the chips: a flat grey-green square.
    static let thumbnail: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor(srgbRed: 0.4, green: 0.5, blue: 0.5, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 18, height: 18).fill()
        image.unlockFocus()
        return image
    }()

    static func answer(_ text: String) -> some View {
        MarkdownView([MarkdownPart<Int>.prose(MarkdownText.styled(text, role: .message))], role: .message) { _ in EmptyView() }
            .padding(.horizontal, Space.m)
    }

    /// The edit pencil's box: the label line's right end, hanging from its foot.
    private func actionBox(width: CGFloat, labelBottom: CGFloat, count: Int = 1) -> CGRect {
        let w = Size.messageAction.button * CGFloat(count) + Space.xs * CGFloat(count - 1)
        return CGRect(x: width - Space.l - w, y: labelBottom - Size.messageAction.button, width: w, height: Size.messageAction.button)
    }

    // MARK: 17 states

    /// Hover your message: the pencil at the end of its label line; without the pointer the line is bare.
    func testHoverYourMessage() throws {
        let width: CGFloat = 640
        func row(_ hover: Bool) -> some View {
            VStack(alignment: .leading, spacing: Space.xs) {
                MessageLabelLine("You // 13:52", showsActions: hover) { MessageActionButton("Edit and send again", symbol: Symbol.edit) {} }
                UserMessageText(Self.ask2)
            }
            .padding(Space.l).padding(.top, Space.l)
            .environment(\.hairlineControls, true)
        }
        let labelBottom = Space.xxxl + fitting(MessageLabel("You").environment(\.hairlineControls, true)).height
        let box = actionBox(width: width, labelBottom: labelBottom)
        let shown = try shot("Retry-hover-message", width: width, height: 110) { row(true) }
        XCTAssertTrue(shown.isColor(box.minX + 3, box.midY, Ink.surface.raised, tolerance: 0.02), "a white button \(shown.rgb(box.minX + 3, box.midY))")
        XCTAssertTrue(shown.contains(Ink.line.rule, in: CGRect(x: box.minX - 0.5, y: box.minY + 4, width: 1.5, height: 16), tolerance: 0.05), "its rule edge")
        XCTAssertTrue(shown.contains(Ink.text.primary, in: box.insetBy(dx: 5, dy: 5), tolerance: 0.25), "the ink pencil")
        let bare = try shot("Retry-hover-none", width: width, height: 110) { row(false) }
        XCTAssertTrue(bare.isColor(box.midX, box.midY, Ink.surface.window, tolerance: 0.01), "no button without the pointer")
        XCTAssertEqual(fitting(MessageActionButton("Edit", symbol: Symbol.edit) {}), CGSize(width: 24, height: 24))
    }

    /// Hover the last answer: copy and retry.
    func testHoverLastAnswer() throws {
        let width: CGFloat = 640
        let shot = try shot("Retry-hover-answer", width: width, height: 90) {
            VStack(alignment: .leading, spacing: Space.xs) {
                MessageLabelLine("Hermes // 14:01", showsActions: true) {
                    MessageActionButton("Copy answer", symbol: Symbol.copy) {}
                    MessageActionButton("Retry", symbol: Symbol.retry) {}
                }
                Self.answer("Done on the second screen only. The Settings window opens with ⌘, and its three tabs switch.")
            }
            .padding(Space.l).padding(.top, Space.l)
            .environment(\.hairlineControls, true)
        }
        let labelBottom = Space.xxxl + fitting(MessageLabel("Hermes").environment(\.hairlineControls, true)).height
        let both = actionBox(width: width, labelBottom: labelBottom, count: 2)
        XCTAssertTrue(shot.isColor(both.minX + 3, both.midY, Ink.surface.raised, tolerance: 0.02), "copy's white")
        XCTAssertTrue(shot.isColor(both.maxX - 3, both.midY, Ink.surface.raised, tolerance: 0.02), "retry's white")
        XCTAssertTrue(shot.isColor(both.minX + Size.messageAction.button + Space.xs / 2, both.midY, Ink.surface.window, tolerance: 0.01), "4 pt apart")
    }

    /// A failed run: FAILED in terminal red, a 3 pt red edge at the left, retry at the right.
    func testFailedRunRetry() throws {
        let width: CGFloat = 640
        let height = fitting(FailureRow("Hermes answered 529: the provider is overloaded.") {}.frame(width: width)).height
        XCTAssertEqual(height, Size.messageAction.button + 2 * Space.s, accuracy: 1, "the retry button sets the row's height")
        let shot = try shot("Retry-failed", width: width, height: height) {
            FailureRow("Hermes answered 529: the provider is overloaded.") {}.environment(\.hairlineControls, true)
        }
        XCTAssertTrue(shot.isColor(1.5, height / 2, Ink.status.bad, tolerance: 0.08), "the red edge \(shot.rgb(1.5, height / 2))")
        XCTAssertTrue(shot.isColor(Stroke.mark + 3, Space.s / 2, Ink.surface.raised, tolerance: 0.02), "white beside it")
        XCTAssertTrue(shot.contains(Ink.status.error, in: CGRect(x: Space.m, y: 0, width: 60, height: height), tolerance: 0.1), "FAILED in terminal red")
        XCTAssertTrue(shot.contains(Ink.text.primary, in: CGRect(x: width - Space.s - 20, y: Space.s + 4, width: 16, height: 16), tolerance: 0.25), "the retry glyph")
        let bare = try self.shot("Retry-failed-bare", width: width, height: height) { FailureRow("Run failed").environment(\.hairlineControls, true) }
        XCTAssertFalse(bare.contains(Ink.text.primary, in: CGRect(x: width - Space.s - 20, y: Space.s + 4, width: 16, height: 16), tolerance: 0.25), "no retry without an action")
    }

    /// Editing a message with images: the chips under the text, × on each; 3 later messages in the footer.
    func testEditorWithImages() throws {
        let width: CGFloat = 760
        let editor = MessageEditor(
            text: .constant("is this the right blur radius for the sidebar?"),
            chips: [.init(id: "a", name: "screenshot-1.png", thumbnail: Self.thumbnail), .init(id: "b", name: "Image", thumbnail: nil)],
            laterMessages: 3, removesAnswer: true, onCancel: {}, onSend: {})
        let shot = try shot("Edit-images", width: width, height: 150) { editor.environment(\.hairlineControls, true) }
        // Under the one-line editor (Size.control): a chip's thumbnail, 12 + 4 pt in.
        let chipY = Size.control + Size.messageAction.chip / 2
        XCTAssertTrue(shot.isColor(Space.m + Space.xs + 9, chipY, Color(red: 0.4, green: 0.5, blue: 0.5), tolerance: 0.06),
                      "the thumbnail \(shot.rgb(Space.m + Space.xs + 9, chipY))")
        XCTAssertTrue(shot.contains(Ink.line.rule, in: CGRect(x: Space.m, y: Size.control, width: 2, height: Size.messageAction.chip), tolerance: 0.05), "the chip's edge")
        XCTAssertEqual(MessageEditor.removal(laterMessages: 3, answer: true), "3 later messages and their answers are removed")
        XCTAssertEqual(MessageEditor.removal(laterMessages: 1, answer: true), "1 later message and its answer are removed")
        XCTAssertNil(MessageEditor.removal(laterMessages: 0, answer: false))
    }

    /// Not offered: during a run the label line has no actions, only WORKING under the message.
    func testNotOfferedDuringARun() throws {
        let width: CGFloat = 640
        let shot = try shot("Retry-not-offered", width: width, height: 130) {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabelLine("You // 13:52", showsActions: false) { MessageActionButton("Edit and send again", symbol: Symbol.edit) {} }
                    UserMessageText(Self.ask2)
                }
                WorkLine(detail: "00:38 · 2 tools") {}
            }
            .padding(Space.l).padding(.top, Space.l)
            .environment(\.hairlineControls, true)
        }
        let labelBottom = Space.xxxl + fitting(MessageLabel("You").environment(\.hairlineControls, true)).height
        let box = actionBox(width: width, labelBottom: labelBottom)
        XCTAssertFalse(shot.contains(Ink.surface.raised, in: box.insetBy(dx: 2, dy: 2), tolerance: 0.01), "no button")
    }

    // MARK: 17a

    /// The design's transcript with the second message in the editor and Hermes' answer after it dimmed.
    struct EditInPlace: View {
        let laterMessages: Int

        var body: some View {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel("You // 13:42")
                    UserMessageText(WindowA3Tests.ask1)
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel("Hermes // 13:49")
                    WindowA3Tests.answer("The cua-driver daemon is still running on your Mac. `cua-driver stop` ends it.")
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel("You // 13:52")
                    MessageEditor(
                        text: .constant("go ahead, but test on the second screen only and leave the main one alone"),
                        laterMessages: laterMessages, removesAnswer: true, onCancel: {}, onSend: {})
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel("Hermes // 14:01")
                    WindowA3Tests.answer("Done on the second screen only. The Settings window opens with ⌘, and its three tabs switch.")
                }
                .rewound(true)
            }
            .frame(maxWidth: Size.chatColumn)
            .padding(Space.l)
            .environment(\.hairlineControls, true)
        }
    }

    func testEditInPlace() throws {
        let width: CGFloat = 760
        for later in [0, 3] {
            TypeSpec.drawnWeights = []
            let height = fitting(EditInPlace(laterMessages: later).frame(width: width)).height
            let shot = try shot("Edit-in-place\(later == 0 ? "" : "-several")", width: width, height: height) { EditInPlace(laterMessages: later) }
            // The editor: an ink edge with the yellow inset inside it at the left.
            let ys = stride(from: CGFloat(0), to: height, by: 0.5)
            let inset = ys.filter { shot.isColor(Space.l + Stroke.hairline + 1, $0, Ink.selection, tolerance: 0.08) }
            XCTAssertGreaterThan(CGFloat(inset.count) / 2, Size.control + Size.control, "\(later): the yellow inset down the editor")
            let top = try XCTUnwrap(inset.first)
            XCTAssertTrue(shot.contains(Ink.line.strong, in: CGRect(x: width / 2, y: top - 2, width: 1, height: 2), tolerance: 0.08),
                          "\(later): the ink edge over it")
            // Send yellow in the footer at the right; the composer isn't here, so it is the only yellow.
            XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: Space.l + Size.chatColumn - 80, y: top, width: 70, height: 120)), "\(later): Send")
            // The dimmed answer: nothing in it darker than ink at 38 % over paper.
            let dimmed = CGRect(x: Space.l, y: height - Space.l - 40, width: 400, height: 40)
            let darkest = stride(from: dimmed.minX, to: dimmed.maxX, by: 1).flatMap { x in
                stride(from: dimmed.minY, to: dimmed.maxY, by: 1).map { shot.light(x, $0) }
            }.min() ?? 0
            XCTAssertGreaterThan(darkest, 0.45, "\(later): the answer after the editor is dimmed")
            XCTAssertLessThanOrEqual(TypeSpec.drawnWeights.max() ?? 0, 600)
        }
    }

    /// The editor takes the focus with the caret at the end; Esc cancels.
    func testEditorFocusAndEscape() throws {
        final class Taps { var cancel = 0 }
        let taps = Taps()
        let text = "go ahead, but test on the second screen only"
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: MessageEditor(
            text: .constant(text), laterMessages: 0, removesAnswer: true, onCancel: { taps.cancel += 1 }, onSend: {}))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let view = try XCTUnwrap(window.firstResponder as? NSTextView, "the editor has the focus")
        XCTAssertEqual(view.selectedRange(), NSRange(location: (text as NSString).length, length: 0), "the caret at the end")
        XCTAssertEqual(view.font?.pointSize, 14, "the message role")
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(taps.cancel, 1)
    }
}
