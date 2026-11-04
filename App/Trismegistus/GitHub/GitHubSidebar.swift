import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The GitHub section's sidebar: `GITHUB // n OPEN`, the filter, the repo and priority pickers, then the Work board
/// grouped by Status in board order (Done folded until opened); with a repo chosen, its board items or its open or
/// closed issues instead. The selection is `owner/repo#n`.
struct GitHubSidebar: View {
    @Binding var selection: String?
    var filterFocus: FocusState<Bool>.Binding

    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var repo: String?
    /// nil: any; `""`: no priority.
    @State private var priority: String?
    @State private var list = ListKind.board
    /// Groups whose fold differs from the default (Done folded, the rest open).
    @State private var toggled: Set<String> = []
    /// A repo's open or closed issues, the 100 most recently updated.
    @State private var repoIssues: GitHubIssueList?
    @State private var repoError: String?

    enum ListKind { case board, open, closed, needsCheck }

    /// A repo's open or closed issue list, which needs a repo chosen.
    private var isRepoList: Bool { list == .open || list == .closed }

    private func matches(_ title: String, _ ref: String) -> Bool {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty || title.localizedCaseInsensitiveContains(needle) || ref.localizedCaseInsensitiveContains(needle)
    }

    var body: some View {
        let github = model.github
        // `owner/repo#n` of the issues with a live run.
        let running = Set((model.agents?.agents ?? []).filter(\.alive).compactMap { a in a.repo.flatMap { r in a.issue.map { "\(r)#\($0)" } } })
        VStack(spacing: 0) {
            SidebarHeader(title: list == .needsCheck ? "Needs check // \(github?.board?.needsCheckCount ?? 0)"
                                                      : "GitHub // \(github?.board?.openCount ?? 0) open",
                          prompt: "Filter issues", filter: $filter,
                          focus: filterFocus) {
                if let github {
                    EndfieldButton("Refresh", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { Task { await github.refresh() } }
                }
            } extra: {
                if let board = github?.board {
                    pickers(board)
                    // A refresh that failed over a board loaded before.
                    ActionError(message: github?.error)
                }
            }
            if let github {
                if github.notConfigured {
                    SidebarNote(text: "Not set up on the relay.")
                } else if github.board == nil {
                    SidebarNote(text: github.error ?? "Loading the board…")
                } else if isRepoList, repoIssues == nil {
                    SidebarNote(text: repoError ?? "Loading…")
                }
            } else {
                SidebarNote(text: "Not connected.")
            }
            List(selection: $selection) {
                if let board = github?.board {
                    if let repo, isRepoList, let issues = repoIssues {
                        let state = list == .closed ? "closed" : "open"
                        SidebarNote(text: issues.total > issues.issues.count
                            ? "\(issues.issues.count) of \(issues.total) \(state), recently updated first" : "\(issues.total) \(state)")
                            .sidebarRow()
                        ForEach(issues.issues.filter { matches($0.title, "\(repo)#\($0.number)") }) { issue in
                            let ref = "\(repo)#\(issue.number)"
                            IssueRow(ref: ref, title: issue.title, priority: "", isClosed: issue.state == "closed",
                                     isRunning: running.contains(ref), isSelected: selection == ref)
                                .tag(ref).sidebarRow()
                        }
                    } else if list == .needsCheck {
                        inboxRows(board, running: running)
                    } else {
                        boardRows(board, running: running)
                    }
                }
            }
            .sidebarList()
        }
        .onChange(of: repo) { if repo == nil, isRepoList { list = .board } }
        .onChange(of: list) { model.github?.inboxShown = list == .needsCheck }
        .onAppear { model.github?.inboxShown = false }
        // The inbox reads each item's comments while it is open; a changed item is read again.
        .task(id: list == .needsCheck ? inboxSignature : nil) {
            if list == .needsCheck, let github = model.github, let items = github.board?.needsCheck().flatMap(\.items) {
                await github.loadNotes(for: items)
            }
        }
        .task(id: "\(repo ?? "") \(list)") { await loadRepoIssues() }
    }

    private func pickers(_ board: GitHubBoard) -> some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                Picker("Repository", selection: $repo) {
                    Text("All repos").tag(String?.none)
                    ForEach(board.repos, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .labelsHidden().pickerStyle(.menu)
                if list == .board {
                    Picker("Priority", selection: $priority) {
                        Text("Any priority").tag(String?.none)
                        ForEach(board.priorityOptions, id: \.self) { Text($0).tag(Optional($0)) }
                        Text("No priority").tag(Optional(""))
                    }
                    .labelsHidden().pickerStyle(.menu)
                }
            }
            HStack(spacing: 0) {
                TabChip(title: "Board", symbol: "rectangle.split.3x1", isOn: list == .board) { list = .board }
                // Open and Closed are one repo's issues.
                if repo != nil {
                    TabChip(title: "Open", symbol: "circle", isOn: list == .open) { list = .open }
                    TabChip(title: "Closed", symbol: Symbol.check, isOn: list == .closed) { list = .closed }
                }
                TabChip(title: "Needs check", symbol: "eye", count: board.needsCheckCount, isOn: list == .needsCheck) { list = .needsCheck }
            }
            // Ink on white: the chips' words don't read on the grey ground.
            .background(Ink.surface.raised)
            .overlay(Rectangle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
        }
    }

    /// Changes when an inbox item is added or updated.
    private var inboxSignature: String {
        (model.github?.board?.items ?? []).filter { GitHubInbox.isNeedsCheck($0.status) }.map { $0.id + $0.updatedAt }.joined(separator: ",")
    }

    /// Items at Status Needs check, grouped by repo (name without the owner), newest updated first.
    @ViewBuilder private func inboxRows(_ board: GitHubBoard, running: Set<String>) -> some View {
        let groups = board.needsCheck(repo: repo, matching: filter)
        if groups.isEmpty { SidebarNote(text: "Nothing needs your check.").sidebarRow() }
        ForEach(groups, id: \.repo) { group in
            HStack(spacing: Space.s) {
                Text(GitHubInbox.shortName(group.repo)).typeRole(.label)
                Text(verbatim: "\(group.items.count)").typeRole(.monoSmall)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Ink.text.onSidebarSecondary)
            .padding(.horizontal, Space.l).padding(.top, Space.m).padding(.bottom, Space.xs)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .sidebarRow()
            ForEach(group.items) { item in
                IssueRow(ref: "#\(item.number)", title: item.title, priority: item.priority, isClosed: item.state == "closed",
                         isRunning: running.contains(item.id), isSelected: selection == item.id,
                         caption: model.github?.notes[item.id]?.note?.lines.first)
                    .tag(item.id).sidebarRow()
            }
        }
    }

    @ViewBuilder private func boardRows(_ board: GitHubBoard, running: Set<String>) -> some View {
        ForEach(board.groups(repo: repo, priority: priority), id: \.status) { group in
            let folded = GitHubBoard.isDone(group.status) != toggled.contains(group.status)
            Button {
                if toggled.contains(group.status) { toggled.remove(group.status) } else { toggled.insert(group.status) }
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: Symbol.fold(isOpen: !folded))
                        .font(.system(size: Icon.xxs, weight: .bold)).frame(width: Icon.xxs)
                    Text(group.status.isEmpty ? "No status" : group.status).typeRole(.label)
                    Text(verbatim: "\(group.items.count)").typeRole(.monoSmall)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Ink.text.onSidebarSecondary)
                .padding(.horizontal, Space.l).padding(.top, Space.m).padding(.bottom, Space.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(folded ? "Show the issues" : "Hide the issues")
            .sidebarRow()
            if !folded {
                ForEach(group.items.filter { matches($0.title, $0.id) }) { item in
                    IssueRow(ref: item.id, title: item.title, priority: item.priority, isClosed: item.state == "closed",
                             isRunning: running.contains(item.id), isSelected: selection == item.id)
                        .tag(item.id).sidebarRow()
                }
            }
        }
    }

    private func loadRepoIssues() async {
        repoIssues = nil
        repoError = nil
        guard let repo, isRepoList, let rest = model.github?.rest else { return }
        do {
            repoIssues = try await rest.githubIssues(repo: repo, state: list == .closed ? "closed" : "open")
        } catch {
            // Cancelled: the repo or the list kind changed under it.
            guard !Task.isCancelled else { return }
            repoError = GitHubError.describe(error)
        }
    }
}

/// The selected issue (`GitHubIssueView`), or an empty state. Loads the board once per connection, so the sidebar
/// has it with the sidebar hidden too.
struct GitHubView: View {
    let selection: String?
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model

