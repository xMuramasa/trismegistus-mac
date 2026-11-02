import AppKit
import SwiftUI

/// The chat's message field (#47): an `NSTextView` that grows from one line (`Size.control`) up to `maxLines`, then
/// scrolls inside. Return and ⇧↩ insert a newline; ⌘↩ is left to the Send / Steer button's shortcut (AppKit offers key
/// equivalents before the text view's `keyDown`). Plain text: smart quotes and dashes, text replacement and
/// auto-correct are off (prompts carry commands and code); spell check is on. A grabber on the top edge drags it taller,
/// up to `maxHeight`: that height is its minimum until a double-click on the grabber returns it to auto-grow.
public struct Composer: View {
    /// The protocol's cap on a prompt or steer, in Unicode scalars (JSON Schema's `maxLength`, as the relay counts).
    public static let limit = 32_768
    /// From here a counter shows under the field.
    static let counterFrom = 30_000

    let placeholder: String
    @Binding var text: String
    let maxLines: CGFloat
    /// The height dragged with the grabber; 0 is auto-grow.
    @Binding var chosenHeight: Double
    let maxHeight: CGFloat
    var forceFocused = false  // snapshots: focus can't be set from outside
    @State private var lines = 1
    @State private var focused = false
    @State private var dragStart: CGFloat?
    @Environment(\.isEnabled) private var isEnabled

    public init(_ placeholder: String, text: Binding<String>, maxLines: CGFloat, chosenHeight: Binding<Double>, maxHeight: CGFloat) {
        self.placeholder = placeholder
        self._text = text
        self.maxLines = maxLines
        self._chosenHeight = chosenHeight
        self.maxHeight = maxHeight
    }

    public var body: some View {
        let height = Self.height(lines: lines, maxLines: maxLines, chosen: chosenHeight, limit: maxHeight)
        let isFocused = focused || forceFocused
        VStack(alignment: .trailing, spacing: Space.xs) {
            ComposerEditor(placeholder: placeholder, text: $text, lines: $lines, focused: $focused, isEnabled: isEnabled)
                .frame(height: height)
                .background(isFocused ? Ink.surface.raised : Ink.surface.sunken)
                .edge(isFocused ? Ink.line.strong : Ink.line.rule)
                .overlay(alignment: .top) { grabber(height) }
            if let counter = Self.counter(text) {
                Text(counter).typeRole(.monoSmall).foregroundStyle(Self.isOverLimit(text) ? Ink.status.error : Ink.text.secondary)
            }
        }
    }

    /// A short rule bar centred on the top edge; dragging up makes the field taller.
    private func grabber(_ height: CGFloat) -> some View {
        Rectangle().fill(Ink.line.rule).frame(width: Size.composer.grabber, height: Stroke.mark)
            .frame(maxWidth: .infinity).frame(height: Size.grip).contentShape(Rectangle())
            .alignmentGuide(.top) { $0[VerticalAlignment.center] }
            .pointerStyle(.rowResize)
            .gesture(
                // Global: the edge moves under the pointer, so a local translation would feed back.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = dragStart ?? height
                        dragStart = start
                        chosenHeight = Double(min(max(start - drag.translation.height, Size.control), maxHeight))
                    }
                    .onEnded { _ in dragStart = nil })
            .onTapGesture(count: 2) { chosenHeight = 0 }
            .accessibilityHidden(true)
    }

    // MARK: rules

    /// The body role's face, which the text view draws in.
    static let font: NSFont = {
        Fonts.register()
        let spec = TypeRole.body.spec
        return spec.family.faces[spec.weight].flatMap { NSFont(name: $0, size: spec.size) } ?? .systemFont(ofSize: spec.size)
    }()
    static let lineHeight = NSLayoutManager().defaultLineHeight(for: font)

    /// One line is `Size.control`; each line more adds a line up to `maxLines`. A dragged height (`chosen`, kept within
    /// `limit`) is the minimum.
    static func height(lines: Int, maxLines: CGFloat, chosen: Double, limit: CGFloat, lineHeight: CGFloat = lineHeight) -> CGFloat {
        let grown = Size.control + (min(CGFloat(max(lines, 1)), maxLines) - 1) * lineHeight
        return max(grown, min(CGFloat(chosen), limit))
    }

    /// `30,512 / 32,768` from `counterFrom` on, else nil.
    static func counter(_ text: String) -> String? {
        let count = text.unicodeScalars.count
        guard count >= counterFrom else { return nil }
        let style = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_US"))
        return "\(count.formatted(style)) / \(limit.formatted(style))"
    }

    /// Over the protocol's cap: Send is disabled.
    public static func isOverLimit(_ text: String) -> Bool { text.unicodeScalars.count > limit }

    /// What a draft sends: trimmed at both ends, inner newlines kept.
    public static func message(_ draft: String) -> String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The text view in a scroll view. It publishes its line count (wrapped lines included) for the current width; the
