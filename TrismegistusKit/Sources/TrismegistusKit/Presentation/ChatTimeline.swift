import Foundation

/// A tool call as a chat row shows it.
public struct ToolRow: Sendable, Equatable {
    public var tool: String
    public var summary: String
    public var duration: String
    public var output: String?
    public var exitCode: Int?
}

/// One step of an answer's thinking: an assistant message's `reasoning` and what the step led to.
public struct ThinkingStep: Sendable, Equatable {
    public var thought: String
    /// The step's tool names (`terminal`, `read_file, terminal`); nil when it led to the answer.
    public var tool: String?
    /// Its one call's arguments in short (`cua-driver inspect`), or `3 calls`; empty for none.
    public var detail: String

    public init(thought: String, tool: String? = nil, detail: String = "") {
        self.thought = thought
        self.tool = tool
        self.detail = detail
    }
}

/// An image in the chat.
public enum ChatImage: Sendable, Equatable, Hashable {
    /// Sent through the relay (`GET /api/attachments/{id}`).
    case attachment(AttachmentRef)
    /// A file of Hermes' that the session's messages name (`GET /api/sessions/{id}/media?path=`).
    case media(path: String)
}

/// One row of the chat.
public enum ChatItem: Sendable, Equatable, Identifiable {
    /// From the history; `text` may be empty when the message is only images. `steer`: sent into a running turn
    /// (Hermes' stored steer, without its wrapper).
    case user(id: String, text: String, time: Date?, images: [ChatImage] = [], steer: Bool = false)
    /// A prompt from the outbox: pending, sent (time of its run's first event) or failed; or a steer just sent.
    case prompt(OutgoingPrompt, time: Date?)
    case answer(id: String, text: String, time: Date?)
    case tool(id: String, ToolRow)
    case subagent(id: String, name: String, toolCount: Int, duration: String)
    /// The window's one marker per run; the terminal pane has the details.
    case marker(id: String, RunSummary)
    case note(id: String, text: String, isError: Bool)
    /// The window's chip of a finished turn's thinking, after its answer (#74): the steps in order.
    case thinking(id: String, [ThinkingStep])

    public var id: String {
        switch self {
        case .user(let id, _, _, _, _), .answer(let id, _, _), .tool(let id, _), .subagent(let id, _, _, _),
            .marker(let id, _), .note(let id, _, _), .thinking(let id, _):
            id
        case .prompt(let p, _): "o-\(p.id)"
        }
    }
}

/// Builds the chat from a session's state: REST history, then the live events grouped by run (each run after the
/// prompt that started it, its steers after the event they were sent after), then the prompts still waiting. `compact` (popover) shows tool and subagent rows inline;
/// otherwise (window) each run gets one marker.
public enum ChatTimeline {
    public static func items(_ s: SessionState, compact: Bool) -> [ChatItem] {
        var items = history(s.history, compact: compact, running: s.run != nil)
        var runs: [String: [Event]] = [:]
        var order: [String] = []
        for e in s.events {
            if runs[e.runID] == nil { order.append(e.runID) }
            runs[e.runID, default: []].append(e)
        }
        var placed: Set<String> = []
        for runID in order {
            let events = runs[runID] ?? []
            if let p = s.outbox.first(where: { !$0.isSteer && $0.status == .sent(runID: runID) }) {
                items.append(.prompt(p, time: date(ms: events.first?.ts)))
                placed.insert(p.id)
            }
            let steers = s.outbox.filter { $0.isSteer && $0.status == .sent(runID: runID) }
            placed.formUnion(steers.map(\.id))
            items += run(events, steers: steers, compact: compact, shows: { e, m in shows(s, e, m) })
        }
        items += s.outbox.filter { !placed.contains($0.id) }.map { .prompt($0, time: nil) }
        return items
    }

    /// Tool calls started so far in a run.
    public static func toolCount(_ s: SessionState, runID: String) -> Int {
        s.events.filter { $0.runID == runID && $0.kind == "tool.started" }.count
    }

    /// `running`: the last turn is still going; its thinking shows once it ends and the history reloads.
    private static func history(_ messages: [HistoryMessage], compact: Bool, running: Bool = false) -> [ChatItem] {
        var results: [String: String] = [:]
        for m in messages where m.role == .tool {
            if let id = m.toolCallID { results[id] = m.content }
        }
        var items: [ChatItem] = []
        // The window's thinking chip goes after each turn's last item (its answer); a steer stays in the turn.
        var steps: [ThinkingStep] = []
        var stepsID = ""
        func endTurn() {
            if !compact, !steps.isEmpty { items.append(.thinking(id: stepsID, steps)) }
            steps = []
        }
        for m in messages {
            let time = m.timestamp.map { Date(timeIntervalSince1970: $0) }
            if m.role == .assistant, let step = thinkingStep(m) {
                steps.append(step)
                stepsID = "k-\(m.id)"
            }
            switch m.role {
            case .user:
                if !m.isSteer { endTurn() }
                let (text, images) = userMessage(m.content, attachments: m.attachments)
                items.append(.user(id: "h-\(m.id)", text: text, time: time, images: images, steer: m.isSteer))
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
        if !running { endTurn() }
        return items
    }

    /// The message's thinking as a step, nil when it has none.
    static func thinkingStep(_ m: HistoryMessage) -> ThinkingStep? {
        guard let thought = m.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines), !thought.isEmpty else { return nil }
        guard let first = m.toolCalls.first else { return ThinkingStep(thought: thought) }
        var names: [String] = []
        for call in m.toolCalls where !names.contains(call.name) { names.append(call.name) }
        let detail = m.toolCalls.count == 1 ? argumentSummary(first.arguments) : "\(m.toolCalls.count) calls"
        return ThinkingStep(thought: thought, tool: names.joined(separator: ", "), detail: detail)
    }

    /// A call's arguments in at most 40 characters: its command, path, query or URL, else its first string argument by
    /// name; empty when it has none.
    static func argumentSummary(_ arguments: String?) -> String {
        guard let data = arguments?.data(using: .utf8),
            let args = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return "" }
        let named = ["command", "path", "file_path", "query", "url", "pattern"].lazy.compactMap { args[$0] as? String }.first
        let value = named ?? args.sorted { $0.key < $1.key }.lazy.compactMap { $0.value as? String }.first ?? ""
        let line = firstLine(value).trimmingCharacters(in: .whitespaces)
        return line.count > 40 ? String(line.prefix(39)) + "…" : line
    }

