import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The Agents section's sidebar: `AGENTS // n RUNNING`, the filter, one row per agent.
struct AgentsSidebar: View {
    @Binding var selection: String?
    var filterFocus: FocusState<Bool>.Binding

    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        let board = model.agents
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let agents = (board?.agents ?? []).filter {
            needle.isEmpty || [$0.title, $0.issueTitle, $0.issueRef].contains { $0?.localizedCaseInsensitiveContains(needle) == true }
        }
        VStack(spacing: 0) {
            SidebarHeader(title: "Agents // \(board?.runningCount ?? 0) running", prompt: "Filter agents", filter: $filter,
                          focus: filterFocus)
            if let board, board.agents.isEmpty {
                SidebarNote(text: board.notConfigured ? "Not set up."
                    : board.isLoaded ? "No background agents running or finished in the last day." : "Reading the agents…")
            } else if board == nil {
                SidebarNote(text: "Not connected.")
            }
            List(selection: $selection) {
                ForEach(agents) { agent in
                    AgentRow(agent: agent, isSelected: selection == agent.id).tag(agent.id).sidebarRow()
                }
            }
            .sidebarList()
        }
    }
}

/// Background work on optiplex (Claude Code delegate runs, Hermes background processes): the selected agent's detail
/// and transcript at full height. The list is fetched every 3 s while shown. Hermes subagents are not here: the relay
/// can't see them.
struct AgentsView: View {
    @Binding var selection: String?
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let board = model.agents {
                content(board)
                    .task(id: ObjectIdentifier(board)) {
                        while !Task.isCancelled {
                            await board.refresh()
                            try? await Task.sleep(for: .seconds(3))
                        }
                    }
                    .onChange(of: board.agents.map(\.id), initial: true) { _, ids in
                        if board.isLoaded { selection = WindowSection.kept(selection, in: ids) }
                    }
            } else {
                Text("Not connected.").typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.surface.window)
    }

    @ViewBuilder private func content(_ board: AgentBoard) -> some View {
        if board.notConfigured {
            NotConfigured()
        } else {
            VStack(spacing: 0) {
                if let error = board.error { notice(error, board: board) }
                if let agent = board.agents.first(where: { $0.id == selection }) {
                    AgentDetail(agent: agent, board: board, onOpen: onOpen).id(agent.id)
                } else {
                    SectionEmpty(symbol: WindowSection.agents.symbol, text: board.isLoaded ? "No agent selected" : "Reading the agents…")
                }
            }
        }
    }

    /// One line over the agents already fetched, which stay.
    private func notice(_ error: AgentsError, board: AgentBoard) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: JobsView.failedSymbol).font(.system(size: Icon.m)).accessibilityHidden(true)
            Text(AgentsError.describe(error)).typeRole(.callout).lineLimit(2)
            Spacer(minLength: Space.s)
            EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { Task { await board.refresh() } }
        }
        .foregroundStyle(Ink.text.secondary)
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .background(Ink.surface.sunken)
    }
}

/// The helper isn't installed on optiplex yet (the relay answers `not_configured`).
private struct NotConfigured: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Agents helper not running").typeRole(.label).foregroundStyle(Ink.text.primary)
            Text("The agents helper isn't running on optiplex: see agents/README.md in the relay repo.")
                .typeRole(.callout).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.l)
        .frame(maxWidth: Size.chatColumn, alignment: .leading)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// An agent in the sidebar: title and how it stands, then kind, start or end, turns and duration, then its last
/// progress line (a process shows its command).
private struct AgentRow: View {
    let agent: Agent
    let isSelected: Bool

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        let ink = RowInk(onSidebar: onSidebar, isSelected: isSelected)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    if agent.alive {
                        Circle().fill(Ink.status.online).frame(width: Size.dot, height: Size.dot)
                            .overlay(Circle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
                            .accessibilityHidden(true)
                    }
                    Text(agent.issueTitle ?? agent.title).typeRole(.headline).foregroundStyle(ink.title).lineLimit(1)
                    Spacer(minLength: Space.s)
                    Text(agent.statusWords).typeRole(.label).foregroundStyle(agent.failed ? ink.error : ink.meta)
                }
                Text(AgentFacts.line(agent, now: context.date)).typeRole(.monoSmall).foregroundStyle(ink.meta).lineLimit(1)
                if let line = agent.progress ?? agent.command {
                    Text(line).typeRole(.monoSmall).foregroundStyle(ink.meta).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
            .rowGround(isSelected: isSelected)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The facts line of a row and of the detail header.
@MainActor enum AgentFacts {
    /// `repo#12 · delegate · started 5 min ago` or `delegate · ended 2 hr ago · 41 turns · 1 hr, 2 min`.
    static func line(_ agent: Agent, now: Date) -> String {
        var parts = [agent.issueRef, agent.isDelegate ? "delegate" : "process"].compactMap { $0 }
        if agent.alive {
            if let start = agent.started { parts.append("started \(JobDetail.relative(start, now: now))") }
        } else {
            if let end = agent.ended ?? agent.started { parts.append("ended \(JobDetail.relative(end, now: now))") }
            if let turns = agent.numTurns { parts.append("\(turns) \(turns == 1 ? "turn" : "turns")") }
            if let ms = agent.durationMs, let words = duration(ms) { parts.append(words) }
        }
        return parts.joined(separator: " · ")
    }

    static func duration(_ ms: Int) -> String? {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.maximumUnitCount = 2
        return formatter.string(from: TimeInterval(ms) / 1000)
    }
}
