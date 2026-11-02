import AppKit
import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// One issue: `owner/repo#n`, title, state and board fields, the body and comments as Markdown. Actions:
/// open in the browser and start a conversation for every device; Status, Priority, close/reopen and commenting for a
/// manager only. None of them is destructive, so none asks first.
struct GitHubIssueView: View {
    let github: GitHubModel
    let repo: String
    let number: Int
    /// Opens a conversation in the window.
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @State private var issue: GitHubIssue?
    @State private var loadError: String?
    @State private var actionError: String?
    @State private var busy = false
    @State private var draft = ""
    @State private var confirmingStop = false
    // Opening a run's transcript sets the same keys the main window reads for its section and the Agents selection.
    @AppStorage("window.section") private var section = WindowSection.chat
    @AppStorage(WindowSection.agents.selectionKey) private var selectedAgent = ""

    /// The run working on this issue, from the agents list the board polls.
    private var run: Agent? { model.agents?.run(on: repo, issue: number) }

    var body: some View {
        VStack(spacing: 0) {
            header
            SegmentRule((Size.titleRule.magenta, Size.titleRule.yellow, Size.titleRule.green), height: Size.titleRule.height, stretches: true)
            if let issue {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        post(author: issue.author, date: issue.createdAt, text: issue.body.isEmpty ? "*No description.*" : issue.body)
                        if issue.commentsTotal > issue.comments.count {
                            Text("\(issue.commentsTotal - issue.comments.count) older comments are on GitHub")
                                .typeRole(.caption).foregroundStyle(Ink.text.muted)
                        }
                        ForEach(issue.comments, id: \.url) { post(author: $0.author, date: $0.createdAt, text: $0.body) }
                        if github.isManager { composer }
                    }
                    .frame(maxWidth: Size.chatColumn, alignment: .leading)
                    .padding(Space.l)
                    .frame(maxWidth: .infinity)
                }
            } else {
                Text(loadError ?? "Loading the issue…").typeRole(.caption)
                    .foregroundStyle(loadError == nil ? Ink.text.muted : Ink.text.error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.surface.window)
        .task { await load() }
        .alert("Stop \(run?.title ?? "the run")?", isPresented: $confirmingStop) {
            Button("Stop", role: .destructive) { stopRun() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its process tree is ended.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(spacing: Space.s) {
                        Text("\(repo)#\(number)").typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                        if let issue {
                            Text(issue.isOpen ? "open" : "closed").typeRole(.label).foregroundStyle(Ink.text.secondary)
                            if !issue.priority.isEmpty { PriorityMark(priority: issue.priority) }
                            TagChips(tags: issue.labels.withoutPriority(issue.priority), limit: 4)
                        }
                    }
                    Text(issue?.title ?? "").typeRole(.title).foregroundStyle(Ink.text.primary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Spacer(minLength: 0)
                if let run, run.alive {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        RunningMark(detail: [run.model, PopoverFormat.ago(run.started, now: context.date)].compactMap { $0 }.joined(separator: " · "))
                    }
                }
                if let issue {
                    EndfieldButton("Open in browser", symbol: "arrow.up.right", kind: .quiet, iconOnly: true) { openInBrowser(issue) }
                    EndfieldButton("Start conversation", symbol: "bubble.left.and.text.bubble.right", kind: .primary) { startConversation(issue) }
                        .disabled(busy || model.store == nil)
                }
            }
            if let issue { actions(issue) }
            if let run, let board = model.agents { runRow(run, board: board) }
            ActionError(message: actionError)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .background(Ink.surface.raised)
    }

    /// Status and Priority by option name, close/reopen: managers. Viewers see the fields as text.
    @ViewBuilder private func actions(_ issue: GitHubIssue) -> some View {
        let board = github.board
        HStack(spacing: Space.s) {
            if github.isManager, let board {
                field("Status", value: issue.status, options: board.statusOptions) { set(issue, status: $0) }
                field("Priority", value: issue.priority, options: board.priorityOptions) { set(issue, priority: $0) }
                Spacer(minLength: Space.s)
                if issue.isOpen {
                    EndfieldButton("Close issue", symbol: "checkmark.circle") { setOpen(issue, false) }.disabled(busy)
                } else {
                    EndfieldButton("Reopen issue", symbol: "arrow.uturn.backward") { setOpen(issue, true) }.disabled(busy)
                }
            } else {
                Text(issue.onBoard
                     ? "Status: \(issue.status.isEmpty ? "none" : issue.status) · Priority: \(issue.priority.isEmpty ? "none" : issue.priority)"
                     : "Not on the Work board")
                    .typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    /// The run in the Agents list's style; Stop (a manager's, while it runs) asks first, as in Agents.
    private func runRow(_ run: Agent, board: AgentBoard) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            IssueRunRow(model: run.model, age: PopoverFormat.ago(run.alive ? run.started : run.ended ?? run.started, now: context.date),
                        status: run.statusWords, isAlive: run.alive, failed: run.failed, progress: run.progress,
                        canStop: board.canManage && run.alive, isStopping: board.stopping.contains(run.id),
                        openTranscript: { selectedAgent = run.id; section = .agents }, stop: { confirmingStop = true })
        }
    }

    private func stopRun() {
        guard let run, let board = model.agents else { return }
        Task {
            do {
                try await board.stop(run)
                actionError = nil
            } catch {
                actionError = AgentsError.describe(error)
            }
        }
    }

    /// A menu of the board's options; picking one sets it. The unset value is shown but can't be picked.
    private func field(_ label: String, value: String, options: [String], set: @escaping (String) -> Void) -> some View {
        Picker(label, selection: Binding(get: { value }, set: { if !$0.isEmpty && $0 != value { set($0) } })) {
            Text("No \(label.lowercased())").tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .disabled(busy)
    }

    private func post(author: String, date: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(author).typeRole(.label).foregroundStyle(Ink.text.primary)
                Text(Self.age(date)).typeRole(.monoSmall).foregroundStyle(Ink.text.muted)
            }
            GitHubMarkdown(text: text)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: Space.s) {
            TextField("Comment on GitHub", text: $draft, prompt: Text("Comment on GitHub").foregroundStyle(Ink.text.secondary), axis: .vertical)
                .textFieldStyle(.plain)
                .typeRole(.body)
                .foregroundStyle(Ink.text.primary)
                .lineLimit(3...12)
                .padding(Space.m)
                .background(Ink.surface.raised)
                .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
            EndfieldButton("Comment", symbol: Symbol.send) { comment() }
                .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: Actions

    private func load() async {
        do {
            issue = try await github.rest.githubIssue(repo: repo, number: number)
            loadError = nil
        } catch {
            guard !Task.isCancelled else { return }
            loadError = GitHubError.describe(error)
        }
    }

    /// Runs a write, then reads the issue and the board again (the relay dropped its cache).
    private func act(_ write: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await write()
                actionError = nil
            } catch {
                actionError = GitHubError.describe(error)
            }
            await load()
            await github.refresh()
        }
    }

    private func set(_ issue: GitHubIssue, status: String? = nil, priority: String? = nil) {
        act { _ = try await github.rest.githubSetBoard(repo: issue.repo, number: issue.number, status: status, priority: priority) }
    }

    private func setOpen(_ issue: GitHubIssue, _ open: Bool) {
        act { try await github.rest.githubSetOpen(repo: issue.repo, number: issue.number, open) }
    }

    private func comment() {
        let text = draft
        act {
            _ = try await github.rest.githubComment(repo: repo, number: number, body: text)
            draft = ""
        }
    }

    private func openInBrowser(_ issue: GitHubIssue) {
        guard let url = URL(string: issue.url), url.scheme == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    /// A new relay conversation titled after the issue, its first prompt the issue; then the chat opens.
    private func startConversation(_ issue: GitHubIssue) {
        guard let store = model.store else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let session = try await store.createSession()
                // A refused title leaves Hermes' own; the conversation still starts.
                try? await store.renameSession(session.id, to: GitHubPrompt.title(issue))
                await model.send(GitHubPrompt.text(issue), to: session.id)
                onOpen(session.id)
            } catch {
                actionError = GitHubError.describe(error)
            }
        }
    }

    static func age(_ text: String) -> String {
        let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
        return PopoverFormat.ago(date, now: .now)
    }
}
