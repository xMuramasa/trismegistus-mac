import Foundation

/// What a new conversation gets of the one it continues: the user's messages, the assistant's prose and one line per
/// tool call (never tool output), under a header, cut to fit the relay's prompt limit. Then `prompt(digest:)` wraps it.
public enum HandoffDigest {
    /// Unicode scalars: the relay counts prompt text in runes and takes at most 32,768 (`protocol.MaxTextChars`); this
    /// leaves room for the fixed text of the prompt.
    public static let limit = 30_000
    /// One message is cut here, so a pasted log can't take the whole digest.
    static let messageLimit = 4_000
    static let commandLimit = 200
    static let argumentLimit = 120

    /// The digest of `history`. `model` names the old conversation's model in the header.
    public static func make(
        history: [HistoryMessage], info: SessionInfo, model: String?, timeZone: TimeZone = .current, limit: Int = limit
    ) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = timeZone
        format.dateFormat = "yyyy-MM-dd HH:mm"
        let started = info.startedAt ?? history.first?.timestamp

        var header = "# Earlier conversation\n"
        header += "Title: \(info.title ?? "untitled")\n"
        header += "Id: \(info.id)\n"
        if let started { header += "Started: \(format.string(from: Date(timeIntervalSince1970: started)))\n" }
        if let model { header += "Model: \(model)\n" }
        header += "Messages: \(info.messageCount ?? history.count)\n"

        // One block per user message and per assistant message (prose, then its tool lines).
        var entries = TerminalTranscript.entries(fromHistory: history, sessionID: info.id)[...]
        var blocks: [(text: String, isUser: Bool)] = []
        for m in history {
            let time = m.timestamp.map { " · " + format.string(from: Date(timeIntervalSince1970: $0)) } ?? ""
            switch m.role {
            case .user:
                blocks.append(("## User\(time)\n" + cut(m.content, messageLimit), true))
            case .assistant:
                let calls = entries.prefix(m.toolCalls.count)
                entries = entries.dropFirst(m.toolCalls.count)
                let prose = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !prose.isEmpty || !calls.isEmpty else { continue }
                var text = "## Assistant\(time)\n"
                if !prose.isEmpty { text += cut(prose, messageLimit) + "\n" }
                text += calls.map { "- " + toolLine($0) + "\n" }.joined()
                blocks.append((text.trimmingCharacters(in: .newlines), false))
            case .tool:
                continue
            }
        }

        func size(_ s: String) -> Int { s.unicodeScalars.count + 2 }
        let budget = limit - size(header) - 200 // the cut marker
        guard blocks.map({ size($0.text) }).reduce(0, +) > budget else {
            return ([header] + blocks.map(\.text)).joined(separator: "\n\n")
        }
        // Too long: the first user message, then as much of the end as fits.
        let first = blocks.firstIndex { $0.isUser } ?? 0
        var used = size(blocks[first].text)
        var start = blocks.count
        while start - 1 > first, used + size(blocks[start - 1].text) <= budget {
            start -= 1
            used += size(blocks[start].text)
        }
        let dropped = start - first - 1
        var parts = [header] + blocks[...first].map(\.text)
        if dropped > 0 {
            parts.append("[… \(dropped) earlier \(dropped == 1 ? "entry" : "entries") cut to fit; the full history stays in conversation \(info.id) …]")
        }
        return (parts + blocks[start...].map(\.text)).joined(separator: "\n\n")
    }

    /// The first message of the new conversation.
    public static func prompt(digest: String) -> String {
        """
        This conversation continues an earlier one that grew too large to go on. Below is a digest of it: the user's \
        messages, your replies, and one line per tool call (tool output left out).

        First reply with a short status of at most 10 lines: where it left off, what is done, what is next, and any \
        open questions. Only carry on with the work if the last user message asked for it and it isn't done yet; \
        otherwise wait for the user.

        Treat the digest as notes, not as the current state: re-read files and re-run commands instead of trusting \
        what it says they contained or printed.

        <digest>
        \(digest)
        </digest>
        """
    }

    /// One line for a tool call. Terminal: the command's first line and its exit code; file writes and patches: the
    /// path; others: the tool name and a short summary of its arguments.
    public static func toolLine(_ e: TerminalEntry) -> String {
        if e.isCommand {
            let result = e.exitCode.map { "exit \($0)" } ?? (e.errorText?.isEmpty == false ? "error" : e.awaitsResult ? "no result" : "done")
            return "$ " + firstLine(e.command ?? "", commandLimit) + " → " + result
        }
        let args = arguments(e.command)
        if ["write", "patch", "edit"].contains(where: e.tool.contains), let path = args["path"] ?? args["file_path"] {
            return "\(e.tool) \(path)"
        }
        if e.tool == TerminalTranscript.codeTool, let code = args["code"] ?? e.command {
            return "\(e.tool): " + firstLine(code, argumentLimit)
        }
        let preferred = ["query", "pattern", "path", "url", "name", "goal", "prompt"]
        let key = preferred.first { args[$0] != nil } ?? args.keys.sorted().first
        guard let key, let value = args[key] else { return e.tool }
        return "\(e.tool) \(key)=" + firstLine(value, argumentLimit)
    }

    /// Fragments of Hermes' messages when the provider stopped answering; they come as a failed run's error or as the
    /// last assistant message.
    public static let stallFragments = [
        "Provider has been unresponsive", "consecutive stale attempts",
        "Operation interrupted: waiting for model response",
        "Your request was not processed. Send it again if you still want me to carry it out",
    ]

    public static func isStall(_ text: String) -> Bool {
        stallFragments.contains { text.localizedCaseInsensitiveContains($0) }
    }

    /// String-valued arguments of a call (the history keeps them as a JSON string); the code of execute_code arrives
    /// already parsed as `command`, so plain text gives none.
    private static func arguments(_ json: String?) -> [String: String] {
        guard let json, let object = try? Wire.decode([String: JSONValue].self, from: Data(json.utf8)) else { return [:] }
        return object.compactMapValues { if case .string(let s) = $0 { s } else { nil } }
    }

    private static func firstLine(_ s: String, _ max: Int) -> String {
        let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let more = line.count < s.trimmingCharacters(in: .whitespacesAndNewlines).count
        return cut(line, max, marker: more ? " …" : "")
    }

    private static func cut(_ s: String, _ max: Int, marker: String = "") -> String {
        s.unicodeScalars.count <= max ? s + marker : String(String.UnicodeScalarView(s.unicodeScalars.prefix(max))) + " …"
    }
}
