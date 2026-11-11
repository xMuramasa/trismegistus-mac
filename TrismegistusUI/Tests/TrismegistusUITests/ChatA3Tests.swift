import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window's chat in the a3 skin (#71, design 13 `#a3`, render `13e-a3-chat.png`): the transcript and the composer.
/// Writes `A3-Chat-*.png` next to #69's shots, and asserts the fills, colours and sizes in the pixels themselves.
extension WindowA3Tests {
    /// Hermes' answer from the render; `code` adds the code block (mono: kept out of the window's no-mono check).
    static func answer(code: Bool) -> [MarkdownPart<Int>] {
        let s = { MarkdownText.styled($0, role: .message) }
        var parts: [MarkdownPart<Int>] = [
            .prose(s("I’m testing through macOS accessibility in the background, so I haven’t taken over your screen.")),
            .prose(s("Checked and working:")),
            .list([
                MarkdownItem(.bullet, text: s("**#41, sections:** Chat, GitHub, Agents, Jobs and Commands each switch and show their list.")),
                MarkdownItem(.bullet, text: s("**#48, chat kinds:** App 10, Telegram 4, Terminal 9, One-shots 2, Cron 6.")),
            ]),
        ]
        if code {
            parts.append(.code(language: "bash", text: "$ cua-driver inspect --app Trismegistus --depth 2\n# the window's tree\nwindow   \"Trismegistus\"  1560×1122"))
        }
        parts.append(.prose(s("The cua-driver daemon is still running on your Mac. `cua-driver stop` ends it.")))
        return parts
    }

    /// Both message kinds, the commands chip (open: a run's calls under it as the a3 Commands rows, one failed), WORKING; laid out as
    /// `ChatView` lays out the window's transcript.
    struct Transcript: View {
        var code = true
        var chipOpen = false

