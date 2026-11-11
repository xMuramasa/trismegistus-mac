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
    // An answered inbox item selects the next one in the sidebar.
    @AppStorage(WindowSection.github.selectionKey) private var selectedIssue = ""
    @State private var checkNote = ""
    /// What the answer posted: the check panel's folded line until the status has moved on.
    @State private var answered: CheckPanel.Result?

    /// The run working on this issue, from the agents list the board polls.
    private var run: Agent? { model.agents?.run(on: repo, issue: number) }

    private var issueID: String { "\(repo)#\(number)" }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let issue { readout(issue) }
            if run != nil || actionError != nil { runPanel }
            if let issue {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.l) {
                        if GitHubInbox.isNeedsCheck(issue.status) { checkPanel(issue) }
                        post(author: issue.author, date: issue.createdAt, text: issue.body.isEmpty ? "*No description.*" : issue.body)
                        if issue.commentsTotal > issue.comments.count {
                            Text(verbatim: "\(issue.commentsTotal - issue.comments.count) older comments are on GitHub")
                                .typeRole(.caption).foregroundStyle(Ink.text.muted)
                        }
                        ForEach(issue.comments, id: \.url) { post(author: $0.author, date: $0.createdAt, text: $0.body) }
                        if github.isManager { composer }
                    }
                    .frame(maxWidth: Size.issueColumn, alignment: .leading)
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
        DetailHeader {
            Text(issue?.title ?? "").lineLimit(2).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        } subtitle: {
            Text(verbatim: issue.map { "\(issueID) · \($0.isOpen ? "open" : "closed") · \(Self.age($0.createdAt))" } ?? issueID)
        } trailing: {
            if let run, run.alive {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    RunningMark(detail: [run.model, PopoverFormat.ago(run.started, now: context.date)].compactMap { $0 }.joined(separator: " · "))
                }
            }
            if let issue {
                if let tasks = issue.taskReading { TaskReading(tasks) }
                // One yellow: Looks good while the check panel shows, else Dispatch, else Start conversation.
                let option = GitHubDispatch.option(labels: issue.labels, isOpen: issue.isOpen, canManage: github.isManager,
                                                   hasLiveRun: run?.alive == true)
                let checking = GitHubInbox.isNeedsCheck(issue.status)
                EndfieldButton("Open in browser", symbol: "arrow.up.right", kind: .quiet, iconOnly: true) { openInBrowser(issue) }
                EndfieldButton("Start conversation", symbol: "bubble.left.and.text.bubble.right",
                               kind: option == .button || checking ? .secondary : .primary) { startConversation(issue) }
                    .disabled(busy || model.store == nil)
                switch option {
                case .button:
                    EndfieldButton("Dispatch", symbol: "play.fill", kind: checking ? .secondary : .primary) { dispatch(issue) }
                        .disabled(busy || model.store == nil)
                case .hidden(let tooltip): DispatchHiddenMark(reason: tooltip)
                case .none: EmptyView()
                }
            }
            DetailTools(section: .github)
        }
    }

    /// The run and the last refusal, under the readout.
    private var runPanel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let run, let board = model.agents { runRow(run, board: board) }
            ActionError(message: actionError)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .background(Ink.surface.frosted)
    }

    /// Status and Priority by option name, close/reopen: managers. Viewers see the fields as text. One row: the Tags cell
    /// shows as many tags as fit (#73: a `ViewThatFits` over whole rows with these native menus never settled and froze
    /// the window).
    private func readout(_ issue: GitHubIssue) -> some View {
        let tags = issue.labels.withoutPriority(issue.priority).withoutAgent
        let board = github.isManager ? github.board : nil
        return ReadoutRow {
            ReadoutCell("Status") {
                if let board {
                    field("Status", value: issue.status, options: board.statusOptions) { set(issue, status: $0) }
                } else {
                    reading(issue.onBoard ? issue.status : "Not on the Work board")
                }
            }
            ReadoutCell("Priority") {
                if let board {
                    field("Priority", value: issue.priority, options: board.priorityOptions, width: nil) { set(issue, priority: $0) }
                } else {
                    reading(issue.priority)
                }
            }
            ReadoutCell("Tags") { ReadoutTags(tags) }.readoutFills()
            ReadoutCell("Agent") { ReadoutTag(issue.labels.agentValue ?? "none") }
        } trailing: {
            if github.isManager {
                if issue.isOpen {
                    EndfieldButton("Close issue", symbol: "checkmark.circle") { setOpen(issue, false) }.disabled(busy)
                } else {
                    EndfieldButton("Reopen issue", symbol: "arrow.uturn.backward") { setOpen(issue, true) }.disabled(busy)
                }
            }
        }
    }

    private func reading(_ value: String) -> some View {
        Text(verbatim: value.isEmpty ? "none" : value).typeRole(.callout).lineLimit(1)
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

    /// A board field's menu (`ReadoutMenu`), off while a write is in flight.
    private func field(_ label: String, value: String, options: [String], width: CGFloat? = Size.readoutPicker,
                       set: @escaping (String) -> Void) -> some View {
        ReadoutMenu(label, value: value, options: options, width: width, set: set).disabled(busy)
    }

    private func post(author: String, date: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text(verbatim: "// \(author)").typeRole(.trackedLabel).foregroundStyle(Ink.text.secondary)
                Text(Self.age(date)).typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary)
            }
            GitHubMarkdown(text: text)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rounded(Radius.control, fill: Ink.surface.sectionCard, edge: Ink.line.rule)
    }

    private var composer: some View {
        VStack(alignment: .trailing, spacing: Space.s) {
            TextField("Comment on GitHub", text: $draft, prompt: Text("Comment on GitHub").foregroundStyle(Ink.text.secondary), axis: .vertical)
                .textFieldStyle(.plain)
                .typeRole(.body)
                .foregroundStyle(Ink.text.primary)
                .lineLimit(3...12)
                .padding(Space.m)
                .rounded(Radius.control, fill: Ink.surface.raised, edge: Ink.line.rule)
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
        busy = true
        Task {
            defer { busy = false }
            do {
                try await start(issue, prompt: GitHubPrompt.text(issue))
            } catch {
                actionError = GitHubError.describe(error)
            }
        }
    }

    private func start(_ issue: GitHubIssue, prompt: String) async throws {
        guard let store = model.store else { return }
        let session = try await store.createSession()
        // A refused title leaves Hermes' own; the conversation still starts.
        try? await store.renameSession(session.id, to: GitHubPrompt.title(issue))
        await model.send(prompt, to: session.id)
        onOpen(session.id)
    }

    /// Status Ready, then the chat that Hermes reacts to; a failed status write starts nothing. No confirm: the word is the commitment.
    private func dispatch(_ issue: GitHubIssue) {
        busy = true
        Task {
            defer { busy = false }
            do {
                try await GitHubInbox.dispatch(github.rest, repo: issue.repo, number: issue.number) {
                    try await start(issue, prompt: GitHubDispatch.prompt(repo: issue.repo, number: issue.number))
                }
                actionError = nil
            } catch {
                actionError = GitHubError.describe(error)
            }
            await github.refresh()
            await load()
        }
    }

    // MARK: Needs check

    private func checkPanel(_ issue: GitHubIssue) -> some View {
        let note = GitHubInbox.note(in: issue.comments)
        return CheckPanel(lines: note?.lines ?? [], source: note.map { "from Hermes · " + Self.stamp($0.date) } ?? "",
                          canAct: github.isManager, busy: busy, note: $checkNote, ticked: github.ticks.ticked(issueID), result: answered,
                          tick: { github.ticks.toggle($0, issue: issueID) },
                          looksGood: { answer(.confirmed) { try await GitHubInbox.confirm(github.rest, repo: issue.repo, number: issue.number) } },
                          notRight: {
                              let text = checkNote
                              answer(.notePosted) {
                                  try await GitHubInbox.reject(github.rest, repo: issue.repo, number: issue.number, note: text, isOpen: issue.isOpen)
                                  checkNote = ""
                              }
                          })
    }

    /// Writes, folds the panel, reads the board again and, from the inbox, selects the item after this one that is still there.
    private func answer(_ result: CheckPanel.Result, _ write: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            let before = github.board?.needsCheck().flatMap(\.items).map(\.id) ?? []
            var done = false
            do {
                try await write()
                actionError = nil
                answered = result
                done = true
            } catch {
                actionError = GitHubError.describe(error)
            }
            await github.refresh()
            if done, github.inboxShown, let at = before.firstIndex(of: issueID) {
                let left = Set(github.board?.needsCheck().flatMap(\.items).map(\.id) ?? [])
                if let next = (before[(at + 1)...] + before[..<at]).first(where: left.contains) {
                    selectedIssue = next
                    return
                }
            }
            await load()
            // A failed read keeps the fold: the answer went out, the panel must not offer it again.
            if let issue, !GitHubInbox.isNeedsCheck(issue.status) { answered = nil }
        }
    }

    /// `2 Nov 00:48` in the Mac's zone.
    static func stamp(_ text: String) -> String {
        let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
        return date?.formatted(.clock.day().month(.abbreviated).hour(.twoDigits(amPM: .omitted)).minute()) ?? text
    }

    static func age(_ text: String) -> String {
        let date = (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
        return PopoverFormat.ago(date, now: .now)
    }
}
