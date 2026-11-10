import SwiftUI

public extension EnvironmentValues {
    /// True on a steel ground: content there draws light (`Ink.text.onDark`). Nothing in the window is steel since the
    /// top bar went (#68); the parts keep their light variant.
    @Entry var onSteel = false
}

/// The head of every detail (#57, white since #68 took the top bar away): 52 pt on white, an optional leading mark (the
/// conversation's avatar), the title and the subtitle (`source · run id · started time`) on the left, the readings and
/// actions on the right; Endfield's 4 pt title rule under it, edge to edge.
public struct DetailHeader<Mark: View, Title: View, Subtitle: View, Trailing: View>: View {
    let mark: Mark
    let title: Title
    let subtitle: Subtitle
    let trailing: Trailing

    public init(
        @ViewBuilder mark: () -> Mark, @ViewBuilder title: () -> Title, @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.mark = mark()
        self.title = title()
        self.subtitle = subtitle()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.m) {
                mark
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s) {
                        title.typeRole(.title, weight: .bold).foregroundStyle(Ink.text.primary).accessibilityAddTraits(.isHeader)
                    }
                    subtitle.typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.s) { trailing }.fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Ink.text.primary)
            .padding(.leading, Space.xxl).padding(.trailing, Space.l).padding(.vertical, Space.s)
            .frame(minHeight: Size.sidebarHead)
            .background(Ink.surface.raised)
            SegmentRule((Size.titleRule.magenta, Size.titleRule.yellow, Size.titleRule.green), height: Size.titleRule.height, stretches: true)
        }
    }
}

public extension DetailHeader where Mark == EmptyView {
    init(@ViewBuilder title: () -> Title, @ViewBuilder subtitle: () -> Subtitle, @ViewBuilder trailing: () -> Trailing) {
        self.init(mark: { EmptyView() }, title: title, subtitle: subtitle, trailing: trailing)
    }
}

/// The detail header's terminal button, Chat only (⌘⌥T is the View menu's). While the drawer is open it reads pressed:
/// ink with a white glyph.
public struct TerminalToggle: View {
    let section: WindowSection
    let isOpen: Bool
    let action: () -> Void

    public init(section: WindowSection, isOpen: Bool, action: @escaping () -> Void) {
        self.section = section
        self.isOpen = isOpen
        self.action = action
    }

    var isAvailable: Bool { section == .chat }
    var isPressed: Bool { isAvailable && isOpen }
    var help: String { isAvailable ? "Toggle terminal (⌘⌥T)" : "The terminal pane is Chat only" }

    public var body: some View {
        Button(action: action) { IconCell(symbol: Symbol.terminal, isOn: isPressed) }
            .buttonStyle(.plain)
            .disabled(!isAvailable)
            .opacity(isAvailable ? 1 : Opacity.outlineOnDark)
            .help(help)
            .accessibilityLabel("Terminal")
            .accessibilityAddTraits(isPressed ? .isSelected : [])
    }
}

/// What the top bar held, at the end of a detail header (#68): the terminal toggle and Settings (⌘,).
public struct WindowTools: View {
    let section: WindowSection
    let terminalOpen: Bool
    let toggleTerminal: () -> Void

    public init(section: WindowSection, terminalOpen: Bool, toggleTerminal: @escaping () -> Void) {
        self.section = section
        self.terminalOpen = terminalOpen
        self.toggleTerminal = toggleTerminal
    }

    public var body: some View {
        TerminalToggle(section: section, isOpen: terminalOpen, action: toggleTerminal)
        SettingsLink { IconCell(symbol: Symbol.settings) }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
    }
}
