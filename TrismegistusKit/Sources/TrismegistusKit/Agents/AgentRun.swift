import Foundation

/// A line of a run's steps: a tool call with its result, or the delegate's narration between them.
public struct AgentRow: Sendable, Equatable, Identifiable {
    /// `line.n`: one stream line can carry several steps.
    public let id: String
    /// Nil for a narration line.
    public var tool: String? = nil
    /// The narration, or the call's summary with paths relative to the run's worktree.
    public var text: String
    /// Nil until the tool's result arrives.
    public var failed: Bool? = nil
    /// What folds under the row: the summary with its full paths when `text` shortened them, then the result.
    public var output: String? = nil
}

/// The final report: its first line, then the rest.
public struct AgentReport: Sendable, Equatable {
    public var title: String
    public var body: String
}

/// How a run's steps read.
public enum AgentRun {
    /// The row name of a `tool_result` with no call before it (the call fell off the front of the kept steps).
    public static let orphanResult = "Result"
    /// Characters of a tool name that fit the row's narrow name column.
    public static let shortName = 6

    /// The last `result` step with text, its leading heading marks dropped from the title.
    public static func report(of steps: [AgentStep]) -> AgentReport? {
        guard let text = finalText(of: steps) else { return nil }
        let lines = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return AgentReport(
            title: String(lines[0].drop { $0 == "#" || $0 == " " }).trimmingCharacters(in: .whitespaces),
            body: lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : "")
    }

    /// One row per `tool` step, its `tool_result` folded in, narration in between. The `result` step is the report, and
    /// so is the narration that repeats it (a run's last message is both).
    public static func rows(of steps: [AgentStep], cwd: String?) -> [AgentRow] {
        let report = finalText(of: steps)
        var rows: [AgentRow] = []
        // shortcut: results pair with the oldest open call, because steps carry no tool ids; parallel calls answered out
        // of order swap outputs. Upgrade if the helper ever sends the id.
        var waiting: [Int] = []
        var line = (number: -1, count: 0)
        for step in steps {
            line = step.line == line.number ? (step.line, line.count + 1) : (step.line, 0)
            let id = "\(step.line).\(line.count)"
            switch step.kind {
            case .tool:
                waiting.append(rows.count)
                rows.append(toolRow(id: id, step.text, cwd: cwd))
            case .toolResult:
                if waiting.isEmpty {
                    rows.append(
                        AgentRow(id: id, tool: orphanResult, text: step.text, failed: step.error, output: step.text.isEmpty ? nil : step.text))
                } else {
                    let i = waiting.removeFirst()
                    rows[i].failed = step.error
                    rows[i].output = [rows[i].output, step.text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n").nonEmpty
                }
            case .result:
                break
            case .text, .unknown:
                let text = step.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty, text != report { rows.append(AgentRow(id: id, text: text)) }
            }
        }
        return rows
    }

    /// `10 steps · 3 failed`: the card's header counts tool calls, not narration.
    public static func stepsLine(_ rows: [AgentRow]) -> String {
        let tools = rows.filter { $0.tool != nil }
        return "\(tools.count) \(tools.count == 1 ? "step" : "steps") · \(tools.filter { $0.failed == true }.count) failed"
    }

    /// `text` with `cwd/` taken off every path that starts with it. A path elsewhere stays, even with `cwd` inside it.
    public static func relative(_ text: String, to cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty else { return text }
        let prefix = cwd.hasSuffix("/") ? cwd : cwd + "/"
        var out = ""
        var rest = Substring(text)
        while let hit = rest.range(of: prefix) {
            out += rest[..<hit.lowerBound]
            if let before = out.last, before.isLetter || before.isNumber || "/._-~".contains(before) { out += rest[hit] }
            rest = rest[hit.upperBound...]
        }
        return out + rest
    }

    private static func finalText(of steps: [AgentStep]) -> String? {
        steps.last { $0.kind == .result }?.text.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }

    /// `<ToolName>: <summary>`.
    private static func toolRow(id: String, _ text: String, cwd: String?) -> AgentRow {
        guard let colon = text.range(of: ": ") else { return AgentRow(id: id, tool: text, text: "") }
        let summary = String(text[colon.upperBound...])
        let short = relative(summary, to: cwd)
        return AgentRow(id: id, tool: String(text[..<colon.lowerBound]), text: short, output: short == summary ? nil : summary)
    }
}

extension Agent {
    /// The outcome chip's kind.
    public enum Tone: Sendable { case ok, warn, err, neutral }

    /// Running warns, a failure is an error, a `success` is ok; a run stopped without a result line says nothing.
    public var tone: Tone {
        if alive { return .warn }
        if failed { return .err }
        return outcome == nil ? .neutral : .ok
    }
}

extension String {
    fileprivate var nonEmpty: String? { isEmpty ? nil : self }
}
