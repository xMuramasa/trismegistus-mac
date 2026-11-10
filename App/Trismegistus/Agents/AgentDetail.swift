import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The selected agent: how it stands and its buttons (open the conversation that started it, stop for a manager
/// device), then the run. A new one per agent (`.id`), so the transcript starts over.
struct AgentDetail: View {
    let agent: Agent
    let board: AgentBoard
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @State private var transcript: AgentTranscript
    @State private var confirmingStop = false
    /// The relay's or the helper's refusal of the last stop.
    @State private var error: String?

    init(agent: Agent, board: AgentBoard, onOpen: @escaping (String) -> Void) {
        self.agent = agent
        self.board = board
        self.onOpen = onOpen
        _transcript = State(initialValue: AgentTranscript(id: agent.id, rest: board.rest))
    }

    private var canOpenConversation: Bool {
        agent.sessionID.map { id in model.sessions.contains { $0.id == id } } ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if agent.command != nil || error != nil { commandLine }
            AgentRunPane(agent: agent, transcript: transcript)
        }
        // Polls every 2 s while the agent is alive and this view is shown; a finished agent loads once.
        .task { if agent.hasTranscript { await transcript.follow() } }
        .alert("Stop \(agent.title)?", isPresented: $confirmingStop) {
            Button("Stop", role: .destructive) { stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its process tree is ended.")
        }
    }

    private var header: some View {
        DetailHeader {
            Text(agent.title).truncationMode(.middle)
        } subtitle: {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(summary(now: context.date)).textSelection(.enabled)
            }
        } trailing: {
            if let id = agent.sessionID, canOpenConversation {
                EndfieldButton("Open conversation", symbol: Symbol.chevronRight) { onOpen(id) }
            }
            if board.canManage, agent.alive {
                if board.stopping.contains(agent.id) {
                    Text("Stopping…").typeRole(.label)
                } else {
                    EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger) { confirmingStop = true }
                }
            }
            DetailTools(section: .agents)
        }
    }

    /// The agent's command and the last refusal, under the band.
    private var commandLine: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if let command = agent.command {
                Text(command).typeRole(.monoSmall).foregroundStyle(Ink.text.muted).lineLimit(2).truncationMode(.middle)
                    .textSelection(.enabled)
            }
            ActionError(message: error)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `running · delegate · started 5 min ago · /wt/issue-22`.
    private func summary(now: Date) -> String {
        var parts = [agent.statusWords, AgentFacts.line(agent, now: now)]
        if let cwd = agent.cwd { parts.append(cwd) }
        return parts.joined(separator: " · ")
    }

    private func stop() {
        error = nil
        Task {
            do {
                try await board.stop(agent)
            } catch {
                self.error = AgentsError.describe(error)
            }
        }
    }
}

/// The run under the header: the result on top (the last progress line while it runs), then its steps in one card, open
/// by default because they are this screen's content. A process has neither.
private struct AgentRunPane: View {
    let agent: Agent
    let transcript: AgentTranscript

    @State private var stepsOpen = true
    @State private var openRows: Set<String> = []

    var body: some View {
        if agent.hasTranscript {
            let rows = AgentRun.rows(of: transcript.steps, cwd: agent.cwd)
            AgentRunScroll(alive: agent.alive) {
                VStack(spacing: Space.xxl) {
                    result
                    if transcript.steps.isEmpty {
                        if let error = transcript.error {
                            note(AgentsError.describe(error), isError: true)
                        } else {
                            note(transcript.isLoaded ? "No steps yet." : "Reading the transcript…")
                        }
                    } else {
                        steps(rows)
                    }
                }
            }
        } else {
            note("No transcript for this process.").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func note(_ text: String, isError: Bool = false) -> some View {
        Text(text).typeRole(.caption).foregroundStyle(isError ? Ink.text.error : Ink.text.muted).padding(Space.l)
    }

    private var chipKind: StatusChip.Kind {
        switch agent.tone {
        case .ok: .ok
        case .warn: .warn
        case .err: .err
        case .neutral: .neutral
        }
    }

    private var result: some View {
        let report = agent.alive ? nil : AgentRun.report(of: transcript.steps)
        let title = report.map { MarkdownText.styled($0.title) }
            ?? AttributedString(agent.alive ? agent.progress ?? "No progress yet." : "No report.")
        return TimelineView(.periodic(from: .now, by: 30)) { context in
            AgentResultCard(chip: StatusChip(agent.statusWords, kind: chipKind), meta: AgentFacts.result(agent, now: context.date), title: title) {
                if let report, !report.body.isEmpty { GitHubMarkdown(text: report.body) }
            }
        }
    }

    private func steps(_ rows: [AgentRow]) -> some View {
        let nameWidth = rows.contains { ($0.tool?.count ?? 0) > AgentRun.shortName } ? Size.toolRow.nameWide : Size.toolRow.name
        return AgentStepsCard(line: AgentRun.stepsLine(rows), isOpen: $stepsOpen) {
            LazyVStack(spacing: 0) {
                if transcript.dropped > 0 { ToolNarration("\(transcript.dropped) earlier steps are not shown.") }
                ForEach(rows) { row in
                    if let tool = row.tool {
                        ToolCallRow(symbol: agentToolSymbol(tool), tool: tool, command: row.text, failed: row.failed, output: row.output,
                                    nameWidth: nameWidth, isOpen: isOpen(row))
                    } else {
                        ToolNarration(String(MarkdownText.styled(row.text).characters))
                    }
                }
                if let error = transcript.error {
                    Text(AgentsError.describe(error)).typeRole(.caption).foregroundStyle(Ink.text.error)
                        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func isOpen(_ row: AgentRow) -> Binding<Bool> {
        Binding {
            openRows.contains(row.id)
        } set: { open in
            if open { openRows.insert(row.id) } else { openRows.remove(row.id) }
        }
    }
}