    /// The first line of the newest thought Hermes stored in the turn still going (the messages after its prompt): what the
    /// WORKING line shows during a run. Nil when none has one yet.
    public static func latestThought(_ messages: [HistoryMessage]) -> String? {
        let turn = messages.lastIndex { $0.role == .user && !$0.isSteer }.map { messages[($0 + 1)...] } ?? messages[...]
        return turn.reversed().lazy.compactMap { thinkingStep($0) }.first.map { firstLine($0.thought) }
    }

    /// A history user message as the chat shows it. Hermes keeps no images, only a `[screenshot]` line for each: with
    /// the relay's attachments the trailing `[screenshot]` lines go; Telegram's `[Image attached at: <path>]` lines
    /// become images, with the `[screenshot]` lines right after them. Other text stays as written.
    public static func userMessage(_ content: String, attachments: [AttachmentRef]) -> (text: String, images: [ChatImage]) {
        var kept: [Substring] = []
        var media: [ChatImage] = []
        var afterImage = false
        for line in content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("[Image attached at: "), t.hasSuffix("]") {
                let path = t.dropFirst(20).dropLast().trimmingCharacters(in: .whitespaces)
                if path.hasPrefix("/") {
                    media.append(.media(path: path))
                    afterImage = true
                    continue
                }
            }
            if afterImage, t == "[screenshot]" { continue }
            afterImage = false
            kept.append(line)
        }
        if !attachments.isEmpty {
            while let last = kept.last, ["[screenshot]", ""].contains(last.trimmingCharacters(in: .whitespaces)) { kept.removeLast() }
        }
        let images = attachments.map(ChatImage.attachment) + media
        guard !images.isEmpty else { return (content, []) }
        return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), images)
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

    /// How far before a `user.message` the history's copy of it may be stamped (same host clock; Hermes stores later).
    static let historySlack: TimeInterval = 10

    /// A relay's `user.message` (trismegistus#30) shows unless something else already does: this device's outbox (its
    /// prompt by client_msg_id, its steer by run and text) or the history, which has it once Hermes stored it (same
    /// text, or the same images for an image-only prompt, stamped at or after it).
    static func shows(_ s: SessionState, _ e: Event, _ m: UserMessage) -> Bool {
        if let id = m.clientMsgID, s.outbox.contains(where: { !$0.isSteer && $0.id == id }) { return false }
        if s.outbox.contains(where: { $0.isSteer && $0.text == m.text && $0.status == .sent(runID: e.runID) }) { return false }
        let text = bare(m.text)
        let images = (m.attachments ?? []).map(\.id)
        let at = Double(e.ts) / 1000 - historySlack
        return !s.history.contains { h in
            h.role == .user && bare(h.content) == text && (!text.isEmpty || h.attachments.map(\.id) == images)
                && (h.timestamp ?? 0) >= at
        }
    }

    /// Hermes keeps a `[screenshot]` line per image in the prompt it stores.
    private static func bare(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.trimmingCharacters(in: .whitespaces) != "[screenshot]" }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(
        _ events: [Event], steers: [OutgoingPrompt] = [], compact: Bool, shows: (Event, UserMessage) -> Bool = { _, _ in true }
    ) -> [ChatItem] {
        let entries = TerminalTranscript.entries(from: events)
        let entryAt = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var subagentEnd: [String: (seq: Int, data: SubagentCompleted)] = [:]
        for e in events {
            if case .subagentCompleted(let c) = e.payload { subagentEnd[c.subagentID] = (e.seq, c) }
        }
        var items: [ChatItem] = []
        var markerPlaced = false
        var waiting = steers[...]
        for e in events {
            while let p = waiting.first, p.afterSeq < e.seq {
                items.append(.prompt(p, time: nil))
                waiting = waiting.dropFirst()
            }
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
            case .userMessage(let m) where shows(e, m):
                items.append(.user(
                    id: id, text: m.text, time: date(ms: e.ts), images: (m.attachments ?? []).map { .attachment($0.ref) },
                    steer: m.kind == .steer))
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
        items += waiting.map { .prompt($0, time: nil) }
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
