import Foundation

/// One tool call as the terminal pane shows it: `$ command`, then output, exit code and duration.
public struct TerminalEntry: Sendable, Equatable, Identifiable {
    /// The seq of the call's first event.
    public var id: Int
    public var runID: String
    public var tool: String
    /// Unix milliseconds of the first event.
    public var time: Int
    /// The `tool.started` preview; nil when the start was missed (replay gap).
    public var command: String?
    /// Terminal tool: the parsed `output`. Other tools and unparsable previews: the raw preview.
    public var output: String?
    public var exitCode: Int?
    /// The terminal tool's own `error` text (e.g. "BLOCKED: Command denied by user. ...").
    public var errorText: String?
    /// The completed event's error flag.
    public var isError: Bool
    /// The terminal preview was not valid JSON (the relay cuts previews at 4,000 characters); `output` is the raw text.
    public var isTruncated: Bool
    /// Seconds; nil while running.
    public var duration: Double?
    /// Started, not completed.
    public var isRunning: Bool

    public var isCommand: Bool { tool == TerminalTranscript.terminalTool }
    public var failed: Bool { isError || (exitCode ?? 0) != 0 }
}

/// What the chat marker of a run shows: `4 COMMANDS · 6.1 s · 1 failed`.
public struct RunSummary: Sendable, Equatable {
    public var commandCount: Int
    /// Seconds, completed commands only.
    public var totalDuration: Double
    public var failedCount: Int

    public var label: String {
        var parts = ["\(commandCount) \(commandCount == 1 ? "COMMAND" : "COMMANDS")", String(format: "%.1f s", totalDuration)]
        if failedCount > 0 { parts.append("\(failedCount) failed") }
        return parts.joined(separator: " · ")
    }
}

public enum TerminalTranscript {
    public static let terminalTool = "terminal"

    public enum Filter: Sendable { case commands, all }

    /// Pairs `tool.started` with `tool.completed` in order. The events carry no call id, so a completion belongs to the
    /// oldest unfinished call of the same tool in the same run; a completion without a start (replay gap) is its own entry.
    public static func entries(from events: [Event], filter: Filter = .all) -> [TerminalEntry] {
        var entries: [TerminalEntry] = []
        var open: [String: [Int]] = [:] // "run|tool" → indexes of running entries, oldest first
        for e in events {
            switch e.payload {
            case .toolStarted(let s):
                open["\(e.runID)|\(s.tool)", default: []].append(entries.count)
                entries.append(TerminalEntry(
                    id: e.seq, runID: e.runID, tool: s.tool, time: e.ts, command: s.preview, isError: false,
                    isTruncated: false, isRunning: true))
            case .toolCompleted(let c):
                let key = "\(e.runID)|\(c.tool)"
                let i: Int
                if let first = open[key]?.first {
                    open[key]?.removeFirst()
                    i = first
                } else {
                    i = entries.count
                    entries.append(TerminalEntry(
                        id: e.seq, runID: e.runID, tool: c.tool, time: e.ts, isError: false, isTruncated: false, isRunning: true))
                }
                complete(&entries[i], c)
            default: break
            }
        }
        return filter == .commands ? entries.filter(\.isCommand) : entries
    }

    /// Commands of one run (or of every run in `entries`).
    public static func summary(of entries: [TerminalEntry], runID: String? = nil) -> RunSummary {
        let cmds = entries.filter { $0.isCommand && (runID == nil || $0.runID == runID) }
        return RunSummary(
            commandCount: cmds.count, totalDuration: cmds.reduce(0) { $0 + ($1.duration ?? 0) },
            failedCount: cmds.filter(\.failed).count)
    }

    private static func complete(_ entry: inout TerminalEntry, _ c: ToolCompleted) {
        entry.isRunning = false
        entry.isError = c.error
        entry.duration = c.duration
        guard let preview = c.preview else { return }
        guard entry.isCommand else {
            entry.output = preview
            return
        }
        if let r = try? JSONDecoder().decode(TerminalResult.self, from: Data(preview.utf8)) {
            entry.output = r.output
            entry.exitCode = r.exitCode
            entry.errorText = r.error
        } else {
            entry.output = preview
            entry.isTruncated = true
        }
    }
}

/// The terminal tool's `tool.completed` preview.
private struct TerminalResult: Decodable {
    var output: String?
    var exitCode: Int?
    var error: String?
    enum CodingKeys: String, CodingKey { case output, exitCode = "exit_code", error }
}
