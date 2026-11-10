import SwiftUI

/// The main window's sections (#41), in the section panel's order, top to bottom: ⌘1…⌘5.
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
