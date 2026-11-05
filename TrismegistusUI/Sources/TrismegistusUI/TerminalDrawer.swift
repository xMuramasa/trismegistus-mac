import AppKit
import SwiftTerm
import SwiftUI

/// The terminal's emulator: one SwiftTerm view fed by the caller, not a local process. It outlives the drawer, so hiding
/// the drawer keeps the screen and its 10,000 lines of scrollback.
@MainActor
public final class TerminalScreen: @preconcurrency TerminalViewDelegate {
    /// Keystrokes, pastes and the emulator's own replies.
    public var onInput: (Data) -> Void = { _ in }
    public var onResize: (_ cols: Int, _ rows: Int) -> Void = { _, _ in }

    static let scrollback = 10_000
    static let font: NSFont = {
        Fonts.register()
        let spec = TypeRole.mono.spec
        return spec.family.faces[spec.weight].flatMap { NSFont(name: $0, size: spec.size) } ?? .monospacedSystemFont(ofSize: spec.size, weight: .regular)
    }()

    let view: TerminalView

    public init() {
        // About the drawer's size: the first shell opens before the drawer's first layout, which then resizes it.
        view = TerminalView(frame: NSRect(x: 0, y: 0, width: Size.chatColumn, height: Size.terminalDrawer.default), font: Self.font)
        view.terminalDelegate = self
        view.nativeBackgroundColor = NSColor(Ink.surface.darkPanel)
        view.nativeForegroundColor = NSColor(Ink.text.onDark)
        view.caretColor = NSColor(Ink.selection)
        view.selectedTextBackgroundColor = NSColor(Ink.text.secondary)
        view.installColors(Ink.ansi.map(Self.ansi))
        view.getTerminal().changeHistorySize(Self.scrollback)
    }

    private static func ansi(_ color: SwiftUI.Color) -> SwiftTerm.Color {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return SwiftTerm.Color(red: UInt16(c.redComponent * 65535), green: UInt16(c.greenComponent * 65535), blue: UInt16(c.blueComponent * 65535))
    }

    public var size: (cols: Int, rows: Int) {
        let terminal = view.getTerminal()
        return (terminal.cols, terminal.rows)
    }

    public func feed(_ bytes: Data) { view.feed(byteArray: ArraySlice(bytes)) }

    /// A muted line (or lines) from the app, out of whatever the ended shell left on: the alternate screen, colours.
    public func notice(_ text: String) {
        let lines = text.replacingOccurrences(of: "\n", with: "\r\n")
        let terminal = view.getTerminal()
        // Leaving the alternate screen restores the cursor saved on entering it; sent on the main screen, it homed the
        // cursor and each notice overwrote the one before (review, 2026-11-04). So only when a program left it on.
        if terminal.isCurrentBufferAlternate { view.feed(text: "\u{1B}[?1049l") }
        // A soft reset (colours, modes, scroll region) may move the cursor too: put it back, then a fresh line.
        let at = terminal.getCursorLocation()
        view.feed(text: "\u{1B}[!p\u{1B}[\(at.y + 1);\(at.x + 1)H" + (at.x > 0 ? "\r\n" : "") + "\u{1B}[90m\(lines)\u{1B}[0m\r\n")
    }

    public func focus() { view.window?.makeFirstResponder(view) }

    public func send(source: TerminalView, data: ArraySlice<UInt8>) { onInput(Data(data)) }
    public func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { onResize(newCols, newRows) }
    public func setTerminalTitle(source: TerminalView, title: String) {}
    public func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    public func scrolled(source: TerminalView, position: Double) {}
    public func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    /// OSC 52: a program on the host doesn't get to write the Mac's clipboard.
    public func clipboardCopy(source: TerminalView, content: Data) {}
}

/// The terminal under the chat, the detail column's full width on `dark-panel`. Dragging the top edge sets the height,
/// 120-480 pt, kept under `heightKey`.
public struct TerminalDrawer: View {
    public static let heightKey = "window.terminalHeight"

    let screen: TerminalScreen
    @AppStorage(Self.heightKey) private var height = Double(Size.terminalDrawer.default)
    @State private var dragStart: Double?

    public init(screen: TerminalScreen) { self.screen = screen }

    static func clamped(_ height: Double) -> Double { min(max(height, Size.terminalDrawer.min), Size.terminalDrawer.max) }

    public var body: some View {
        Host(screen: screen)
            .padding(.vertical, Space.m).padding(.horizontal, Space.l)
            .frame(maxWidth: .infinity)
            .frame(height: Self.clamped(height))
            .background(Ink.surface.darkPanel)
            .overlay(alignment: .top) { edge }
            // A task: the view is in the window by then.
            .task { screen.focus() }
    }

    private var edge: some View {
        Color.clear.frame(height: Size.grip).contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .gesture(
                // Dragging up raises the drawer. Global: the edge moves under the pointer.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? Self.clamped(height)
                        dragStart = start
                        height = Self.clamped(start - drag.translation.height)
                    }
                    .onEnded { _ in dragStart = nil })
            .accessibilityHidden(true)
    }

    /// The emulator in a box of its own. SwiftUI sizes a hosted view down as it leaves and comes back, and every size
    /// reaches the shell: the box passes on real sizes only, and the emulator leaves it before it goes.
    private struct Host: NSViewRepresentable {
        final class Box: NSView {
            override func resizeSubviews(withOldSize oldSize: NSSize) {
                if !bounds.isEmpty { subviews.first?.frame = bounds }
            }
        }

        let screen: TerminalScreen

        func makeNSView(context: Context) -> Box {
            let box = Box()
            box.addSubview(screen.view)
            return box
        }

        func updateNSView(_ box: Box, context: Context) {}

        static func dismantleNSView(_ box: Box, coordinator: ()) {
            box.subviews.first?.removeFromSuperview()
        }
    }
}