        var body: some View {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel("You // 13:42")
                    UserMessageText("i already ran open, could you use cua-driver on my mac to test the ui?")
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel("Hermes // 13:49")
                    MarkdownView(WindowA3Tests.answer(code: code), role: .message) { _ in EmptyView() }.padding(.horizontal, Space.m)
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    CommandChip(commands: 4, duration: "6.1 s", isOpen: .constant(chipOpen))
                    if chipOpen {
                        TerminalEntryView(time: "13:49:02", tool: "terminal", command: "cua-driver inspect --app Trismegistus", exitCode: 0, duration: 1.2)
                        TerminalEntryView(time: "13:49:05", tool: "terminal", command: "unzip -l Inter-4.1.zip", exitCode: 127, duration: 0.1)
                    }
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel("You // 13:52")
                    UserMessageText("go ahead i set it up a second screen for me to work while you check")
                }
                WorkLine(detail: "00:38 · 2 tools") {}
            }
            .frame(maxWidth: Size.chatColumn)
            .padding(Space.l)
        }
    }

    static var approval: some View {
        ApprovalBannerView(
            tool: "terminal", command: "./gradlew assembleRelease", explanation: "Build the release APK for the Pixel.", onChoice: { _ in })
    }

    /// The composer as `ChatView` fills it: idle, running (Stop and Steer) or read-only.
    enum ComposerState: String, CaseIterable { case idle, running, readOnly }

    static func composer(_ state: ComposerState) -> some View {
        ComposerBlock(floating: true) {
            switch state {
            case .running: RunLine("Run active", isActive: true, clock: "00:38", hints: [(key: "⌘↩", action: "steer"), (key: "⌘.", action: "stop")])
            case .idle: RunLine("Ready", hints: [(key: "⌘↩", action: "send"), (key: "⌘K", action: "conversations")])
            case .readOnly: RunLine("Read-only", hints: [(key: "⌘K", action: "conversations")])
            }
        } input: {
            VStack(alignment: .leading, spacing: Space.s) {
                HStack(alignment: .bottom, spacing: Space.s) {
                    if state != .readOnly { EndfieldButton("Attach images", symbol: Symbol.attach, kind: .quiet, iconOnly: true) {} }
                    Composer(state == .running ? "Steer this run" : "Message Hermes", text: .constant(""), maxLines: 10, chosenHeight: .constant(0), maxHeight: 200)
                        .disabled(state == .readOnly)
                    if state == .running {
                        EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger, iconOnly: true) {}
                        EndfieldButton("Steer", symbol: Symbol.steer, kind: .primary) {}
                    } else {
                        EndfieldButton("Send", symbol: Symbol.send, kind: .primary, iconOnly: true) {}.disabled(state == .readOnly)
                    }
                }
                if state == .readOnly {
                    Text(verbatim: "Read-only: this conversation comes from telegram; reply there.").typeRole(.caption).foregroundStyle(Ink.text.secondary)
                }
            }
        }
        .environment(\.hairlineControls, true)
    }

    /// `white` at `alpha` over `ground`, as the pixel should read.
    private static func over(_ alpha: Double, _ ground: Color) -> CGFloat {
        let g = NSColor(ground).usingColorSpace(.sRGB)!.redComponent
        return CGFloat(alpha) + (1 - CGFloat(alpha)) * g
    }

    // MARK: Transcript

    func testTranscriptInA3() throws {
        TypeSpec.drawnWeights = []
        let work = fitting(WorkLine(detail: "00:38 · 2 tools") {}.environment(\.hairlineControls, true)).height
        for open in [false, true] {
            let transcript = Transcript(chipOpen: open).environment(\.hairlineControls, true)
            let height = fitting(transcript.frame(width: 760)).height
            let shot = try shot("Chat-Transcript\(open ? "-open" : "")", width: 760, height: height) { transcript }
            // The code block: its text 12 pt in from the answer's, which is 12 pt in from the column (16 pt in).
            let codeX = Space.l + Space.m + Space.m
            let ys = stride(from: CGFloat(0), to: height, by: 0.5)
            XCTAssertNotNil(ys.first { shot.isColor(600, $0, Ink.surface.sunken, tolerance: 0.01) }, "\(open): the code block's sunken ground")
            XCTAssertTrue(shot.contains(Ink.status.ok, in: CGRect(x: codeX - 1, y: 0, width: 9, height: height), tolerance: 0.12), "\(open): the prompt's green `$`")
            // WORKING's yellow line beside it, on its own row at the bottom, running to the column's end.
            let row = height - Space.l - work / 2
            XCTAssertTrue(stride(from: CGFloat(200), to: Space.l + Size.chatColumn, by: 0.5).contains { shot.isColor($0, row, Ink.selection, tolerance: 0.08) },
                          "\(open): WORKING's yellow line at y = \(row)")
        }
        XCTAssertLessThanOrEqual(TypeSpec.drawnWeights.max() ?? 0, 600, "weights drawn: \(TypeSpec.drawnWeights.sorted())")
    }

    /// Without its code block the transcript draws no mono; the code block is the one exception.
    func testTranscriptUsesMonoOnlyForCode() throws {
        TypeSpec.drawn = []
        _ = try shot("Chat-mono-check", width: 760, height: 700) { Transcript(code: false).environment(\.hairlineControls, true) }
        XCTAssertTrue(TypeSpec.drawn.contains(.ui))
        XCTAssertFalse(TypeSpec.drawn.contains(.mono), "a mono role in the transcript outside code")
    }

    func testLabelsAndMessagesAreA3Type() {
        // `YOU // 13:42`: 10 pt, as the popover's label, but tracked 0.14 em: wider.
        let label = MessageLabel("You // 13:42")
        XCTAssertGreaterThan(fitting(label.environment(\.hairlineControls, true)).width, fitting(label).width + 4)
        // Your message: one 14 pt line, 8 pt above and below (the popover's 13 pt line has 12).
        let line = NSLayoutManager().defaultLineHeight(for: NSFont(name: "Inter-Regular", size: 14)!)
        let you = fitting(UserMessageText("ok").environment(\.hairlineControls, true)).height
        XCTAssertEqual(you, line + 2 * Space.s, accuracy: 2)
        XCTAssertLessThan(you, fitting(UserMessageText("ok")).height)
        XCTAssertEqual(TypeRole.message.spec.size, 14)
        XCTAssertEqual(TypeRole.message.spec.weight, 400)
    }

    /// White at 85 %, the bullets `secondary` squares, the chip white at 70 %: on an ink ground the alphas show.
    func testFillsOverInk() throws {
        let ink = Ink.text.primary
        let you = try flat("Chat-you-on-ink", width: 300, height: 40, ground: ink) { UserMessageText("ok").environment(\.hairlineControls, true) }
        XCTAssertEqual(you.light(150, 18), Self.over(Opacity.message, ink), accuracy: 0.02, "your message: white at 85 %")
        let chip = try flat("Chat-chip-on-ink", width: 300, height: Size.cardHeader, ground: ink) {
            CommandChip(commands: 4, duration: "6.1 s", isOpen: .constant(false)).environment(\.hairlineControls, true)
        }
        XCTAssertEqual(chip.light(2, Size.cardHeader / 2), Self.over(Opacity.control, ink), accuracy: 0.03, "the chip: white at 70 %")
        let list = try flat("Chat-bullets", width: 300, height: 30) {
            MarkdownView([MarkdownPart<Int>.list([MarkdownItem(.bullet, text: MarkdownText.styled("item", role: .message))])], role: .message) { _ in EmptyView() }
                .environment(\.hairlineControls, true)
        }
        let bullet = CGRect(x: 0, y: 0, width: Size.bullet + 1, height: 20)
        XCTAssertTrue(list.contains(Ink.text.secondary, in: bullet, tolerance: 0.03), "a secondary bullet")
        XCTAssertFalse(list.contains(Ink.text.primary, in: bullet, tolerance: 0.05), "no ink bullet")
    }

    /// `pre .p` and `pre .c`: a shell prompt's `$` green, a comment line secondary; other languages stay plain.
    func testCodeHighlighting() {
        let code = "$ ls -la\n  # a comment\necho $HOME"
        let styled = CodeBlockView.highlighted(code, language: "bash")
        XCTAssertEqual(String(styled.characters), code, "the text unchanged")
        typealias Colour = AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute
        let colours = styled.runs.map { (String(styled[$0.range].characters), $0[Colour.self]) }
        XCTAssertEqual(colours.first?.0, "$")
        XCTAssertEqual(colours.first?.1, Ink.status.ok)
        XCTAssertTrue(colours.contains { $0.0.contains("# a comment") && $0.1 == Ink.text.secondary })
        XCTAssertTrue(colours.contains { $0.0.contains("echo $HOME") && $0.1 == nil }, "a `$` inside a line is no prompt")
        XCTAssertTrue(CodeBlockView.highlighted(code, language: "swift").runs.allSatisfy { $0[Colour.self] == nil })
        XCTAssertTrue(CodeBlockView.highlighted("# heading", language: nil).runs.allSatisfy { $0[Colour.self] == Ink.text.secondary })
    }

    func testWorkingOnOneLine() {
        let line = WorkLine(detail: "00:38 · 2 tools") {}
        XCTAssertLessThan(fitting(line.environment(\.hairlineControls, true)).height, fitting(line).height, "a3: the track beside WORKING, not under it")
    }

    // MARK: Approval

    func testApprovalBlock() throws {
        let size = fitting(Self.approval.frame(width: 600).environment(\.hairlineControls, true))
        TypeSpec.drawnWeights = []
        let shot = try flat("Chat-Approval", width: 600, height: size.height + 20) { Self.approval.environment(\.hairlineControls, true) }
        XCTAssertFalse(shot.contains(Ink.selection, in: CGRect(x: 20, y: 0, width: 560, height: 4)), "no yellow bar on top")
        XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: 0, y: 0, width: 200, height: size.height)), "Once stays yellow")
        XCTAssertTrue(shot.isColor(300, size.height + 6, Ink.surface.window, tolerance: 0.01), "no shadow under the block")
        XCTAssertTrue(shot.isColor(300, size.height - 0.5, Ink.line.rule, tolerance: 0.06), "the rule hairline \(shot.rgb(300, size.height - 0.5))")
        XCTAssertTrue(shot.contains(Ink.text.error, in: CGRect(x: 400, y: 0, width: 200, height: size.height), tolerance: 0.06), "Deny in red")
        XCTAssertLessThanOrEqual(TypeSpec.drawnWeights.max() ?? 0, 600)
    }

    // MARK: Composer

    func testComposerInA3() throws {
        let ink = Ink.text.primary
        for state in ComposerState.allCases {
            TypeSpec.drawn = []
            TypeSpec.drawnWeights = []
            let shot = try shot("Chat-Composer-\(state.rawValue)", width: 760, height: 120, ground: ink) {
                VStack(spacing: 0) {
                    Spacer()
                    Self.composer(state)
                }
            }
            // 8 pt in from the sides and the bottom; white at 82 % over the ground.
            XCTAssertEqual(shot.light(4, 100), NSColor(ink).usingColorSpace(.sRGB)!.redComponent, accuracy: 0.02, "\(state): the ground 8 pt in")
            XCTAssertEqual(shot.light(Space.s + 4, 120 - Space.s - 20), Self.over(Opacity.composer, ink), accuracy: 0.03, "\(state): white at 82 %")
            XCTAssertFalse(TypeSpec.drawn.contains(.mono), "\(state): no mono")
            XCTAssertLessThanOrEqual(TypeSpec.drawnWeights.max() ?? 0, 600, "\(state)")
        }
    }
}
