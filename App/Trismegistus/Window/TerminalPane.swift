import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Read-only transcript of the selected conversation's tool calls (live events only), newest at the bottom.
struct TerminalPane: View {
    let sessionID: String?

    @Environment(AppModel.self) private var model
    @AppStorage("window.terminalCommandsOnly") private var commandsOnly = true

    private var state: SessionState? { sessionID.flatMap { model.store?.sessions[$0] } }

    private var entries: [TerminalEntry] {
        guard let state else { return [] }
        return TerminalTranscript.entries(from: state.events, filter: commandsOnly ? .commands : .all)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.rule).frame(height: 1)
            transcript
            Text("Output arrives when a command finishes, cut at 4,000 characters.")
                .typeRole(.caption).foregroundStyle(Theme.muted)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
        }
        .background(Theme.paper)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Terminal").typeRole(.label)
            if let run = (state?.run?.id ?? entries.last?.runID) {
                Text("run \(run.prefix(4))").typeRole(.monoSmall).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            FilterChip(title: "Commands", symbol: Symbol.terminal, isOn: commandsOnly) { commandsOnly = true }
            FilterChip(title: "All tools", symbol: Symbol.list, isOn: !commandsOnly) { commandsOnly = false }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private var transcript: some View {
        if entries.isEmpty {
            Text(sessionID == nil ? "Select a conversation." : "No commands yet.")
                .typeRole(.caption).foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(entries) { EntryRow(entry: $0) }
                }
                .padding(16)
                // Read-only, but selectable across entries so commands and output can be copied.
                .textSelection(.enabled)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
        }
    }
}

private struct FilterChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).textCase(.uppercase)
                Image(systemName: symbol)
            }
            .typeRole(.button)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(isOn ? Theme.yellow : Theme.ink)
            .background(isOn ? Theme.ink : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct EntryRow: View {
    let entry: TerminalEntry

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TerminalEntryView(
                meta: "── \(Self.time(entry.time)) \(entry.tool)", command: entry.command ?? "…", output: output,
                exitCode: entry.exitCode, isRunning: entry.isRunning)
            trailing
        }
    }

    /// The running entry says why it has no output yet, as in the draft.
    private var output: String? {
        if entry.isRunning { return "output arrives when it finishes" }
        var lines: [String] = []
        // Only the terminal tool reports an exit code; other tools show their failure here.
        if entry.isError, entry.exitCode == nil { lines.append("✘ the tool reported an error") }
        if let text = entry.output, !text.isEmpty { lines.append(text) }
        if let text = entry.errorText, !text.isEmpty { lines.append(text) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    @ViewBuilder private var trailing: some View {
        if entry.isRunning {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let s = max(0, Int(context.date.timeIntervalSince1970 - Double(entry.time) / 1000))
                Text(String(format: "%02d:%02d", s / 60, s % 60)).typeRole(.monoSmall).foregroundStyle(Theme.blue)
            }
        } else if let duration = entry.duration {
            Text(String(format: "%.1f s", duration)).typeRole(.monoSmall).foregroundStyle(Theme.muted)
        }
    }

    private static func time(_ ms: Int) -> String {
        Date(timeIntervalSince1970: Double(ms) / 1000).formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
    }
}
