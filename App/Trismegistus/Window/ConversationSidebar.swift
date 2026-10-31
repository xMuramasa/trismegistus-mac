import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Window sidebar: `CONVERSATIONS // n`, icon-only new, filter field, one row per session, the paired device below.
struct ConversationSidebar: View {
    @Binding var selection: String?

    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var createFailed = false

    private var rows: [SessionOverview] {
        guard let store = model.store else { return [] }
        let needle = filter.trimmingCharacters(in: .whitespaces)
        return model.sessions
            .filter { needle.isEmpty || Self.title($0).localizedCaseInsensitiveContains(needle) }
            .compactMap { store.overview[$0.id] }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            List(selection: $selection) {
                ForEach(rows) { row in
                    ConversationRow(overview: row, isSelected: selection == row.id)
                        .tag(row.id)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparatorTint(Theme.rule)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            footer
        }
        .background(Theme.sunken)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Conversations // \(model.sessions.count)").typeRole(.label).foregroundStyle(Theme.secondary)
                Spacer()
                EndfieldButton("New conversation", symbol: Symbol.plus, kind: .quiet, iconOnly: true) { create() }
            }
            EndfieldTextField("Filter", text: $filter)
            if createFailed {
                Text("Could not create a conversation. Try again.").typeRole(.caption).foregroundStyle(Theme.red)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var footer: some View {
        Text(model.deviceName.map { "\($0) · paired" } ?? "not paired")
            .typeRole(.monoSmall).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func create() {
        Task {
            do {
                selection = try await model.store?.createSession().id
                createFailed = false
            } catch {
                createFailed = true
            }
        }
    }

    static func title(_ info: SessionInfo) -> String { info.title ?? info.preview ?? "New conversation" }
}

private struct ConversationRow: View {
    let overview: SessionOverview
    let isSelected: Bool

    var body: some View {
        // Ticks every second only while a run's clock shows; the "2 min" age is fine at half a minute.
        TimelineView(.periodic(from: .now, by: overview.run == nil ? 30 : 1)) { context in
            SessionRowView(
                name: overview.info.map(ConversationSidebar.title) ?? "New conversation",
                source: source, activity: Self.age(overview.lastActivity, now: context.date), isSelected: isSelected,
                isReadOnly: overview.isReadOnly,
                runElapsed: overview.run.map { Self.clock(context.date.timeIntervalSince($0.startedAt)) },
                needsApproval: overview.isWaitingForApproval)
        }
    }

    private var source: SessionSource {
        switch overview.source {
        case "api_server": .trismegistus
        case "telegram": .telegram
        case "cron": .cron
        default: .cli
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60) min"
        case ..<86400: return "\(s / 3600) h"
        case ..<172_800: return "yesterday"
        default: return "\(s / 86400) d"
        }
    }
}
