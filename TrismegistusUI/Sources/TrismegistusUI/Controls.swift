import SwiftUI

public enum EndfieldButtonKind: Sendable {
    case primary, secondary, danger, quiet
}

/// A chip with `m` corners (#68), a 1 px edge and a trailing SF Symbol. `iconOnly` hides the word but keeps it as tooltip
/// and accessibility label. Pressed inverts to ink with yellow text; disabled goes sunken and muted (dark-panel on steel).
/// On steel a secondary button has no fill and a light edge and word (`.btn.steel`, #57). In the window's list column a
/// quiet icon-only button is a sunken square with an ink glyph (`.ib`, a list header's action, #68).
public struct EndfieldButtonStyle: ButtonStyle {
    let kind: EndfieldButtonKind
    let title: String
    let symbol: String?
    let iconOnly: Bool

    public init(_ kind: EndfieldButtonKind = .secondary, title: String, symbol: String? = nil, iconOnly: Bool = false) {
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.iconOnly = iconOnly
    }

    public func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration, style: self)
    }

    private struct Chip: View {
        let configuration: ButtonStyleConfiguration
        let style: EndfieldButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.onSidebar) private var onSidebar
        @Environment(\.onSteel) private var onSteel

        private var isBlock: Bool { onSidebar && style.kind == .quiet && style.iconOnly }

        private var palette: (fill: Color, edge: Color, text: Color) {
            if !isEnabled {
                return onSteel ? (Ink.surface.darkPanel, Ink.text.secondary, Ink.text.onDark) : (Ink.surface.sunken, Ink.line.rule, Ink.text.muted)
            }
            if isBlock { return (configuration.isPressed ? Ink.line.rule : Ink.surface.sunken, .clear, Ink.text.primary) }
            if configuration.isPressed { return (Ink.surface.inverse, Ink.line.strong, Ink.selection) }
            switch style.kind {
            case .primary: return (Ink.selection, Ink.line.strong, Ink.text.primary)
            case .secondary: return onSteel ? (.clear, Ink.text.onDark, Ink.text.onDark) : (Ink.surface.raised, Ink.line.strong, Ink.text.primary)
            case .danger: return (Ink.surface.raised, Ink.text.error, Ink.text.error)
            // No ground of its own: light on the window sidebar's grey and on steel.
            case .quiet: return (.clear, .clear, onSidebar ? Ink.text.onSidebar : onSteel ? Ink.text.onDark : Ink.text.primary)
            }
        }

        var body: some View {
            let p = palette
            HStack(spacing: Space.s) {
                if !style.iconOnly { configuration.label.textCase(.uppercase).lineLimit(1) }
                // Beside the word the symbol is decoration: as its own element it read the label twice to VoiceOver
                // ("Looks good, Looks good"). Alone it carries the label and the tooltip.
                if let symbol = style.symbol {
                    Image(systemName: symbol).font(isBlock ? .system(size: Icon.section) : nil).accessibilityHidden(!style.iconOnly)
                }
            }
            // A button never wraps its word: in a tight row it keeps its size and the row has to make room.
            .fixedSize()
            .typeRole(.button)
            .foregroundStyle(p.text)
            .padding(.vertical, isBlock ? 0 : Space.s)
            .padding(.horizontal, isBlock ? 0 : style.iconOnly ? Space.s : Space.m)
            .frame(width: isBlock ? Size.control : nil, height: isBlock ? Size.control : nil)
            .rounded(Radius.m, fill: p.fill, edge: p.edge)
            .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            .help(style.title)
            .accessibilityLabel(style.title)
        }
    }
}

/// A `Button` wired to `EndfieldButtonStyle`.
public struct EndfieldButton: View {
    let title: String
    let symbol: String?
    let kind: EndfieldButtonKind
    let iconOnly: Bool
    let shortcut: KeyboardShortcut?
    let action: @MainActor () -> Void

    public init(
        _ title: String, symbol: String? = nil, kind: EndfieldButtonKind = .secondary, iconOnly: Bool = false,
        shortcut: KeyboardShortcut? = nil, action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.kind = kind
        self.iconOnly = iconOnly
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) { Text(title) }
            .buttonStyle(EndfieldButtonStyle(kind, title: title, symbol: symbol, iconOnly: iconOnly))
            .keyboardShortcut(shortcut)
    }
}

