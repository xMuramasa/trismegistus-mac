import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// A chat pushed inside the popover: back chevron (‹ and esc), title with the rule, subtitle, `ChatView` below, and
/// the hint strip for the state. Never shows approval keys: approvals are click-only.
struct ChatPage: View {
    let sessionID: String
    let onBack: @MainActor () -> Void

    @Environment(AppModel.self) private var model

    private var info: SessionInfo? { model.sessions.first { $0.id == sessionID } }
    private var runID: String? { model.store?.sessions[sessionID]?.run?.id ?? model.store?.overview[sessionID]?.run?.id }

    private var subtitle: String {
        var parts = [PopoverFormat.sourceName(info?.source)]
        if let runID {
            parts.append("run \(runID.prefix(4))")
        } else if let count = info?.messageCount {
            parts.append("\(count) \(count == 1 ? "message" : "messages")")
        }
        return parts.joined(separator: " · ")
    }

    private var hints: [(key: String, action: String)] {
        var hints: [(key: String, action: String)] = []
        if info?.isReadOnly != true { hints.append(("⌘↩", runID == nil ? "send" : "steer")) }
        if runID != nil { hints.append(("⌘.", "stop")) }
        hints.append(("esc", "back"))
        return hints
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                EndfieldButton("Back", symbol: "chevron.left", kind: .quiet, iconOnly: true, shortcut: .cancelAction, action: onBack)
                VStack(alignment: .leading, spacing: 2) {
                    TitleRule(info.map(PopoverFormat.title) ?? "Session").lineLimit(1)
                    Text(subtitle).typeRole(.monoSmall).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            ChatView(sessionID: sessionID)
            KeyHintStrip(hints)
        }
    }
}
