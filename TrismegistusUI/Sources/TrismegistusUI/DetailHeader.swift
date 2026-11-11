import SwiftUI

public extension EnvironmentValues {
    /// True on a steel ground: content there draws light (`Ink.text.onDark`). Nothing in the window is steel since the
    /// top bar went (#68); the parts keep their light variant.
    @Entry var onSteel = false
}

/// The head of every detail (#57; #69 design 13 #a3): 52 pt, frosted white, an optional leading mark (the
/// conversation's 28 pt avatar), the title (14 pt, 600) and the subtitle (`source · run id · started time`, 11 pt) on
/// the left, the readings and actions (thin-edged) on the right; the 2 pt title rule under it, edge to edge.
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
                        title.typeRole(.detailTitle).foregroundStyle(Ink.text.primary).accessibilityAddTraits(.isHeader)
                    }
                    subtitle.typeRole(.caption).monospacedDigit().foregroundStyle(Ink.text.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.s) { trailing }.fixedSize(horizontal: true, vertical: false)
                    .environment(\.hairlineControls, true)
            }
            .foregroundStyle(Ink.text.primary)
            .padding(.leading, Space.xxl).padding(.trailing, Space.l).padding(.vertical, Space.s)
            .frame(minHeight: Size.sidebarHead)
            .background(Ink.surface.frosted)
            DetailRule()
        }
    }
}

/// The detail header's title rule (#69): a 2 pt rule-grey line with an 8 pt dark-panel tick and the 56 pt yellow
/// segment after a gap.
public struct DetailRule: View {
    public init() {}

    public var body: some View {
        HStack(spacing: Space.xs) {
            Rectangle().fill(Ink.surface.darkPanel).frame(width: Size.titleRule.tick)
            Rectangle().fill(Ink.selection).frame(width: Size.titleRule.yellow)
            Spacer(minLength: 0)
        }
        .frame(height: Size.titleRule.height)
        .background(Ink.line.rule)
        .accessibilityHidden(true)
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
