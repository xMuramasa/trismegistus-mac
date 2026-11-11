import AppKit
import SwiftUI

/// Retry and edit (#75, design 16 `#17a`, `#17-states`): the hover actions on a message's label line, the failed run's
/// line with its retry, and the editor that takes a message's place.
extension Symbol {
    public static let edit = "pencil"
}

/// One hover action (`.hov`): 24 pt square, white with a rule hairline, `control` corners, a 13 pt glyph. Icon-only, the
/// word as tooltip and accessibility label.
public struct MessageActionButton: View {
    let title: String
    let symbol: String
    let action: @MainActor () -> Void

    public init(_ title: String, symbol: String, action: @escaping @MainActor () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: Icon.messageAction)).foregroundStyle(Ink.text.primary)
                .frame(width: Size.messageAction.button, height: Size.messageAction.button)
                .rounded(Radius.control, fill: Ink.surface.raised, edge: Ink.line.rule)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A turn's label (`YOU // 13:52`) with its actions at the end of the line while `showsActions` (the pointer is over the
/// message). They hang from the line's foot, so showing them moves nothing.
public struct MessageLabelLine<Actions: View>: View {
    let label: String
    let showsActions: Bool
    let actions: Actions

    public init(_ label: String, showsActions: Bool, @ViewBuilder actions: () -> Actions) {
        self.label = label
        self.showsActions = showsActions
        self.actions = actions()
    }

    public var body: some View {
        MessageLabel(label)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                // Hidden, not removed: VoiceOver still reaches them.
                HStack(spacing: Space.xs) { actions }.opacity(showsActions ? 1 : 0).allowsHitTesting(showsActions)
            }
    }
}

/// A failed run's line (`.fail`): white with a rule hairline and a 3 pt red left edge, `FAILED` in tracked caps, the
/// reason, and Retry at the right when the run can be sent again.
public struct FailureRow: View {
    let message: String
    let onRetry: (@MainActor () -> Void)?

    public init(_ message: String, onRetry: (@MainActor () -> Void)? = nil) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Text(verbatim: "Failed").typeRole(.trackedLabel).foregroundStyle(Ink.status.error)
            Text(message).typeRole(.body).foregroundStyle(Ink.text.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onRetry { MessageActionButton("Retry", symbol: Symbol.retry, action: onRetry) }
        }
        .padding(.vertical, Space.s).padding(.leading, Space.m).padding(.trailing, Space.s)
        .background(Ink.surface.raised)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.status.bad).frame(width: Stroke.mark) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .edge(Ink.line.rule, radius: Radius.control)
    }
}

/// Your message as an editor in its place (`.edit`): white, an ink edge, a 3 pt yellow inset at the left; the text
/// editable (the composer's text view: undo, spell check, input methods), focused with the caret at the end; the
/// message's images as chips (× drops one); a footer saying what sending removes, Cancel (Esc) and the yellow Send (⌘↩).
public struct MessageEditor: View {
    /// An image that comes along.
    public struct Chip: Identifiable {
        public let id: String
        public let name: String
        public let thumbnail: NSImage?

        public init(id: String, name: String, thumbnail: NSImage?) {
            self.id = id
            self.name = name
            self.thumbnail = thumbnail
        }
    }

    @Binding var text: String
    let chips: [Chip]
    let laterMessages: Int
    let removesAnswer: Bool
    let onRemove: @MainActor (String) -> Void
    let onCancel: @MainActor () -> Void
    let onSend: @MainActor () -> Void
    @State private var lines = 1
    @State private var focused = false

    public init(
        text: Binding<String>, chips: [Chip] = [], laterMessages: Int, removesAnswer: Bool,
        onRemove: @escaping @MainActor (String) -> Void = { _ in }, onCancel: @escaping @MainActor () -> Void,
        onSend: @escaping @MainActor () -> Void
    ) {
        self._text = text
        self.chips = chips
        self.laterMessages = laterMessages
        self.removesAnswer = removesAnswer
        self.onRemove = onRemove
        self.onCancel = onCancel
        self.onSend = onSend
    }

    static let font = Composer.face(.message)

    /// The footer's bold part: what sending from here removes; nil when nothing follows.
    public static func removal(laterMessages: Int, answer: Bool) -> String? {
        switch laterMessages {
        case 0: answer ? "Hermes' answer below is removed" : nil
        case 1: "1 later message and its answer are removed"
        default: "\(laterMessages) later messages and their answers are removed"
        }
    }

    private var canSend: Bool {
        (!Composer.message(text).isEmpty || !chips.isEmpty) && !Composer.isOverLimit(text)
    }

