import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Above a conversation's own messages: the parts it continues, oldest first, each folded behind a divider
/// ("Handed off 13:02 · 184 messages") that opens its history, read-only.
struct OlderParts: View {
    let tipID: String
    var compact = true

    @Environment(AppModel.self) private var model
    @State private var open: Set<String> = []
    @State private var histories: [String: [HistoryMessage]] = [:]
    @State private var errors: [String: String] = [:]

    var body: some View {
        if let store = model.store {
            let parts = Array(store.olderParts(of: tipID).reversed())
            ForEach(Array(parts.enumerated()), id: \.element) { i, part in
                VStack(alignment: .leading, spacing: Space.m) {
                    if open.contains(part) { history(part) }
                    divider(part, newer: i + 1 < parts.count ? parts[i + 1] : tipID, store: store)
                }
            }
        }
    }

    @ViewBuilder private func history(_ part: String) -> some View {
        if let messages = histories[part] {
            ChatTranscript(items: ChatTimeline.items(state(part, messages), compact: compact), sessionID: part)
        } else if let error = errors[part] {
            HStack(spacing: Space.s) {
                Text(error).typeRole(.caption).foregroundStyle(Ink.text.error)
                EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { load(part) }
            }
        } else {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
    }

    private func divider(_ part: String, newer: String, store: SessionStore) -> some View {
        let isOpen = open.contains(part)
        return Button {
            if isOpen { open.remove(part) } else { open.insert(part); if histories[part] == nil { load(part) } }
        } label: {
            HStack(spacing: Space.s) {
                Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
                Text(label(part, newer: newer, store: store)).typeRole(.label).foregroundStyle(Ink.text.secondary).fixedSize()
                Image(systemName: isOpen ? Symbol.chevronDown : Symbol.chevronRight).font(.system(size: Icon.xs, weight: .semibold))
                    .foregroundStyle(Ink.text.secondary)
                Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
            }
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Fold the earlier part" : "Show the earlier part")
        .accessibilityAddTraits(isOpen ? .isSelected : [])
    }

    /// "Handed off 13:02 · 184 messages": when the newer part started, and how long the older one was.
    private func label(_ part: String, newer: String, store: SessionStore) -> String {
        var parts = ["Handed off"]
        if let started = store.sessionList.first(where: { $0.id == newer })?.startedAt {
            let date = Date(timeIntervalSince1970: started)
            parts[0] += " " + (Calendar.current.isDateInToday(date)
                ? date.formatted(.clock.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                : date.formatted(.clock.day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
        }
        if let count = store.sessionList.first(where: { $0.id == part })?.messageCount {
            parts.append("\(count) \(count == 1 ? "message" : "messages")")
        }
        return parts.joined(separator: " · ")
    }

    private func state(_ id: String, _ messages: [HistoryMessage]) -> SessionState {
        var state = SessionState(id: id)
        state.applyHistory(messages)
        return state
    }

    private func load(_ part: String) {
        guard let store = model.store else { return }
        errors[part] = nil
        Task {
            do {
                histories[part] = try await store.rest.messages(part)
            } catch let error as RelayAPIError where error.status == 404 {
                errors[part] = "This part is no longer on the relay."
            } catch {
                errors[part] = SessionStore.message(for: error)
            }
        }
    }
}
