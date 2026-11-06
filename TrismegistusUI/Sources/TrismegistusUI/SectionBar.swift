import SwiftUI

/// The main window's sections (#41), in the section bar's order, left to right: ⌘1…⌘5.
public enum WindowSection: String, CaseIterable, Identifiable, Sendable {
    case chat, github, agents, jobs, commands

    public var id: Self { self }

    public var title: String {
        switch self {
        case .chat: "Chat"
        case .github: "GitHub"
        case .agents: "Agents"
        case .jobs: "Jobs"
        case .commands: "Commands"
        }
    }

    /// The symbols the sidebar rows used before sections, a chat bubble for Chat.
    public var symbol: String {
        switch self {
        case .chat: "bubble.left"
        case .github: "checklist"
        case .agents: "cpu"
        case .jobs: Symbol.cron
        case .commands: Symbol.terminal
        }
    }

    private var number: Int { Self.allCases.firstIndex(of: self)! + 1 }

    /// With ⌘: 1 for the first section.
    public var key: KeyEquivalent { KeyEquivalent(Character(String(number))) }

    /// The tooltip: `Chat (⌘1)`.
    public var help: String { "\(title) (⌘\(number))" }

    /// The `UserDefaults` key of the section's own selection; Chat keeps the key it had before sections.
    public var selectionKey: String { self == .chat ? "window.selectedSession" : "window.selection.\(rawValue)" }

    /// The selection a list keeps when its items change: the same one while it is listed, else the first.
    public static func kept(_ selection: String?, in ids: [String]) -> String? {
        if let selection, ids.contains(selection) { return selection }
        return ids.first
    }
}

/// The foot of the window sidebar, in every section (#65): an ink bar with the paired device over the section icons,
/// the current one on a yellow block.
public struct SectionBar: View {
    @Binding var selection: WindowSection
    /// `macbook · paired`.
    let device: String?

    @Environment(\.sidebarNarrow) private var narrow

    public init(selection: Binding<WindowSection>, device: String? = nil) {
        self._selection = selection
        self.device = device
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let device {
                Text(device).typeRole(.data).monospacedDigit().foregroundStyle(Ink.text.onDark).lineLimit(1)
                    .padding(.horizontal, Space.xs)
            }
            HStack(spacing: 0) {
                ForEach(WindowSection.allCases) { section in
                    let on = section == selection
                    if section != WindowSection.allCases.first { Spacer(minLength: 0) }
                    Button { selection = section } label: {
                        Image(systemName: section.symbol)
                            .font(.system(size: Icon.sectionBlock))
                            .foregroundStyle(on ? Ink.text.primary : Ink.text.onSidebar)
                            .frame(width: narrow ? Size.footerBlock.narrow : Size.footerBlock.width, height: Size.footerBlock.height)
                            .background(on ? Ink.selection : .clear)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(section.help)
                    .accessibilityLabel(section.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, Space.m)
        .padding(.top, Space.m).padding(.bottom, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.inverse)
    }
}