/// `.plain` text field in an `m` container: rest sunken with a rule edge, focused raised with an ink edge, error red.
/// In the window's list column: white with an ink edge and the soft ink shadow, yellow while focused (#65), and `hint`
/// (`⌘K`) as a key cap at its end.
public struct EndfieldTextField: View {
    let placeholder: String
    @Binding var text: String
    let isError: Bool
    /// The fill while not focused: `sunken`, or `paper` on a sunken ground (the window's sidebar).
    let ground: Color
    /// Focus from outside (the window's ⌘K focuses the sidebar's Filter field).
    let focus: FocusState<Bool>.Binding?
    let hint: String?
    var forceFocused = false  // snapshots and previews: focus can't be set from outside
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.onSidebar) private var onSidebar

    public init(
        _ placeholder: String, text: Binding<String>, isError: Bool = false, ground: Color = Ink.surface.sunken,
        focus: FocusState<Bool>.Binding? = nil, hint: String? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isError = isError
        self.ground = ground
        self.focus = focus
        self.hint = hint
    }

    public var body: some View {
        let isFocused = (focus?.wrappedValue ?? focused) || forceFocused
        HStack(spacing: Space.s) {
            TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Ink.text.secondary))
                .textFieldStyle(.plain)
                .typeRole(onSidebar ? .headline : .body)
                .foregroundStyle(isEnabled ? Ink.text.primary : Ink.text.muted)
                .focused(focus ?? $focused)
            if let hint { KeyCap(hint) }
        }
        .padding(.leading, Space.m).padding(.trailing, hint == nil ? Space.m : Space.xs)
        .frame(height: Size.control)
        // The shadow on the ground alone: over the field it would blur the text's glyphs inside it.
        .background {
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(isFocused || onSidebar ? Ink.surface.raised : ground)
                .shadow(!onSidebar ? Shadow.none : isFocused ? Shadow.blockFocus : Shadow.block)
        }
        .edge(isError ? Ink.text.error : isFocused || onSidebar ? Ink.line.strong : Ink.line.rule, radius: Radius.m)
    }
}

/// A shortcut as a key cap (`⌘K`, `kbd`): Inter on raised with a rule edge, `s` corners.
public struct KeyCap: View {
    let key: String

    public init(_ key: String) { self.key = key }

    public var body: some View {
        Text(verbatim: key).typeRole(.caption, weight: .semibold).foregroundStyle(Ink.text.secondary).lineLimit(1).fixedSize()
            .padding(.horizontal, Space.xs).padding(.vertical, Space.xxs)
            .rounded(Radius.s, fill: Ink.surface.raised, edge: Ink.line.rule)
            .accessibilityHidden(true)
    }
}

extension View {
    /// `.switch` toggle tinted ink (yellow fails contrast as a track on paper).
    public func endfieldSwitch() -> some View {
        toggleStyle(.switch).tint(Ink.surface.inverse)
    }
}

#Preview("Buttons") {
    HStack {
        EndfieldButton("Once", symbol: Symbol.check, kind: .primary) {}
        EndfieldButton("Session", symbol: Symbol.clock) {}
        EndfieldButton("Deny", symbol: Symbol.close, kind: .danger) {}
        EndfieldButton("Copy", symbol: Symbol.copy, kind: .quiet, iconOnly: true) {}
        EndfieldButton("Pair", symbol: Symbol.link) {}.disabled(true)
    }
    .padding().background(Ink.surface.window)
}

#Preview("Fields") {
    @Previewable @State var text = "Summarize the deploy log"
    VStack {
        EndfieldTextField("Message Hermes", text: .constant(""))
        EndfieldTextField("Message Hermes", text: $text)
        EndfieldTextField("Code", text: .constant("K7QF-2M9X-A1"), isError: true)
        Toggle("Launch at login", isOn: .constant(true)).endfieldSwitch()
    }
    .padding().frame(width: 320).background(Ink.surface.window)
}
