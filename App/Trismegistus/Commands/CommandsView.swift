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

    static func count(_ n: Int) -> String { "\(n) \(n == 1 ? "call" : "calls")" }
}

/// Recent tool calls across conversations from Hermes' history (Telegram, cron and CLI runs too), one group per
/// conversation, newest group and newest call first, fetched again every 10 s while shown. Filters: the sidebar's
/// conversation and search, failed only here. Each group's head opens its conversation.
struct CommandsView: View {
    /// A group shows this many calls until Show more or a filter.
    private static let groupLimit = 6

    /// A conversation id, `""` for all.
    let conversation: String
    let search: String
    @Binding var sessions: [SessionInfo]?
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(CommandLog.self) private var log: CommandLog?
    @AppStorage(TerminalTranscript.oneLineKey) private var oneLine = TerminalTranscript.oneLineByDefault
    @State private var failedOnly = false
    @State private var listFailed = false
    @State private var foldedGroups: Set<String> = []
    @State private var fullGroups: Set<String> = []

    private var titles: [String: String] {
        Dictionary((sessions ?? model.sessions).map { ($0.id, ConversationSidebar.title($0)) }, uniquingKeysWith: { a, _ in a })
    }

    static func matches(_ e: TerminalEntry, _ search: String) -> Bool {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || [e.command, e.cwd, e.output, e.errorText].contains { $0?.localizedCaseInsensitiveContains(needle) == true }
    }

    /// The conversation's calls; the counts don't move with the Failed filter or the search.
    private var entries: [TerminalEntry] {
        (log?.all ?? []).filter { conversation.isEmpty || $0.sessionID == conversation }
    }

    private func shows(_ e: TerminalEntry) -> Bool { (!failedOnly || e.failed) && Self.matches(e, search) }

    var body: some View {
        let entries = entries
        let groups = TerminalTranscript.groups(entries).filter { $0.entries.contains(where: shows) }
        VStack(spacing: 0) {
            header(calls: entries.count, failed: entries.count(where: \.failed))
            if groups.isEmpty {
                Text(emptyText).typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.xxxl) {
                        ForEach(groups) { groupView($0) }
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

    private func header(calls: Int, failed: Int) -> some View {
        DetailHeader {
            Text(verbatim: conversation.isEmpty ? "All conversations" : titles[conversation] ?? conversation)
        } subtitle: {
            HStack(spacing: Space.s) {
                Text(verbatim: "\(CommandsSidebar.count(calls)) · \(failed) failed")
                if listFailed && log?.all.isEmpty == false {
                    Text("can't reach the relay").foregroundStyle(Ink.status.warn)
                }
            }
        } trailing: {
            HStack(spacing: Space.s) {
                FilterChip(title: "One line", symbol: "text.justify", isOn: oneLine) { oneLine.toggle() }
                FilterChip(title: "Failed", symbol: "exclamationmark.triangle", isOn: failedOnly) { failedOnly.toggle() }
            }
        }
    }

    private func groupView(_ group: ConversationCalls) -> some View {
        let rows = group.entries.filter(shows)
        let cut = rows.count == group.entries.count && !fullGroups.contains(group.id)
        let shown = cut ? Array(rows.prefix(Self.groupLimit)) : rows
        let isOpen = !foldedGroups.contains(group.id)
        let dated = EntryRow.dated(shown)
        return VStack(alignment: .leading, spacing: 0) {
            CommandGroupHead(
                title: titles[group.id] ?? group.id, calls: group.entries.count, failed: group.failedCount, isOpen: isOpen,
                onOpen: { onOpen(group.id) },
                onFold: { foldedGroups.formSymmetricDifference([group.id]) })
            if isOpen {
                Group {
                    if oneLine {
                        LazyVStack(spacing: 0) {
                            ForEach(shown) { EntryRow(entry: $0, oneLine: true, dated: dated) }
                        }
                        .background { Rectangle().fill(Ink.surface.raised).shadow(Shadow.card) }
                    } else {
                        LazyVStack(alignment: .leading, spacing: Space.xxl) {
                            ForEach(shown) { EntryRow(entry: $0, dated: dated) }
                        }
                    }
                }
                .padding(.top, Space.m)
                if shown.count < group.entries.count {
                    CommandGroupFoot(shown: shown.count, total: group.entries.count,
                                     onMore: shown.count < rows.count ? { fullGroups.insert(group.id) } : nil)
                        .padding(.top, Space.s)
                }
            }
        }
    }
}
