import Foundation

/// A tool call as a chat row shows it.
public struct ToolRow: Sendable, Equatable {
    public var tool: String
    public var summary: String
    public var duration: String
    public var output: String?
    public var exitCode: Int?
}

/// One row of the chat.
public enum ChatItem: Sendable, Equatable, Identifiable {
    case user(id: String, text: String, time: Date?)
    /// A prompt from the outbox: pending, sent (time of its run's first event) or failed.
    case prompt(OutgoingPrompt, time: Date?)
    case answer(id: String, text: String, time: Date?)
    case tool(id: String, ToolRow)
    case subagent(id: String, name: String, toolCount: Int, duration: String)
    /// The window's one marker per run; the terminal pane has the details.
    case marker(id: String, RunSummary)
    case note(id: String, text: String, isError: Bool)

    public var id: String {
        switch self {
        case .user(let id, _, _), .answer(let id, _, _), .tool(let id, _), .subagent(let id, _, _, _),
            .marker(let id, _), .note(let id, _, _):
            id
        case .prompt(let p, _): "o-\(p.id)"
        }
    }
}

/// Builds the chat from a session's state: REST history, then the live events grouped by run (each run after the
/// prompt that started it), then the prompts still waiting. `compact` (popover) shows tool and subagent rows inline;
/// otherwise (window) each run gets one marker.
public enum ChatTimeline {
    public static func items(_ s: SessionState, compact: Bool) -> [ChatItem] {
        var items = history(s.history, compact: compact)
        var runs: [String: [Event]] = [:]
        var order: [String] = []
        for e in s.events {
            if runs[e.runID] == nil { order.append(e.runID) }
            runs[e.runID, default: []].append(e)
        }
        var placed: Set<String> = []
        for runID in order {
            let events = runs[runID] ?? []
            if let p = s.outbox.first(where: { $0.status == .sent(runID: runID) }) {
                items.append(.prompt(p, time: date(ms: events.first?.ts)))
                placed.insert(p.id)
            }
            items += run(events, compact: compact)
        }
        items += s.outbox.filter { !placed.contains($0.id) }.map { .prompt($0, time: nil) }
        return items
    }

    /// Tool calls started so far in a run.
    public static func toolCount(_ s: SessionState, runID: String) -> Int {
        s.events.filter { $0.runID == runID && $0.kind == "tool.started" }.count
    }

    private static func history(_ messages: [HistoryMessage], compact: Bool) -> [ChatItem] {
        var results: [String: String] = [:]
        for m in messages where m.role == .tool {
            if let id = m.toolCallID { results[id] = m.content }
        }
        var items: [ChatItem] = []
        for m in messages {
            let time = m.timestamp.map { Date(timeIntervalSince1970: $0) }
            switch m.role {
            case .user:
                items.append(.user(id: "h-\(m.id)", text: m.content, time: time))
            case .assistant:
                if !m.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    items.append(.answer(id: "h-\(m.id)", text: m.content, time: time))
                }
                // shortcut: the window shows no marker for history turns, since the terminal pane is built from live
                // events only; add one if the pane ever reads the history.
                guard compact else { continue }
                for (i, call) in m.toolCalls.enumerated() {
                    items.append(.tool(id: "h-\(m.id)-\(i)", historyTool(call, result: call.id.flatMap { results[$0] })))
                }
            case .tool:
                break
            }
        }
        return items
    }

    private static func historyTool(_ call: HistoryMessage.ToolCall, result: String?) -> ToolRow {
        let args = call.arguments.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        var row = ToolRow(
            tool: call.name, summary: (args?["command"] as? String) ?? call.arguments ?? "", duration: "", output: result)
        if call.name == TerminalTranscript.terminalTool, let result,
            let r = try? JSONDecoder().decode(TerminalResult.self, from: Data(result.utf8))
        {
            row.output = r.output ?? r.error
            row.exitCode = r.exitCode
        }
        return row
    }

    private static func run(_ events: [Event], compact: Bool) -> [ChatItem] {
        let entries = TerminalTranscript.entries(from: events)
        let entryAt = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var subagentEnd: [String: (seq: Int, data: SubagentCompleted)] = [:]
        for e in events {
            if case .subagentCompleted(let c) = e.payload { subagentEnd[c.subagentID] = (e.seq, c) }
        }
        var items: [ChatItem] = []
        var markerPlaced = false
        for e in events {
            let id = "e-\(e.seq)"
            switch e.payload {
            case .toolStarted, .toolCompleted:
                // An entry's id is the seq of its first event; a completion of a call already shown has none.
                guard let entry = entryAt[e.seq] else { continue }
                if compact {
                    items.append(.tool(id: id, ToolRow(
                        tool: entry.tool, summary: entry.command.map(firstLine) ?? "",
                        duration: entry.isRunning ? "…" : entry.duration.map(seconds) ?? "",
                        output: entry.output ?? entry.errorText, exitCode: entry.exitCode)))
                } else if !markerPlaced {
                    markerPlaced = true
                    let summary = TerminalTranscript.summary(of: entries)
                    if summary.commandCount > 0 { items.append(.marker(id: "m-\(e.runID)", summary)) }
                }
            case .subagentStarted(let s) where compact:
                let end = subagentEnd[s.subagentID]
                // shortcut: the events don't say which tool calls belong to a subagent; this counts every call
                // started while it ran, which overcounts when subagents run in parallel.
                let tools = events.filter {
                    $0.kind == "tool.started" && $0.seq > e.seq && $0.seq < (end?.seq ?? .max)
                }.count
                let name = firstLine(s.goal ?? s.subagentID)
                items.append(.subagent(
                    id: id, name: name.count > 40 ? String(name.prefix(39)) + "…" : name, toolCount: tools,
                    duration: end.map { $0.data.duration.map(seconds) ?? "" } ?? "…"))
            case .answer(let a):
                items.append(.answer(id: id, text: a.text, time: date(ms: e.ts)))
                if a.truncated == true {
                    items.append(.note(id: id + "-cut", text: "The answer was cut; reopen the conversation for all of it.", isError: false))
                }
            case .runFailed(let error):
                items.append(.note(id: id, text: error.map { "Run failed: \($0)" } ?? "Run failed", isError: true))
            case .runCancelled:
                items.append(.note(id: id, text: "Run stopped", isError: false))
            case .steerQueued:
                items.append(.note(id: id, text: "Steer queued", isError: false))
            case .reconnected:
                items.append(.note(id: id, text: "Hermes' stream was interrupted; some steps may be missing.", isError: false))
            default:
                break
            }
        }
        return items
    }

    private static func date(ms: Int?) -> Date? {
        ms.map { Date(timeIntervalSince1970: Double($0) / 1000) }
    }

    private static func seconds(_ s: Double) -> String { String(format: "%.1fs", s) }

    private static func firstLine(_ s: String) -> String {
        String(s.split(whereSeparator: \.isNewline).first ?? "")
    }
}
