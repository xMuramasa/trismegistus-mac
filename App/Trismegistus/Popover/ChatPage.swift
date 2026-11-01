import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// A chat pushed inside the popover: back chevron (‹ and esc), title with the rule, subtitle, `ChatView` below, and
/// the hint strip for the state. Never shows approval keys: approvals are click-only.
struct ChatPage: View {
    let sessionID: String
    let onBack: @MainActor () -> Void

    @Environment(AppModel.self) private var model
    @State private var handingOff: SessionInfo?

    /// The thread's newest part, which ChatView shows and sends to.
    private var id: String { model.store?.threadTip(of: sessionID) ?? sessionID }
    private var info: SessionInfo? { model.sessions.first { $0.id == id } }
    private var runID: String? { model.store?.sessions[id]?.run?.id ?? model.store?.overview[id]?.run?.id }

    private var hints: [(key: String, action: String)] {
        var hints: [(key: String, action: String)] = []
        if !SessionInfo.isReadOnly(id: id, info: info) { hints.append(("⌘↩", runID == nil ? "send" : "steer")) }
        if runID != nil { hints.append(("⌘.", "stop")) }
        hints.append(("esc", "back"))
        return hints
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.m) {
                EndfieldButton("Back", symbol: "chevron.left", kind: .quiet, iconOnly: true, shortcut: .cancelAction, action: onBack)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    TitleRule(info.map(PopoverFormat.title) ?? "Session").lineLimit(1)
                    HStack(spacing: Space.m) {
                        Text(PopoverFormat.subtitle(id, info: info, store: model.store)).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).lineLimit(1)
                        if let info { ContextMeter(info: info) { handingOff = info } }
                    }
                }
                Spacer(minLength: 0)
                if let info { ModelMenu(info: info) }
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            ChatView(sessionID: sessionID)
            KeyHintStrip(hints)
        }
        .handoffSheet($handingOff)
    }
}

extension PopoverFormat {
    /// Under a chat's title (the popover's chat page, the window's conversation header): `Trismegistus · run 7f3a ·
    /// started 23:46` while a run is active, else `Trismegistus · 12 messages`.
    @MainActor static func subtitle(_ id: String, info: SessionInfo?, store: SessionStore?) -> String {
        var parts = [sourceName(info?.source)]
        let overviewRun = store?.overview[id]?.run
        if let runID = store?.sessions[id]?.run?.id ?? overviewRun?.id {
            parts.append("run \(runID.prefix(4))")
            if let started = overviewRun?.startedAt {
                parts.append("started " + started.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
            }
        } else if let count = info?.messageCount {
            parts.append("\(count) \(count == 1 ? "message" : "messages")")
        }
        return parts.joined(separator: " · ")
    }
}
