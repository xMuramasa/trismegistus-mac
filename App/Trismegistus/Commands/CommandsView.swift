import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The window sidebar's Commands row, above the conversations.
struct CommandsRowView: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(isSelected ? Theme.yellow : .clear).frame(width: 3)
            HStack(spacing: 8) {
                Image(systemName: Symbol.terminal).font(.system(size: 11)).foregroundStyle(Theme.muted)
                Text("Commands").typeRole(.headline).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Text("all conversations").typeRole(.monoSmall).foregroundStyle(Theme.muted)
                if isSelected {
                    Image(systemName: Symbol.chevronRight).font(.system(size: 10)).foregroundStyle(Theme.ink)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 40)
        .background(Theme.raised)
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
    @AppStorage("commands.commandsOnly") private var commandsOnly = true
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
            (!commandsOnly || e.isCommand) && (!failedOnly || e.failed) && (conversation == nil || e.sessionID == conversation)
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
            Rectangle().fill(Theme.rule).frame(height: 1)
            if entries.isEmpty {
                Text(emptyText).typeRole(.caption).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                conversationLink(entry.sessionID)
                                EntryRow(entry: entry)
                            }
                        }
                    }
                    .padding(16)
                    .textSelection(.enabled)
                }
            }
        }
        .background(Theme.paper)
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
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Commands // \(count)").typeRole(.label).foregroundStyle(Theme.secondary)
                if listFailed && log?.all.isEmpty == false {
                    Text("can't reach the relay").typeRole(.caption).foregroundStyle(Theme.red)
                }
                Spacer(minLength: 8)
                FilterChip(title: "Commands", symbol: Symbol.terminal, isOn: commandsOnly) { commandsOnly = true }
                FilterChip(title: "All tools", symbol: Symbol.list, isOn: !commandsOnly) { commandsOnly = false }
                FilterChip(title: "Failed", symbol: "exclamationmark.triangle", isOn: failedOnly) { failedOnly.toggle() }
            }
            HStack(spacing: 8) {
                EndfieldTextField("Search commands and output", text: $search)
                Picker("Conversation", selection: $conversation) {
                    Text("All conversations").tag(String?.none)
                    ForEach(conversations) { Text(ConversationSidebar.title($0)).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 240)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private func conversationLink(_ sessionID: String?) -> some View {
        if let sessionID {
            Button { onOpen(sessionID) } label: {
                HStack(spacing: 4) {
                    Text(titles[sessionID] ?? sessionID).lineLimit(1)
                    Image(systemName: Symbol.chevronRight).font(.system(size: 9))
                }
                .typeRole(.monoSmall).foregroundStyle(Theme.blue)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the conversation")
        }
    }
}
