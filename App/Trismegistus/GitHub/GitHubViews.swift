import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The window sidebar's GitHub row, after Commands: the Work board's open issues that aren't Done. Loads the board
/// once per connection, so the count shows before the view is opened.
struct GitHubRowView: View {
    nonisolated static let id = "trismegistus.github" // in selections; not a Hermes session id
    static let symbol = "checklist"

    let github: GitHubModel?
    let isSelected: Bool

    @Environment(\.sunkenRows) private var sunken

    private var detail: String {
        guard let github else { return "not connected" }
        if github.notConfigured { return "not set up on the relay" }
        if let board = github.board { return "\(board.openCount) open · Work board" }
        return github.error == nil ? "loading" : "can't load the board"
    }

    var body: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("GitHub").typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(1)
                HStack(spacing: Space.s) {
                    Image(systemName: Self.symbol).font(.system(size: Icon.m))
                    Text(detail).typeRole(.monoSmall).lineLimit(1)
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
        .task(id: github.map(ObjectIdentifier.init)) { await github?.refresh() }
    }
}

/// The Work board grouped by Status in board order (Done folded until opened), filtered by repo and priority; with
/// a repo chosen, its open or closed issues instead. A row opens the issue in place.
struct GitHubView: View {
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @State private var repo: String?
    /// nil: any; `""`: no priority.
    @State private var priority: String?
    @State private var list = ListKind.board
    /// Groups whose fold differs from the default (Done folded, the rest open).
    @State private var toggled: Set<String> = []
    @State private var issue: IssueRef?

    enum ListKind { case board, open, closed }

    struct IssueRef: Equatable {
        var repo: String
        var number: Int
    }

