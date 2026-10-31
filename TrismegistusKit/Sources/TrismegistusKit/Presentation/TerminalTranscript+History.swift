import Foundation

/// The terminal transcript from the Hermes history: every tool call with its full result, including the runs the
/// relay never streamed to the app (Telegram, cron, the CLI, before the app opened).
extension TerminalTranscript {
    public static let codeTool = "execute_code"
    /// Results of tools other than terminal and execute_code are cut here, like the live previews (web results run to
    /// hundreds of KB a run).
    static let toolOutputLimit = 4000

    /// `earlier` plus one entry per assistant tool call in `messages`, completed by the `tool` message naming its id
    /// (which may come in a later page: calls still waiting in `earlier` are completed too). The ids are negative,
    /// Hermes' message id × 100 + the call's index, so they never meet a live seq; Hermes' ids are unique across sessions.
    public static func entries(
        fromHistory messages: [HistoryMessage], sessionID: String, after earlier: [TerminalEntry] = []
    ) -> [TerminalEntry] {
        var entries = earlier
        var waiting: [String: Int] = [:] // call id → index
        for (i, e) in entries.enumerated() where e.awaitsResult { if let c = e.callID { waiting[c] = i } }
        for m in messages {
            switch m.role {
            case .assistant:
                for (k, call) in m.toolCalls.enumerated() {
                    if let c = call.id { waiting[c] = entries.count }
                    entries.append(entry(call, index: k, of: m, sessionID: sessionID))
                }
            case .tool:
                guard let c = m.toolCallID, let i = waiting.removeValue(forKey: c) else { continue }
                complete(&entries[i], with: m)
            case .user:
                break
            }
        }
        return entries
    }

    /// History entries plus the live ones the history doesn't have yet, oldest first. A live entry is the same call as
    /// an unclaimed history entry of the same tool that started within a minute of it (for commands, also with the
    /// command the live preview starts, cut with "..."). The history one is kept, full output and all, unless it is
    /// still waiting for its result.
    public static func merged(history: [TerminalEntry], live: [TerminalEntry]) -> [TerminalEntry] {
        var out = history
        var claimed = Set<Int>()
        for l in live {
            guard let i = out.indices.first(where: { !claimed.contains($0) && isSameCall(out[$0], l) }) else {
                out.append(l)
                continue
            }
            claimed.insert(i)
            if out[i].awaitsResult { out[i] = l }
        }
        return out.enumerated().sorted { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }.map(\.element)
    }

    private static func isSameCall(_ h: TerminalEntry, _ l: TerminalEntry) -> Bool {
        guard h.tool == l.tool, abs(h.time - l.time) < 60_000 else { return false }
        guard l.isCommand, let preview = l.command else { return true }
        let prefix = preview.hasSuffix("...") ? String(preview.dropLast(3)) : preview
        return (h.command ?? "").hasPrefix(prefix)
    }

    private static func entry(_ call: HistoryMessage.ToolCall, index: Int, of m: HistoryMessage, sessionID: String) -> TerminalEntry {
        struct Arguments: Decodable { var command: String?; var workdir: String?; var code: String? }
        let args = call.arguments.flatMap { try? JSONDecoder().decode(Arguments.self, from: Data($0.utf8)) }
        return TerminalEntry(
            id: -((Int(m.id) ?? 0) * 100 + index), runID: "", tool: call.name, time: Int(((m.timestamp ?? 0) * 1000).rounded()),
            command: args?.command ?? args?.code ?? call.arguments, isError: false, isTruncated: false, isRunning: false,
            callID: call.id, cwd: args?.workdir, sessionID: sessionID, awaitsResult: true)
    }

    private static func complete(_ entry: inout TerminalEntry, with result: HistoryMessage) {
        entry.awaitsResult = false
        if let t = result.timestamp { entry.duration = max(0, t - Double(entry.time) / 1000) }
        let text = result.content
        let parsed = try? JSONDecoder().decode(TerminalResult.self, from: Data(text.utf8))
        if entry.isCommand || entry.tool == codeTool, let r = parsed, r.output != nil || r.exitCode != nil || r.error != nil {
            entry.output = r.output
            entry.exitCode = r.exitCode
            entry.errorText = r.error
            entry.isError = r.error?.isEmpty == false || r.status == "error"
        } else {
            entry.output = String(text.prefix(toolOutputLimit))
            entry.isTruncated = text.count > toolOutputLimit
            entry.isError = parsed?.error?.isEmpty == false
        }
    }
}