    /// `owner/repo#n` as its repo and number.
    static func issue(_ ref: String?) -> (repo: String, number: Int)? {
        guard let ref, let hash = ref.lastIndex(of: "#"), let number = Int(ref[ref.index(after: hash)...]) else { return nil }
        return (String(ref[..<hash]), number)
    }

    var body: some View {
        Group {
            if let github = model.github {
                Group {
                    if github.notConfigured {
                        SetupNote(text: github.error ?? "")
                    } else if let issue = Self.issue(selection) {
                        GitHubIssueView(github: github, repo: issue.repo, number: issue.number, onOpen: onOpen)
                            .id(selection)
                    } else {
                        SectionEmpty(symbol: WindowSection.github.symbol, text: "No issue selected")
                    }
                }
                .task(id: ObjectIdentifier(github)) { await github.refresh() }
            } else {
                Text("Not connected.").typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.surface.window)
    }
}

/// An issue in the sidebar: `owner/repo#n`, priority and state over the title.
private struct IssueRow: View {
    let ref: String
    let title: String
    let priority: String
    let isClosed: Bool
    /// A run is alive on it: a triangle beside the number.
    let isRunning: Bool
    let isSelected: Bool
    /// The inbox's first "look at" line, one line.
    var caption: String?

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        let ink = RowInk(onSidebar: onSidebar, isSelected: isSelected)
        VStack(alignment: .leading, spacing: Space.xxs) {
            HStack(spacing: Space.s) {
                if isRunning { RunningTriangle().foregroundStyle(ink.meta) }
                Text(ref).typeRole(.monoSmall).foregroundStyle(ink.meta).lineLimit(1).truncationMode(.middle)
                if !priority.isEmpty { PriorityMark(priority: priority) }
                if isClosed { Text("closed").typeRole(.label).foregroundStyle(ink.meta) }
            }
            Text(title).typeRole(.headline).foregroundStyle(ink.title).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let caption { Text(caption).typeRole(.caption).foregroundStyle(ink.meta).lineLimit(1) }
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// One of the sidebar's tabs: an icon with an optional count beside it; the name is the tooltip and accessibility
/// label. `FilterChip`'s look, which spells its word out and is too wide for four tabs.
private struct TabChip: View {
    let title: String
    let symbol: String
    var count: Int?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: symbol)
                if let count { Text(verbatim: "\(count)").typeRole(.monoSmall) }
            }
            .typeRole(.button)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity)
            .foregroundStyle(isOn ? Ink.selection : Ink.text.primary)
            .background(isOn ? Ink.surface.inverse : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
