import SwiftUI

public enum EndfieldButtonKind: Sendable {
    case primary, secondary, danger, quiet
}

/// Square chip with a 1 px edge and a trailing SF Symbol. `iconOnly` hides the word but keeps it as tooltip and
/// accessibility label. Pressed inverts to ink with yellow text; disabled goes sunken and muted.
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

        private var palette: (fill: Color, edge: Color, text: Color) {
            if !isEnabled { return (Theme.sunken, Theme.rule, Theme.muted) }
            if configuration.isPressed { return (Theme.ink, Theme.ink, Theme.yellow) }
            switch style.kind {
            case .primary: return (Theme.yellow, Theme.ink, Theme.ink)
            case .secondary: return (Theme.raised, Theme.ink, Theme.ink)
            case .danger: return (Theme.raised, Theme.red, Theme.red)
            case .quiet: return (.clear, .clear, Theme.ink)
            }
        }

        var body: some View {
            let p = palette
            HStack(spacing: 6) {
                if !style.iconOnly { configuration.label.textCase(.uppercase).lineLimit(1) }
                if let symbol = style.symbol { Image(systemName: symbol) }
            }
            // A button never wraps its word: in a tight row it keeps its size and the row has to make room.
            .fixedSize()
            .typeRole(.button)
            .foregroundStyle(p.text)
            .padding(.vertical, 6)
            .padding(.horizontal, style.iconOnly ? 6 : 12)
            .background(p.fill)
            .edge(p.edge)
            .contentShape(Rectangle())
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

/// `.plain` text field in a square container: rest sunken with a rule edge, focused raised with an ink edge, error red.
public struct EndfieldTextField: View {
    let placeholder: String
    @Binding var text: String
    let isError: Bool
    /// The fill while not focused: `sunken`, or `paper` on a sunken ground (the window's sidebar).
    let ground: Color
    /// Focus from outside (the window's ⌘K focuses the sidebar's Filter field).
    let focus: FocusState<Bool>.Binding?
    var forceFocused = false  // snapshots and previews: focus can't be set from outside
    @FocusState private var focused: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ placeholder: String, text: Binding<String>, isError: Bool = false, ground: Color = Theme.sunken,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.isError = isError
        self.ground = ground
        self.focus = focus
    }

    public var body: some View {
        let isFocused = (focus?.wrappedValue ?? focused) || forceFocused
        TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(Theme.secondary))
            .textFieldStyle(.plain)
            .typeRole(.body)
            .foregroundStyle(isEnabled ? Theme.ink : Theme.muted)
            .focused(focus ?? $focused)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(isFocused ? Theme.raised : ground)
            .edge(isError ? Theme.red : isFocused ? Theme.ink : Theme.rule)
    }
}

extension View {
    /// `.switch` toggle tinted ink (yellow fails contrast as a track on paper).
    public func endfieldSwitch() -> some View {
        toggleStyle(.switch).tint(Theme.ink)
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
    .padding().background(Theme.paper)
}

#Preview("Fields") {
    @Previewable @State var text = "Summarize the deploy log"
    VStack {
        EndfieldTextField("Message Hermes", text: .constant(""))
        EndfieldTextField("Message Hermes", text: $text)
        EndfieldTextField("Code", text: .constant("K7QF-2M9X-A1"), isError: true)
        Toggle("Launch at login", isOn: .constant(true)).endfieldSwitch()
    }
    .padding().frame(width: 320).background(Theme.paper)
}
