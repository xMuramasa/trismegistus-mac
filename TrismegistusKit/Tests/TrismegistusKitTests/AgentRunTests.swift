import Foundation
import Testing
@testable import TrismegistusKit

/// A run's steps as rows, its report and its outcome chip (#60).
@Suite struct AgentRunTests {
    static let cwd = "/wt/issue-60"

    func tool(_ line: Int, _ text: String) -> AgentStep { AgentStep(line: line, kind: .tool, text: text) }
    func result(_ line: Int, _ text: String, error: Bool = false) -> AgentStep {
        AgentStep(line: line, kind: .toolResult, text: text, error: error)
    }
    func say(_ line: Int, _ text: String) -> AgentStep { AgentStep(line: line, kind: .text, text: text) }
    func rows(_ steps: [AgentStep]) -> [AgentRow] { AgentRun.rows(of: steps, cwd: Self.cwd) }

    // MARK: Rows

    @Test func aToolTakesItsResultAndNarrationStaysBetween() {
        let rows = rows([
            tool(1, "Grep: \"sync\" apps"), result(2, "12: sync"),
            say(3, "Now the build."),
            tool(4, "Bash: make"), result(5, "exit 1", error: true),
        ])
        #expect(rows == [
            AgentRow(id: "1.0", tool: "Grep", text: "\"sync\" apps", failed: false, output: "12: sync"),
            AgentRow(id: "3.0", text: "Now the build."),
            AgentRow(id: "4.0", tool: "Bash", text: "make", failed: true, output: "exit 1"),
        ])
        #expect(AgentRun.stepsLine(rows) == "2 steps · 1 failed")
    }

    @Test func aResultWithoutAToolIsItsOwnRow() {
        let first = rows([result(7, "late output", error: true), tool(8, "Bash: ls"), result(9, "a")])
        #expect(first.map(\.tool) == [AgentRun.orphanResult, "Bash"])
        #expect(first[0].failed == true && first[0].output == "late output")
        #expect(first[1].output == "a")
        // Results after the last call have no call left either.
        #expect(rows([tool(1, "Bash: ls"), result(2, "a"), result(3, "b")]).map(\.tool) == ["Bash", AgentRun.orphanResult])
    }

    @Test func aToolAtTheLiveEdgeHasNoStatusYet() {
        let rows = rows([tool(1, "Bash: sleep 30")])
        #expect(rows[0].failed == nil && rows[0].output == nil)
        #expect(AgentRun.stepsLine(rows) == "1 step · 0 failed")
    }

    @Test func parallelCallsTakeTheirResultsInOrder() {
        let rows = rows([tool(1, "Read: a"), tool(1, "Read: b"), say(2, "Reading both."), result(3, "A"), result(3, "B")])
        #expect(rows.map(\.id) == ["1.0", "1.1", "2.0"])
        #expect(rows[0].output == "A" && rows[1].output == "B")
    }

    @Test func anEmptyResultFoldsNothing() {
        let rows = rows([tool(1, "Bash: true"), result(2, "")])
        #expect(rows[0].failed == false && rows[0].output == nil)
    }

    @Test func theNameIsTheTextBeforeTheFirstColon() {
        let rows = rows([tool(1, "Bash: echo a: b"), tool(2, "NoSummary")])
        #expect(rows[0].tool == "Bash" && rows[0].text == "echo a: b")
        #expect(rows[1].tool == "NoSummary" && rows[1].text == "")
    }

    @Test func theReportIsNotARowNorIsTheNarrationThatRepeatsIt() {
        let rows = rows([
            say(1, "Starting."), say(2, "  \n"), say(3, "All done.\n\nDetails."),
            AgentStep(line: 4, kind: .result, text: "All done.\n\nDetails.\n"),
        ])
        #expect(rows.map(\.text) == ["Starting."])
    }

    @Test func unknownStepsReadAsNarration() {
        #expect(rows([AgentStep(line: 1, kind: .unknown, text: "new kind")]).map(\.text) == ["new kind"])
    }

    // MARK: Relative paths

    @Test func pathsAreRelativeToTheWorktree() {
        #expect(AgentRun.relative("/wt/issue-60/apps/a.swift", to: Self.cwd) == "apps/a.swift")
        #expect(AgentRun.relative("/wt/issue-60/apps/a.swift", to: Self.cwd + "/") == "apps/a.swift")
        #expect(AgentRun.relative("cat /wt/issue-60/a && cp \"/wt/issue-60/b\" c=/wt/issue-60/d", to: Self.cwd) == "cat a && cp \"b\" c=d")
    }

    @Test func pathsOutsideTheWorktreeStay() {
        #expect(AgentRun.relative("/wt/issue-601/a", to: Self.cwd) == "/wt/issue-601/a")
        #expect(AgentRun.relative("/backup/wt/issue-60/a", to: Self.cwd) == "/backup/wt/issue-60/a")
        #expect(AgentRun.relative("~/wt/issue-60/a", to: Self.cwd) == "~/wt/issue-60/a")
        #expect(AgentRun.relative("cd /wt/issue-60", to: Self.cwd) == "cd /wt/issue-60")
        #expect(AgentRun.relative("/wt/issue-60/a", to: nil) == "/wt/issue-60/a")
        #expect(AgentRun.relative("/wt/issue-60/a", to: "") == "/wt/issue-60/a")
    }

    @Test func theFullPathStaysInTheOutput() {
        let both = rows([tool(1, "Edit: /wt/issue-60/a.swift"), result(2, "1 replacement"), tool(3, "Edit: /tmp/b"), result(4, "ok")])
        #expect(both[0].text == "a.swift" && both[0].output == "/wt/issue-60/a.swift\n1 replacement")
        #expect(both[1].text == "/tmp/b" && both[1].output == "ok")
        // Still there before the result arrives.
        #expect(rows([tool(1, "Read: /wt/issue-60/a")])[0].output == "/wt/issue-60/a")
    }

    // MARK: Report

    @Test func theReportsFirstLineIsItsTitle() {
        func report(_ text: String) -> AgentReport? { AgentRun.report(of: [AgentStep(line: 1, kind: .result, text: text)]) }
        #expect(report("Build blocked\n\n- one\n- two\n") == AgentReport(title: "Build blocked", body: "- one\n- two"))
        #expect(report("## All **done**  \nrest") == AgentReport(title: "All **done**", body: "rest"))
        #expect(report("\n\nOne line\n") == AgentReport(title: "One line", body: ""))
        #expect(report(" \n") == nil)
    }

    @Test func theLastResultIsTheReport() {
        #expect(AgentRun.report(of: [say(1, "no result yet")]) == nil)
        let steps = [AgentStep(line: 1, kind: .result, text: "first"), AgentStep(line: 2, kind: .result, text: "second")]
        #expect(AgentRun.report(of: steps)?.title == "second")
    }

    // MARK: Outcome chip

    func agent(alive: Bool, outcome: String?) throws -> Agent {
        var json = #"{"id":"run_a","alive":\#(alive)"#
        if let outcome { json += #","outcome":"\#(outcome)""# }
        return try Wire.decode(Agent.self, from: Data((json + "}").utf8))
    }

    @Test func theOutcomeChip() throws {
        let cases: [(Bool, String?, Agent.Tone, String)] = [
            (true, nil, .warn, "running"),
            (false, "success", .ok, "done"),
            (false, "error_max_turns", .err, "out of turns"),
            (false, "error_during_execution", .err, "failed"),
            (false, "error_new_kind", .err, "error new kind"),
            (false, nil, .neutral, "ended"),
        ]
        for (alive, outcome, tone, words) in cases {
            let agent = try agent(alive: alive, outcome: outcome)
            #expect(agent.tone == tone && agent.statusWords == words)
        }
    }
}
