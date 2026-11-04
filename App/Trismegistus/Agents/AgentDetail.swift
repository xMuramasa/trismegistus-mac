import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The selected agent: how it stands and its buttons (open the conversation that started it, stop for a manager
/// device), then its transcript. A new one per agent (`.id`), so the transcript starts over.
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
            Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
            AgentTranscriptPane(agent: agent, transcript: transcript)
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
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text(agent.title).typeRole(.title).foregroundStyle(Ink.text.primary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: Space.s)
                if let id = agent.sessionID, canOpenConversation {
                    EndfieldButton("Open conversation", symbol: Symbol.chevronRight) { onOpen(id) }
                }
                if board.canManage, agent.alive {
                    if board.stopping.contains(agent.id) {
                        Text("Stopping…").typeRole(.label).foregroundStyle(Ink.text.secondary)
                    } else {
                        EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger) { confirmingStop = true }
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(summary(now: context.date)).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                    .lineLimit(2).textSelection(.enabled)
            }
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

/// The transcript on ink like the terminal pane: text as plain mono, a tool call as one line with a mark, its result
/// dimmed (red when it failed), the final answer as Markdown on a card. Follows the end unless scrolled up.
private struct AgentTranscriptPane: View {
    let agent: Agent
    let transcript: AgentTranscript

    @State private var position = ScrollPosition(edge: .bottom)
    @State private var atBottom = true

    var body: some View {
        Group {
            if !agent.hasTranscript {
                note("No transcript for this process.")
            } else if transcript.steps.isEmpty {
                if let error = transcript.error {
                    note(AgentsError.describe(error), isError: true)
                } else {
                    note(transcript.isLoaded ? "No steps yet." : "Reading the transcript…")
                }
            } else {
                steps
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.surface.terminal)
    }

    private func note(_ text: String, isError: Bool = false) -> some View {
        Text(text).typeRole(.caption).foregroundStyle(isError ? Ink.text.error : Ink.text.muted)
            .padding(Space.l).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var steps: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Space.s) {
                if transcript.dropped > 0 {
                    Text(verbatim: "\(transcript.dropped) earlier steps are not shown.").typeRole(.caption).foregroundStyle(Ink.text.muted)
                }
                ForEach(transcript.steps) { AgentStepRow(step: $0) }
                if let error = transcript.error {
                    Text(AgentsError.describe(error)).typeRole(.caption).foregroundStyle(Ink.text.error)
                }
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(.bottom)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - Space.xxl
        } action: { _, nowAtBottom in
            atBottom = nowAtBottom
        }
        .onChange(of: transcript.steps.last?.id) {
            if atBottom { position.scrollTo(edge: .bottom) }
        }
        .overlay(alignment: .bottomTrailing) {
            if !atBottom {
                EndfieldButton("Follow", symbol: Symbol.chevronDown, kind: .primary) {
                    atBottom = true
                    position.scrollTo(edge: .bottom)
                }
                .padding(Space.l)
            }
        }
    }
}

private struct AgentStepRow: View {
    let step: AgentStep

    var body: some View {
        switch step.kind {
        case .text, .unknown:
            Text(step.text).typeRole(.monoSmall).foregroundStyle(Ink.text.onDark)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        case .tool:
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: "hammer").font(.system(size: Icon.s)).foregroundStyle(Ink.selection).accessibilityLabel("Tool")
                Text(step.text).typeRole(.monoSmall, weight: .semibold).foregroundStyle(Ink.text.onDark).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .toolResult:
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Image(systemName: step.error ? Symbol.close : "arrow.turn.down.right").font(.system(size: Icon.s))
                    .accessibilityLabel(step.error ? "Tool failed" : "Tool result")
                Text(step.text).typeRole(.monoSmall).textSelection(.enabled)
            }
            .foregroundStyle(step.error ? Ink.text.error : Ink.text.onDark.opacity(Opacity.secondaryOnDark))
            .padding(.leading, Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .result:
            VStack(alignment: .leading, spacing: Space.s) {
                Text("Result").typeRole(.label).foregroundStyle(Ink.text.secondary)
                GitHubMarkdown(text: step.text)
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface.raised)
        }
    }
}
