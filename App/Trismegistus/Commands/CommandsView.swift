import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The Commands section's sidebar: `COMMANDS // n`, the search (it filters the log), "All conversations", then the
/// conversations whose calls match, most recent first. The selection is a conversation id, `""` for all.
struct CommandsSidebar: View {
    @Binding var selection: String?
    @Binding var search: String
    /// The session list the log fetched last (`CommandsView`); the app's own until then.
    let sessions: [SessionInfo]?
    var filterFocus: FocusState<Bool>.Binding

    @Environment(AppModel.self) private var model
    @Environment(CommandLog.self) private var log: CommandLog?

    var body: some View {
        let entries = (log?.all ?? []).filter { CommandsView.matches($0, search) }
        let counts = Dictionary(grouping: entries.compactMap(\.sessionID), by: \.self).mapValues(\.count)
        let conversations = (sessions ?? model.sessions).filter { counts[$0.id] != nil }
        VStack(spacing: 0) {
            SidebarHeader(title: "Commands // \(entries.count)", prompt: "Search commands and output", filter: $search,
                          focus: filterFocus)
            if log == nil { SidebarNote(text: "Not connected.") }
            List(selection: $selection) {
                SidebarRow(title: "All conversations", meta: Self.count(entries.count), isSelected: selection == "")
                    .tag("").sidebarRow()
                ForEach(conversations) { info in
                    SidebarRow(title: ConversationSidebar.title(info), meta: Self.count(counts[info.id] ?? 0),
                               isSelected: selection == info.id)
                        .tag(info.id).sidebarRow()
                }
            }
            .sidebarList()
        }
    }

    private static func count(_ n: Int) -> String { "\(n) \(n == 1 ? "call" : "calls")" }
}

/// Recent tool calls across conversations, newest first, from Hermes' history (Telegram, cron and CLI runs too),
/// fetched again every 10 s while shown. Filters: the sidebar's conversation and search, failed only here. Each entry
/// opens its conversation.
struct CommandsView: View {
    /// A conversation id, `""` for all.
    let conversation: String
    let search: String
    @Binding var sessions: [SessionInfo]?
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(CommandLog.self) private var log: CommandLog?
    @State private var failedOnly = false
    @State private var listFailed = false

    private var titles: [String: String] {
        Dictionary((sessions ?? model.sessions).map { ($0.id, ConversationSidebar.title($0)) }, uniquingKeysWith: { a, _ in a })
    }

    static func matches(_ e: TerminalEntry, _ search: String) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || [e.command, e.cwd, e.output, e.errorText].contains { $0?.localizedCaseInsensitiveContains(needle) == true }
    }

    private var entries: [TerminalEntry] {
        (log?.all ?? []).filter { e in
            (!failedOnly || e.failed) && (conversation.isEmpty || e.sessionID == conversation) && Self.matches(e, search)
        }
    }

    var body: some View {
        let entries = entries
        VStack(spacing: 0) {
            header(count: entries.count)
            Rectangle().fill(Ink.line.rule).frame(height: 1)
            if entries.isEmpty {
                Text(emptyText).typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.xl) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: Space.s) {
                                conversationLink(entry.sessionID)
                                EntryRow(entry: entry)
                            }
                        }
                    }
                    .padding(Space.l)
                }
                .settledWidth()
            }
        }
        .background(Ink.surface.window)
        .task(id: log.map(ObjectIdentifier.init)) {
            guard let log else { return }
            while !Task.isCancelled {
                do {
                    let list = try await log.rest.listSessions()
                    sessions = list
                    listFailed = false
                    await log.refresh(list)
                } catch {
                    listFailed = true
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var emptyText: String {
        if log == nil { return "Not connected." }
        if log?.all.isEmpty == true { return listFailed ? "Can't reach the relay." : "Reading the history…" }
        return "No commands match."
    }

    private func header(count: Int) -> some View {
        HStack(spacing: Space.s) {
            Text("\(conversation.isEmpty ? "All conversations" : titles[conversation] ?? conversation) // \(count)")
                .typeRole(.label).foregroundStyle(Ink.text.secondary).lineLimit(1)
            if listFailed && log?.all.isEmpty == false {
                Text("can't reach the relay").typeRole(.caption).foregroundStyle(Ink.text.error)
            }
            Spacer(minLength: Space.s)
            FilterChip(title: "Failed", symbol: "exclamationmark.triangle", isOn: failedOnly) { failedOnly.toggle() }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    @ViewBuilder private func conversationLink(_ sessionID: String?) -> some View {
        if let sessionID {
            Button { onOpen(sessionID) } label: {
                HStack(spacing: Space.xs) {
                    Text(titles[sessionID] ?? sessionID).lineLimit(1)
                    Image(systemName: Symbol.chevronRight).font(.system(size: Icon.xs))
                }
                .typeRole(.monoSmall).foregroundStyle(Ink.text.link)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the conversation")
        }
    }
}
