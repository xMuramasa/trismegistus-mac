import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The window sidebar's Commands row, above the conversations.
struct CommandsRowView: View {
    let isSelected: Bool

    @Environment(\.sunkenRows) private var sunken

    var body: some View {
        // Title and a meta line, like the conversation rows: on one line "all conversations" wrapped at 260 pt.
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Commands").typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(1)
                HStack(spacing: Space.s) {
                    Image(systemName: Symbol.terminal).font(.system(size: Icon.m))
                    Text("all conversations").typeRole(.monoSmall).lineLimit(1)
                }
                .foregroundStyle(sunken ? Ink.text.secondary : Ink.text.muted)
            }
            Spacer(minLength: Space.s)
            if isSelected {
                Image(systemName: Symbol.chevronRight).font(.system(size: Icon.s)).foregroundStyle(Ink.text.primary)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Size.row)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Recent tool calls across conversations, newest first, from Hermes' history (Telegram, cron and CLI runs too),
/// fetched again every 10 s while shown. Filters: commands or all tools, failed only, conversation, text. Each entry
/// opens its conversation.
struct CommandsView: View {
    nonisolated static let id = "trismegistus.commands" // in selections; not a Hermes session id
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @Environment(CommandLog.self) private var log: CommandLog?
    @State private var failedOnly = false
    @State private var conversation: String?
    @State private var search = ""
    /// The list this view fetched last; the app's own is only reloaded on connect.
    @State private var sessions: [SessionInfo]?
    @State private var listFailed = false

    private var titles: [String: String] {
        Dictionary((sessions ?? model.sessions).map { ($0.id, ConversationSidebar.title($0)) }, uniquingKeysWith: { a, _ in a })
    }

    private var entries: [TerminalEntry] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        return (log?.all ?? []).filter { e in
            (!failedOnly || e.failed) && (conversation == nil || e.sessionID == conversation)
                && (needle.isEmpty || [e.command, e.cwd, e.output, e.errorText].contains { $0?.localizedCaseInsensitiveContains(needle) == true })
        }
    }

    /// The conversations that have calls, most recent first.
    private var conversations: [SessionInfo] {
        (sessions ?? model.sessions).filter { !(log?.entries(of: $0.id).isEmpty ?? true) }
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
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text("Commands // \(count)").typeRole(.label).foregroundStyle(Ink.text.secondary)
                if listFailed && log?.all.isEmpty == false {
                    Text("can't reach the relay").typeRole(.caption).foregroundStyle(Ink.text.error)
                }
                Spacer(minLength: Space.s)
                FilterChip(title: "Failed", symbol: "exclamationmark.triangle", isOn: failedOnly) { failedOnly.toggle() }
            }
            HStack(spacing: Space.s) {
                EndfieldTextField("Search commands and output", text: $search)
                Picker("Conversation", selection: $conversation) {
                    Text("All conversations").tag(String?.none)
                    ForEach(conversations) { Text(ConversationSidebar.title($0)).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: Size.pickerMax)
            }
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
