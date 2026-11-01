import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Read-only transcript of the selected conversation's tool calls, newest at the bottom: the Hermes history (every
/// run, wherever it started, output in full) plus the live events it doesn't have yet.
struct TerminalPane: View {
    let sessionID: String?

    @Environment(AppModel.self) private var model
    @Environment(CommandLog.self) private var log: CommandLog?
    @AppStorage("window.terminalCommandsOnly") private var commandsOnly = true

    private var state: SessionState? { sessionID.flatMap { model.store?.sessions[$0] } }

    private var entries: [TerminalEntry] {
        guard let sessionID else { return [] }
        let live = state.map { TerminalTranscript.entries(from: $0.events) } ?? []
        let all = TerminalTranscript.merged(history: log?.entries(of: sessionID) ?? [], live: live)
        return commandsOnly ? all.filter(\.isCommand) : all
    }

    var body: some View {
        let entries = entries
        VStack(spacing: 0) {
            header(entries)
            Rectangle().fill(Theme.rule).frame(height: 1)
            transcript(entries)
            Text("Live output arrives when a command finishes, cut at 4,000 characters; the history has it in full.")
                .typeRole(.caption).foregroundStyle(Theme.muted)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        }
        .settledWidth(minimum: 280)
        .background(Theme.paper)
        // Runs started elsewhere (Telegram, cron, the CLI) send no live events: ask the history while the pane shows.
        .task(id: TaskKey(sessionID: sessionID, log: log.map(ObjectIdentifier.init))) {
            guard let sessionID, let log else { return }
            // Not while the pane is still opening.
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                await log.sync(sessionID)
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private struct TaskKey: Equatable {
        var sessionID: String?
        var log: ObjectIdentifier?
    }

    /// Title on its own line, the filter below as two halves: the pane can be 280 pt wide, too narrow for title and
    /// both chips on one line (they wrapped letter by letter).
    private func header(_ entries: [TerminalEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Terminal").typeRole(.label).lineLimit(1)
                if let run = (state?.run?.id ?? entries.last?.runID), !run.isEmpty {
                    Text("run \(run.prefix(4))").typeRole(.monoSmall).foregroundStyle(Theme.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                FilterChip(title: "Commands", symbol: Symbol.terminal, isOn: commandsOnly, fills: true) { commandsOnly = true }
                Rectangle().fill(Theme.rule).frame(width: 1)
                FilterChip(title: "All tools", symbol: Symbol.list, isOn: !commandsOnly, fills: true) { commandsOnly = false }
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private func transcript(_ entries: [TerminalEntry]) -> some View {
        if entries.isEmpty {
            Text(sessionID == nil ? "Select a conversation." : "No commands yet.")
                .typeRole(.caption).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(entries) { EntryRow(entry: $0) }
                }
                .padding(16)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
        }
    }
}

struct FilterChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    /// Stretch to the width offered (a half of a segmented row) instead of hugging the label.
    var fills = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Never wrap: a narrow pane squeezed the labels into one letter column ("COM/MAN/DS").
                Text(title).textCase(.uppercase).lineLimit(1).fixedSize()
                Image(systemName: symbol)
            }
            .typeRole(.button)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: fills ? .infinity : nil)
            .foregroundStyle(isOn ? Theme.yellow : Theme.ink)
            .background(isOn ? Theme.ink : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct EntryRow: View {
    let entry: TerminalEntry

    var body: some View {
        TerminalEntryView(
            title: "\(Self.time(entry.time)) \(entry.tool)", detail: entry.cwd,
            command: entry.command ?? "…", output: output, exitCode: entry.exitCode, isRunning: entry.isRunning,
            startedAt: Date(timeIntervalSince1970: Double(entry.time) / 1000), duration: entry.duration)
    }

    /// The running entry says why it has no output yet, as in the draft.
    private var output: String? {
        if entry.isRunning { return "output arrives when it finishes" }
        if entry.awaitsResult { return "no result in the history yet" }
        var lines: [String] = []
        // Only the terminal tool reports an exit code; other tools show their failure here.
        if entry.isError, entry.exitCode == nil { lines.append("✘ the tool reported an error") }
        if let text = entry.output, !text.isEmpty { lines.append(text) }
        if let text = entry.errorText, !text.isEmpty { lines.append(text) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// `14:02:11`, with the day before it when it isn't today (history reaches back days).
    private static func time(_ ms: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let clock = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
        return Calendar.current.isDateInToday(date) ? clock : date.formatted(.dateTime.day().month(.abbreviated)) + " " + clock
    }
}