    public var body: some View {
        let editor = ComposerEditor(
            placeholder: "", text: $text, lines: $lines, focused: $focused, isEnabled: true, focusRequests: 0,
            font: Self.font, focusOnAppear: true, onCancel: onCancel)
        let height = Composer.height(
            lines: lines, maxLines: Size.composer.windowLines, chosen: 0, limit: .infinity, lineHeight: editor.lineHeight)
        VStack(alignment: .leading, spacing: 0) {
            editor.frame(height: height)
            if !chips.isEmpty {
                HStack(spacing: Space.s) { ForEach(chips) { chip($0) } }
                    .padding(.horizontal, Space.m).padding(.bottom, Space.s)
            }
            Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
            HStack(spacing: Space.s) {
                // Wraps rather than truncates: the files note is the part that must be read (it was cut to "stay as they...").
                footer.typeRole(.callout).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCancel) {
                    HStack(spacing: Space.s) {
                        Text(verbatim: "Cancel")
                        KeyCap("esc")
                    }
                }
                .buttonStyle(EditorButtonStyle(primary: false))
                .help("Cancel (Esc)")
                Button(action: onSend) {
                    HStack(spacing: Space.s) {
                        Text(verbatim: "Send")
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(EditorButtonStyle(primary: true))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSend)
                .help("Send (⌘↩)")
            }
            .padding(.vertical, Space.s).padding(.leading, Space.m).padding(.trailing, Space.s)
        }
        .background(Ink.surface.raised)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.selection).frame(width: Stroke.mark) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .edge(Ink.line.strong, radius: Radius.control)
    }

    private var footer: Text {
        let tail = AttributedString(". Files it changed stay as they are.")
        guard let removal = Self.removal(laterMessages: laterMessages, answer: removesAnswer) else {
            return Text(AttributedString("Sends from here") + tail)
        }
        var bold = AttributedString(removal)
        bold.font = TypeRole.callout.spec.font(weight: .semibold)
        bold.foregroundColor = Ink.text.primary
        return Text(AttributedString("Sends from here: ") + bold + tail)
    }

    private func chip(_ chip: Chip) -> some View {
        HStack(spacing: Space.s) {
            Group {
                if let thumbnail = chip.thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFill()
                } else {
                    Ink.surface.sunken
                }
            }
            .frame(width: Size.messageAction.thumb, height: Size.messageAction.thumb)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
            Text(verbatim: chip.name).typeRole(.callout).foregroundStyle(Ink.text.secondary).lineLimit(1)
            Button { onRemove(chip.id) } label: {
                Image(systemName: Symbol.close).font(.system(size: Icon.xs, weight: .semibold)).foregroundStyle(Ink.text.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove \(chip.name)")
            .accessibilityLabel("Remove \(chip.name)")
        }
        .padding(.horizontal, Space.xs)
        .frame(height: Size.messageAction.chip)
        .rounded(Radius.control, fill: Ink.surface.raised, edge: Ink.line.rule)
    }
}

extension View {
    /// What sending from the open editor removes, dimmed to 38 % (`.dim`).
    public func rewound(_ on: Bool) -> some View { opacity(on ? Opacity.rewound : 1) }
}

/// `.btnw`: 30 pt, white with a rule edge, `control` corners, the word as written; the primary yellow and 600.
private struct EditorButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let fill = !isEnabled ? Ink.surface.sunken : configuration.isPressed ? Ink.line.rule : primary ? Ink.selection : Ink.surface.raised
        configuration.label
            .typeRole(.body, weight: primary ? .semibold : nil)
            .foregroundStyle(isEnabled ? Ink.text.primary : Ink.text.muted)
            .fixedSize()
            .padding(.horizontal, Space.m)
            .frame(height: Size.control)
            .rounded(Radius.control, fill: fill, edge: primary && isEnabled ? Ink.selection : Ink.line.rule)
            .contentShape(Rectangle())
    }
}

#Preview("Retry and edit") {
    @Previewable @State var text = "go ahead, but test on the second screen only and leave the main one alone"
    VStack(alignment: .leading, spacing: Space.xl) {
        MessageLabelLine("You // 13:52", showsActions: true) { MessageActionButton("Edit and send again", symbol: Symbol.edit) {} }
        MessageLabelLine("Hermes // 14:01", showsActions: true) {
            MessageActionButton("Copy answer", symbol: Symbol.copy) {}
            MessageActionButton("Retry", symbol: Symbol.retry) {}
        }
        FailureRow("Hermes answered 529: the provider is overloaded.") {}
        MessageEditor(text: $text, laterMessages: 0, removesAnswer: true, onCancel: {}, onSend: {})
    }
    .padding().frame(width: 640).background(Ink.surface.window)
    .environment(\.hairlineControls, true)
}
