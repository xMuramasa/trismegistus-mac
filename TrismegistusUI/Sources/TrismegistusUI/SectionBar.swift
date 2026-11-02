import SwiftUI

/// The main window's sections (#41), in the section bar's order, left to right: ⌘1…⌘6.
public enum WindowSection: String, CaseIterable, Identifiable, Sendable {
    case chat, github, news, agents, jobs, commands

    public var id: Self { self }

    public var title: String {
        switch self {
        case .chat: "Chat"
        case .github: "GitHub"
        case .news: "News"
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
        case .news: "newspaper"
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

    /// Where an id opened from another section lands (Jobs, GitHub, Agents, Commands, a notification): News for the
    /// News id, otherwise the conversation in Chat.
    public static func opening(_ id: String, newsID: String) -> WindowSection { id == newsID ? .news : .chat }

    /// The selection a list keeps when its items change: the same one while it is listed, else the first.
    public static func kept(_ selection: String?, in ids: [String]) -> String? {
        if let selection, ids.contains(selection) { return selection }
        return ids.first
    }
}

/// The section icons at the bottom of the window sidebar, spread evenly (09f): unselected in `icon.on-sidebar`, the
/// selected one in `text.on-sidebar` with a yellow bar under it. Each icon is at least a 28 pt square to click.
public struct SectionBar: View {
    @Binding var selection: WindowSection

    public init(selection: Binding<WindowSection>) {
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(WindowSection.allCases) { section in
                let on = section == selection
                Button { selection = section } label: {
                    Image(systemName: section.symbol)
                        .font(.system(size: Icon.section))
                        .foregroundStyle(on ? Ink.text.onSidebar : Ink.icon.onSidebar)
                        .overlay(alignment: .bottom) {
                            if on {
                                Rectangle().fill(Ink.selection).frame(width: Icon.section, height: Stroke.accent)
                                    .offset(y: Space.xxs + Stroke.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: Size.sectionTarget)
                        .frame(minWidth: Size.sectionTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.help)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, Space.m)
        .padding(.horizontal, Space.xl)
    }
}