/// height it gets back never changes that width, so nothing loops (#28).
struct ComposerEditor: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    @Binding var lines: Int
    @Binding var focused: Bool
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ScrollView {
        let view = TextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isContinuousSpellCheckingEnabled = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.drawsBackground = false
        view.font = Composer.font
        view.textContainer?.lineFragmentPadding = 0
        // One line sits in the middle of `Size.control`.
        view.textContainerInset = NSSize(width: Space.m, height: (Size.control - Composer.lineHeight) / 2)
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.string = text
        let coordinator = context.coordinator
        view.onFocus = { [weak coordinator] focused in Task { @MainActor in coordinator?.editor.focused = focused } }
        view.onWidth = { [weak coordinator] view in Task { @MainActor in coordinator?.measure(view) } }
        let scroll = ScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        return scroll
    }

    func updateNSView(_ scroll: ScrollView, context: Context) {
        guard let view = scroll.documentView as? TextView else { return }
        let coordinator = context.coordinator
        coordinator.editor = self
        if view.placeholder != placeholder {
            view.placeholder = placeholder
            view.setAccessibilityPlaceholderValue(placeholder)
            view.needsDisplay = true
        }
        view.isEditable = isEnabled
        let color = NSColor(isEnabled ? Ink.text.primary : Ink.text.muted)
        if view.textColor != color {
            view.textColor = color
            view.insertionPointColor = color
            view.typingAttributes = [.font: Composer.font, .foregroundColor: color]
        }
        // Never while the input method composes: that would end the composition.
        if view.string != text, !view.hasMarkedText() {
            // Through the undo-registering path: ⌘Z after a send brings the text back.
            let all = NSRange(location: 0, length: (view.string as NSString).length)
            coordinator.updating = true
            if view.shouldChangeText(in: all, replacementString: text) {
                view.replaceCharacters(in: all, with: text)
                view.didChangeText()
            }
            coordinator.updating = false
            Task { @MainActor in coordinator.measure(view) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var editor: ComposerEditor
        /// Inside `updateNSView`: SwiftUI state can't change now.
        var updating = false

        init(_ editor: ComposerEditor) { self.editor = editor }

        func textDidChange(_ notification: Notification) {
            guard !updating, let view = notification.object as? TextView else { return }
            if editor.text != view.string { editor.text = view.string }
            // At once: a frame a line short would scroll the first line out of view for a moment.
            measure(view)
        }

        func measure(_ view: NSTextView) {
            guard let layout = view.layoutManager, let container = view.textContainer else { return }
            layout.ensureLayout(for: container)
            let lines = max(1, Int((layout.usedRect(for: container).height / Composer.lineHeight).rounded()))
            if editor.lines != lines { editor.lines = lines }
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertLineBreak(_:))
                || selector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
            else { return false }
            textView.insertNewline(nil)  // a plain "\n", never U+2028
            return true
        }
    }

    /// Keeps the text view as tall as the visible area, so a click anywhere in a dragged-taller field lands in it.
    final class ScrollView: NSScrollView {
        override func tile() {
            super.tile()
            guard let view = documentView as? NSTextView, view.minSize.height != contentSize.height else { return }
            view.minSize = NSSize(width: 0, height: contentSize.height)
            view.sizeToFit()
        }
    }

    /// Draws the placeholder while empty (marked text counts as text) and reports focus and width changes.
    final class TextView: NSTextView {
        var placeholder = ""
        var onFocus: (Bool) -> Void = { _ in }
        var onWidth: (TextView) -> Void = { _ in }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            guard string.isEmpty, let font else { return }
            NSAttributedString(string: placeholder, attributes: [.font: font, .foregroundColor: NSColor(Ink.text.secondary)])
                .draw(at: textContainerOrigin)
        }

        /// ⌘↩ is Send's (a key equivalent, offered first); when Send is disabled it does nothing rather than add a line.
        override func keyDown(with event: NSEvent) {
            if event.modifierFlags.contains(.command), ["\r", "\u{3}"].contains(event.charactersIgnoringModifiers) { return }
            super.keyDown(with: event)
        }

        override func didChangeText() {
            super.didChangeText()
            needsDisplay = true  // the placeholder comes and goes with the whole text
        }

        /// AppKit registers the text drag types when the edit settings change, before this view has a window; again here,
        /// or a dragged string never lands in it.
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateDragTypeRegistration()
        }

        override func setFrameSize(_ newSize: NSSize) {
            let widthChanged = newSize.width != frame.width
            super.setFrameSize(newSize)
            if widthChanged { onWidth(self) }
        }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became { onFocus(true) }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocus(false) }
            return resigned
        }
    }
}

#Preview("Composer") {
    @Previewable @State var text = "git log --oneline -5\nand tell me what changed"
    @Previewable @State var chosen = 0.0
    VStack {
        Composer("Message Hermes", text: .constant(""), maxLines: 10, chosenHeight: .constant(0), maxHeight: 300)
        Composer("Message Hermes", text: $text, maxLines: 10, chosenHeight: $chosen, maxHeight: 300)
    }
    .padding().frame(width: 360).background(Ink.surface.window)
}