    var body: some View {
        Group {
            if let github = model.github {
                if let issue {
                    GitHubIssueView(github: github, repo: issue.repo, number: issue.number, onBack: { self.issue = nil }, onOpen: onOpen)
                        .id("\(issue.repo)#\(issue.number)")
                } else {
                    content(github)
                }
            } else {
                Text("Not connected.").typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.surface.window)
        .onChange(of: repo) { if repo == nil { list = .board } }
    }

    private func content(_ github: GitHubModel) -> some View {
        VStack(spacing: 0) {
            header(github)
            Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
            if github.notConfigured {
                SetupNote(text: github.error ?? "")
            } else if let board = github.board {
                if let repo, list != .board {
                    RepoIssues(repo: repo, state: list == .closed ? "closed" : "open") { issue = IssueRef(repo: repo, number: $0) }
                        .id("\(repo) \(list)")
                } else {
                    boardList(board)
                }
            } else {
                Text(github.error ?? "Loading the board…").typeRole(.caption)
                    .foregroundStyle(github.error == nil ? Ink.text.muted : Ink.text.error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await github.refresh() }
    }

    private func header(_ github: GitHubModel) -> some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text("GitHub // \(github.board?.openCount ?? 0) open").typeRole(.label).foregroundStyle(Ink.text.secondary)
                Spacer(minLength: Space.s)
                EndfieldButton("Refresh", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { Task { await github.refresh() } }
            }
            if let board = github.board {
                HStack(spacing: Space.s) {
                    Picker("Repository", selection: $repo) {
                        Text("All repos").tag(String?.none)
                        ForEach(board.repos, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    .labelsHidden().pickerStyle(.menu).frame(maxWidth: Size.pickerMax)
                    if list == .board {
                        Picker("Priority", selection: $priority) {
                            Text("Any priority").tag(String?.none)
                            ForEach(board.priorityOptions, id: \.self) { Text($0).tag(Optional($0)) }
                            Text("No priority").tag(Optional(""))
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: Size.pickerMax)
                    }
                    Spacer(minLength: Space.s)
                    if repo != nil {
                        HStack(spacing: 0) {
                            FilterChip(title: "Board", symbol: "rectangle.split.3x1", isOn: list == .board) { list = .board }
                            FilterChip(title: "Open", symbol: "circle", isOn: list == .open) { list = .open }
                            FilterChip(title: "Closed", symbol: Symbol.check, isOn: list == .closed) { list = .closed }
                        }
                        .overlay(Rectangle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
                    }
                }
                // A refresh that failed over a board loaded before.
                ActionError(message: github.error)
            }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    private func boardList(_ board: GitHubBoard) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.xs) {
                ForEach(board.groups(repo: repo, priority: priority), id: \.status) { group in
                    let folded = GitHubBoard.isDone(group.status) != toggled.contains(group.status)
                    Button {
                        if toggled.contains(group.status) { toggled.remove(group.status) } else { toggled.insert(group.status) }
                    } label: {
                        HStack(spacing: Space.s) {
                            Image(systemName: folded ? Symbol.chevronRight : Symbol.chevronDown)
                                .font(.system(size: Icon.xxs, weight: .bold)).frame(width: Icon.xxs)
                            Text(group.status.isEmpty ? "No status" : group.status).typeRole(.label)
                            Text("\(group.items.count)").typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Ink.text.primary)
                        .padding(.top, Space.m).padding(.bottom, Space.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityHint(folded ? "Show the issues" : "Hide the issues")
                    if !folded {
                        ForEach(group.items) { item in
                            GitHubIssueRow(ref: item.id, title: item.title, priority: item.priority, labels: item.labels,
                                           isClosed: item.state == "closed") { issue = IssueRef(repo: item.repo, number: item.number) }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.l).padding(.bottom, Space.l)
        }
    }
}

/// A repo's open or closed issues, the 100 most recently updated.
private struct RepoIssues: View {
    let repo: String
    let state: String
    let onSelect: (Int) -> Void

    @Environment(AppModel.self) private var model
    @State private var list: GitHubIssueList?
    @State private var error: String?

    var body: some View {
        Group {
            if let list {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.xs) {
                        Text(list.total > list.issues.count ? "\(list.issues.count) of \(list.total) \(state), recently updated first" : "\(list.total) \(state)")
                            .typeRole(.label).foregroundStyle(Ink.text.secondary).padding(.vertical, Space.m)
                        ForEach(list.issues) { issue in
                            let comments = issue.comments == 1 ? "1 comment" : "\(issue.comments) comments"
                            GitHubIssueRow(ref: "\(repo)#\(issue.number)", title: issue.title, priority: "", labels: issue.labels,
                                           isClosed: issue.state == "closed", detail: comments) { onSelect(issue.number) }
                        }
                    }
                    .padding(.horizontal, Space.l).padding(.bottom, Space.l)
                }
            } else {
                Text(error ?? "Loading…").typeRole(.caption).foregroundStyle(error == nil ? Ink.text.muted : Ink.text.error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard let rest = model.github?.rest else { return }
            do { list = try await rest.githubIssues(repo: repo, state: state) } catch { self.error = GitHubError.describe(error) }
        }
    }
}

/// `owner/repo#n`, priority and state over the title; labels on the right.
struct GitHubIssueRow: View {
    let ref: String
    let title: String
    let priority: String
    let labels: [String]
    let isClosed: Bool
    var detail: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.s) {
                        Text(ref).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).lineLimit(1)
                        if !priority.isEmpty { PriorityMark(priority: priority) }
                        if isClosed { Text("closed").typeRole(.label).foregroundStyle(Ink.text.secondary) }
                        if let detail { Text(detail).typeRole(.monoSmall).foregroundStyle(Ink.text.muted).lineLimit(1) }
                    }
                    Text(title).typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Space.s)
                TagChips(tags: labels.withoutPriority(priority), limit: 3)
                Image(systemName: Symbol.chevronRight).font(.system(size: Icon.s)).foregroundStyle(Ink.text.secondary)
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(Ink.surface.raised)
            .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the issue")
    }
}

/// The priority as an ink tag, like a news edition's feed tag.
struct PriorityMark: View {
    let priority: String

    var body: some View {
        Text(priority).typeRole(.label).foregroundStyle(Ink.surface.window)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xxs).background(Ink.surface.inverse)
            .accessibilityLabel("Priority \(priority)")
    }
}

/// `not_configured`: what the relay needs.
private struct SetupNote: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("GitHub is not set up").typeRole(.label).foregroundStyle(Ink.text.primary)
            Text(text).typeRole(.callout).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            Text("GITHUB_TOKEN=… in the relay's .env, then restart the relay. The token needs read and write access to the owner's issues and the Work project.")
                .typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(Space.l)
        .frame(maxWidth: Size.chatColumn, alignment: .leading)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Markdown as the chat renders an answer: prose with inline styles (line breaks kept as written), fenced code as
/// `CodeBlockView`, pipe tables as `MarkdownTableView`. HTML in the prose and the cells is dropped (`stripHTML`).
struct GitHubMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let s):
                    let s = MarkdownBlocks.stripHTML(s)
                    Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
                        .typeRole(.body).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .table(let header, let rows, let alignments):
                    MarkdownTableView(header: header, rows: rows, alignments: alignments, clean: MarkdownBlocks.stripHTML)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A Markdown pipe table (`MarkdownBlock.table`): a header row in the label role, hairline rules, cells that size to
/// their text up to a third of the chat column and wrap past it; a wide table scrolls sideways.
struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]
    let alignments: [MarkdownBlock.Alignment]
    /// Cell text is run through this first (GitHub text drops its HTML).
    var clean: (String) -> String = { $0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                rule
                GridRow { ForEach(header.indices, id: \.self) { cell(header[$0], column: $0, role: .label, color: Ink.text.secondary) } }
                rule
                ForEach(rows.indices, id: \.self) { r in
                    GridRow { ForEach(header.indices, id: \.self) { cell(rows[r][$0], column: $0, role: .body, color: Ink.text.primary) } }
                    rule
                }
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline).gridCellColumns(header.count)
    }

    private func cell(_ text: String, column: Int, role: TypeRole, color: Color) -> some View {
        let text = clean(text)
        let alignment = alignments[column]
        return Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .typeRole(role).foregroundStyle(color).textSelection(.enabled)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .frame(maxWidth: Size.chatColumn / 3, alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
    }
}
