import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The window sidebar's Agents row, after GitHub: how many background agents run on optiplex.
struct AgentsRowView: View {
    let board: AgentBoard?
    let isSelected: Bool

    @Environment(\.sunkenRows) private var sunken

    private var detail: String {
        guard let board else { return "not connected" }
        if board.notConfigured { return "not set up" }
        if board.error != nil, board.agents.isEmpty { return "can't load" }
        if !board.isLoaded { return "loading" }
        return board.runningCount > 0 ? "\(board.runningCount) running" : "idle"
    }

    var body: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Agents").typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(1)
                HStack(spacing: Space.s) {
                    Image(systemName: AgentsView.symbol).font(.system(size: Icon.m))
                    Text(detail).typeRole(.monoSmall).lineLimit(1)
                }
                .foregroundStyle(sunken ? Ink.text.secondary : Ink.text.muted)
            }
            Spacer(minLength: Space.s)
            if board?.anyRunning == true {
                Circle().fill(Ink.status.online).frame(width: Size.dot, height: Size.dot)
                    .overlay(Circle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
                    .accessibilityHidden(true)
            }
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

/// Background work on optiplex (Claude Code delegate runs, Hermes background processes): the list on top (up to four
/// rows, then it scrolls), the selected agent's detail and transcript below it. The list is fetched every 3 s while
/// shown. Hermes subagents are not here: the relay can't see them.
struct AgentsView: View {
    nonisolated static let id = "trismegistus.agents" // in selections; not a Hermes session id
    static let symbol = "cpu"
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @State private var selected: String?

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
                        if !ids.contains(selected ?? "") { selected = ids.first }
                    }
            } else {
                Text("Not connected.").typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.surface.window)
    }

    private func content(_ board: AgentBoard) -> some View {
        VStack(spacing: 0) {
            header(board)
            Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
            if board.notConfigured {
                NotConfigured()
            } else {
                if let error = board.error { notice(error, board: board) }
                list(board)
                Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
                if let agent = board.agents.first(where: { $0.id == selected }) {
                    AgentDetail(agent: agent, board: board, onOpen: onOpen).id(agent.id)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func header(_ board: AgentBoard) -> some View {
        HStack(spacing: Space.s) {
            Text("Agents // \(board.runningCount) running").typeRole(.label).foregroundStyle(Ink.text.secondary)
            Spacer(minLength: Space.s)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
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

    @ViewBuilder private func list(_ board: AgentBoard) -> some View {
        if board.agents.isEmpty {
            Text(board.isLoaded ? "No background agents running or finished in the last day." : "Reading the agents…")
                .typeRole(.caption).foregroundStyle(Ink.text.muted)
                .padding(Space.l).frame(maxWidth: .infinity)
        } else {
            let rows = VStack(spacing: 0) {
                ForEach(board.agents) { agent in
                    Button { selected = agent.id } label: { AgentRow(agent: agent, isSelected: selected == agent.id) }
                        .buttonStyle(.plain)
                }
            }
            if board.agents.count <= 4 {
                rows
            } else {
                ScrollView { rows }.frame(height: Size.row * 4.5)
            }
        }
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

/// An agent in the list: title and how it stands, then kind, start or end, turns and duration, then its last
/// progress line (a process shows its command).
private struct AgentRow: View {
    let agent: Agent
    let isSelected: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    if agent.alive {
                        Circle().fill(Ink.status.online).frame(width: Size.dot, height: Size.dot)
                            .overlay(Circle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
                            .accessibilityHidden(true)
                    }
                    Text(agent.title).typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(1)
                    Spacer(minLength: Space.s)
                    Text(agent.statusWords).typeRole(.label).foregroundStyle(agent.failed ? Ink.text.error : Ink.text.secondary)
                }
                Text(AgentFacts.line(agent, now: context.date)).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).lineLimit(1)
                if let line = agent.progress ?? agent.command {
                    Text(line).typeRole(.monoSmall).foregroundStyle(Ink.text.muted).lineLimit(1).truncationMode(.tail)
                }
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
            .rowGround(isSelected: isSelected)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The facts line of a row and of the detail header.
@MainActor enum AgentFacts {
    /// `delegate · started 5 min ago` or `delegate · ended 2 hr ago · 41 turns · 1 hr, 2 min`.
    static func line(_ agent: Agent, now: Date) -> String {
        var parts = [agent.isDelegate ? "delegate" : "process"]
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
