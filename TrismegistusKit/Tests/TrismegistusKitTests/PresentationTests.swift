import Foundation
import Testing
@testable import TrismegistusKit

/// Hermes SSE data frames recorded in probe/ (Resources/probe/*.jsonl) as the app-side events the relay would send.
/// Only the tool kinds are mapped; the rest are dropped. seq counts from 1.
func probeEvents(_ name: String) throws -> [Event] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/probe/\(name).jsonl")
    var out: [Event] = []
    for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
        let f = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let tool = f["tool"] as? String ?? ""
        let payload: EventPayload
        switch f["event"] as? String {
        case "tool.started": payload = .toolStarted(.init(tool: tool, preview: f["preview"] as? String))
        case "tool.completed":
            payload = .toolCompleted(.init(
                tool: tool, duration: f["duration"] as? Double, error: f["error"] as? Bool ?? false, preview: f["preview"] as? String))
        default: continue
        }
        let ts = Int(((f["timestamp"] as? Double) ?? 0) * 1000)
        out.append(Event(sessionID: "s1", runID: f["run_id"] as? String ?? "", seq: out.count + 1, ts: ts, payload: payload))
    }
    return out
}

private func started(_ seq: Int, _ tool: String = "terminal", _ preview: String? = nil, run: String = "r1") -> Event {
    Event(sessionID: "s1", runID: run, seq: seq, ts: seq * 1000, payload: .toolStarted(.init(tool: tool, preview: preview)))
}

private func completed(
    _ seq: Int, _ preview: String? = nil, tool: String = "terminal", duration: Double? = 1, error: Bool = false, run: String = "r1"
) -> Event {
    Event(sessionID: "s1", runID: run, seq: seq, ts: seq * 1000,
          payload: .toolCompleted(.init(tool: tool, duration: duration, error: error, preview: preview)))
}

@Suite struct TerminalTranscriptTests {
    @Test func recordedTerminalCall() throws {
        let entries = TerminalTranscript.entries(from: try probeEvents("tool"))
        let e = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(e.command == "date +%Y")
        #expect(e.output == "2026")
        #expect(e.exitCode == 0)
        #expect(e.errorText == nil)
        #expect(e.duration == 0.15)
        #expect(!e.isRunning && !e.isTruncated && !e.failed)
        #expect(e.time == 1792801004583)
    }

    @Test func blockedCommandIsAFailureWithItsReason() throws {
        let e = try #require(TerminalTranscript.entries(from: try probeEvents("approval")).first)
        #expect(e.command?.hasPrefix("rm -rf") == true)
        #expect(e.isError && e.failed)
        #expect(e.exitCode == -1)
        #expect(e.output == "")
        #expect(e.errorText?.hasPrefix("BLOCKED: Command denied by user.") == true)
    }

    @Test func subagentDelegationIsAToolRowNotACommand() throws {
        let events = try probeEvents("subagent")
        let all = TerminalTranscript.entries(from: events, filter: .all)
        #expect(all.map(\.tool) == ["delegate_task"])
        #expect(all[0].output?.contains("dispatched") == true)
        #expect(all[0].exitCode == nil && !all[0].isTruncated)
        #expect(TerminalTranscript.entries(from: events, filter: .commands).isEmpty)
    }

    @Test func cutPreviewIsKeptRawAndMarkedTruncated() {
        let cut = #"{"output": "line 1\nline 2\nlin"#
        let e = TerminalTranscript.entries(from: [started(1, "terminal", "cat big"), completed(2, cut)])[0]
        #expect(e.output == cut)
        #expect(e.isTruncated)
        #expect(e.exitCode == nil)
        #expect(!e.isRunning)
    }

    @Test func startedWithoutCompletedIsRunning() {
        let e = TerminalTranscript.entries(from: [started(1, "terminal", "sleep 9")])[0]
        #expect(e.isRunning)
        #expect(e.duration == nil && e.output == nil)
    }

    @Test func completionsPairWithTheOldestOpenCallOfTheSameToolAndRun() {
        let events = [
            started(1, "terminal", "a"), started(2, "terminal", "b"), started(3, "web_search", "q"),
            completed(4, #"{"output":"A","exit_code":0,"error":null}"#, duration: 1),
            completed(5, #"{"output":"B","exit_code":2,"error":null}"#, duration: 2, error: true),
        ]
        let e = TerminalTranscript.entries(from: events)
        #expect(e.map(\.command) == ["a", "b", "q"])
        #expect(e.map(\.output) == ["A", "B", nil])
        #expect(e.map(\.isRunning) == [false, false, true])
        #expect(e.map(\.id) == [1, 2, 3])
    }

    @Test func completionWithoutStartKeepsItsOutput() {
        let e = TerminalTranscript.entries(from: [completed(7, #"{"output":"x","exit_code":0,"error":null}"#)])
        #expect(e.count == 1 && e[0].command == nil && e[0].output == "x" && !e[0].isRunning)
    }

    @Test func commandsFilterKeepsOnlyTheTerminalTool() {
        let events = [started(1, "terminal", "ls"), completed(2, #"{"output":"","exit_code":0,"error":null}"#),
                      started(3, "read_file", "a.txt"), completed(4, "text", tool: "read_file")]
        #expect(TerminalTranscript.entries(from: events, filter: .commands).map(\.tool) == ["terminal"])
        #expect(TerminalTranscript.entries(from: events, filter: .all).map(\.tool) == ["terminal", "read_file"])
    }

    @Test func summaryCountsCommandsDurationAndFailures() {
        let ok = #"{"output":"","exit_code":0,"error":null}"#
        let events = [
            started(1, "terminal", "a"), completed(2, ok, duration: 1.5),
            started(3, "terminal", "b"), completed(4, #"{"output":"","exit_code":1,"error":null}"#, duration: 2.0),
            started(5, "terminal", "c"), completed(6, ok, duration: 2.6, error: true),
            started(7, "terminal", "d"), // still running: counted, no duration
            started(8, "read_file", "f"), completed(9, "x", tool: "read_file", duration: 50),
            started(10, "terminal", "other run", run: "r2"), completed(11, ok, duration: 9, run: "r2"),
        ]
        let entries = TerminalTranscript.entries(from: events)
        let s = TerminalTranscript.summary(of: entries, runID: "r1")
        #expect(s == RunSummary(commandCount: 4, totalDuration: 6.1, failedCount: 2))
        #expect(s.label == "4 COMMANDS · 6.1 s · 2 failed")
        #expect(TerminalTranscript.summary(of: entries).commandCount == 5)
        #expect(RunSummary(commandCount: 1, totalDuration: 0.15, failedCount: 0).label == "1 COMMAND · 0.1 s")
    }
}

@Suite struct MarkdownBlocksTests {
    @Test func plainProseIsOneBlock() {
        #expect(MarkdownBlocks.parse("Hello **world**\n\nsecond paragraph") == [.prose("Hello **world**\n\nsecond paragraph")])
        #expect(MarkdownBlocks.parse("").isEmpty)
    }

    @Test func pipeTableWithAlignments() {
        let md = "| Name | Qty | Note |\n|:--|--:|:-:|\n| a \\| b | 2 | ok |\n| c | 3 |"
        #expect(MarkdownBlocks.parse(md) == [.table(
            header: ["Name", "Qty", "Note"], rows: [["a | b", "2", "ok"], ["c", "3", ""]], alignments: [.leading, .trailing, .center])])
    }

    @Test func tableBetweenParagraphsAndCode() {
        let md = "Before:\na | b\n--- | ---\n1 | 2\n\nAfter\n```\n| x |\n|---|\n```"
        #expect(MarkdownBlocks.parse(md) == [
            .prose("Before:"), .table(header: ["a", "b"], rows: [["1", "2"]], alignments: [.leading, .leading]),
            .prose("After"), .code(language: nil, text: "| x |\n|---|"),
        ])
    }

    @Test func aPipeLineIsNotATableWithoutAMatchingDelimiterRow() {
        for md in ["a | b\nplain text", "a | b | c\n--- | ---", "just | one line", "a | b\n--- | ---- x", "a | b\n"] {
            #expect(MarkdownBlocks.parse(md) == [.prose(md.trimmingCharacters(in: .newlines))])
        }
    }

    @Test func stripHTMLKeepsTextAndDropsComments() {
        let md = "Hi<!-- hidden\nnote --> there\n\n<sub>Migrated from Hermes kanban card <b>t_1</b></sub>\na<br/>b see <https://x.test> and 1 < 2"
        #expect(MarkdownBlocks.stripHTML(md) == "Hi there\n\nMigrated from Hermes kanban card t_1\na\nb see <https://x.test> and 1 < 2")
    }

    @Test func fenceWithInfoString() {
        let md = "Run it:\n\n```swift title=\"a.swift\"\nlet x = 1\nprint(x)\n```\n\nDone."
        #expect(MarkdownBlocks.parse(md) == [
            .prose("Run it:"), .code(language: "swift", text: "let x = 1\nprint(x)"), .prose("Done."),
        ])
    }

    @Test func tildeFenceAndNoLanguage() {
        #expect(MarkdownBlocks.parse("~~~\nplain\n~~~") == [.code(language: nil, text: "plain")])
        #expect(MarkdownBlocks.parse("~~~sh\nls\n~~~\n```py\nx\n```") == [
            .code(language: "sh", text: "ls"), .code(language: "py", text: "x"),
        ])
    }

    @Test func backticksInsideCodeDoNotCloseIt() {
        let md = "````md\n```swift\nlet x = 1\n```\n````\nafter `inline` code"
        #expect(MarkdownBlocks.parse(md) == [
            .code(language: "md", text: "```swift\nlet x = 1\n```"), .prose("after `inline` code"),
        ])
        // A different fence character, or a shorter run, is content too.
        #expect(MarkdownBlocks.parse("```\n~~~\n``\n```") == [.code(language: nil, text: "~~~\n``")])
    }

    @Test func inlineTripleBackticksAreNotAFence() {
        #expect(MarkdownBlocks.parse("use ```x``` inline\n``` not `a fence") == [.prose("use ```x``` inline\n``` not `a fence")])
    }

    @Test func unterminatedFenceRunsToTheEnd() {
        #expect(MarkdownBlocks.parse("Look:\n```sh\nls -la\ncd /") == [.prose("Look:"), .code(language: "sh", text: "ls -la\ncd /")])
        #expect(MarkdownBlocks.parse("```") == [.code(language: nil, text: "")])
    }

    @Test func indentedFenceLosesItsIndentFromTheContent() {
        let md = "1. step\n\n   ```sh\n   ls\n     indented\n   ```\n2. next"
        #expect(MarkdownBlocks.parse(md) == [
            .prose("1. step"), .code(language: "sh", text: "ls\n  indented"), .prose("2. next"),
        ])
        // Four spaces is an indented code block in Markdown, not a fence.
        #expect(MarkdownBlocks.parse("    ```\n    x") == [.prose("    ```\n    x")])
    }

    @Test func crlfLineEndings() {
        #expect(MarkdownBlocks.parse("a\r\n\r\n```go\r\nfmt.Println()\r\n```\r\nb\r\n") == [
            .prose("a"), .code(language: "go", text: "fmt.Println()"), .prose("b"),
        ])
    }
}

@Suite struct MarkdownDocumentTests {
    @Test func aBlankLineSeparatesParagraphs() {
        #expect(MarkdownBlocks.document("Hello **world**\nsame one\n\n \nsecond paragraph") == [.block(.prose("Hello **world**\nsame one")), .block(.prose("second paragraph"))])
        #expect(MarkdownBlocks.document("").isEmpty)
    }

    @Test func bulletedList() {
        #expect(MarkdownBlocks.document("- one\n* **two**\n+ `three`") == [.list([
            MarkdownListItem(.bullet, "one"), MarkdownListItem(.bullet, "**two**"), MarkdownListItem(.bullet, "`three`"),
        ])])
    }

    @Test func numberedListCountsUpFromTheFirst() {
        #expect(MarkdownBlocks.document("1. a\n1. b\n1) c") == [.list([
            MarkdownListItem(.number(1), "a"), MarkdownListItem(.number(2), "b"), MarkdownListItem(.number(3), "c"),
        ])])
        #expect(MarkdownBlocks.document("3. a\n4. b") == [.list([MarkdownListItem(.number(3), "a"), MarkdownListItem(.number(4), "b")])])
    }

    @Test func taskList() {
        let blocks = MarkdownBlocks.document("- [ ] open\n- [x] done\n- [X] also\n* plain\n- [ ]\n- [y] no")
        #expect(blocks == [.list([
            MarkdownListItem(.task(done: false), "open"), MarkdownListItem(.task(done: true), "done"), MarkdownListItem(.task(done: true), "also"),
            MarkdownListItem(.bullet, "plain"), MarkdownListItem(.bullet, "[ ]"), MarkdownListItem(.bullet, "[y] no"),
        ])])
        #expect(MarkdownBlocks.taskProgress(blocks) == (2, 3))
    }

    @Test func taskProgressCountsNestedItemsAndEveryList() {
        let md = "- [x] a\n  - [ ] b\n  - [x] c\n\nText\n\n- [ ] d"
        #expect(MarkdownBlocks.taskProgress(MarkdownBlocks.document(md)) == (2, 4))
        #expect(MarkdownBlocks.taskProgress(MarkdownBlocks.document("no tasks\n- here")) == (0, 0))
    }

    @Test func nestedItemsOneLevel() {
        #expect(MarkdownBlocks.document("- a\n  - b\n    - deep\n  1. c\n- d") == [.list([
            MarkdownListItem(.bullet, "a", children: [
                MarkdownListItem(.bullet, "b"), MarkdownListItem(.bullet, "deep"), MarkdownListItem(.number(1), "c"),
            ]),
            MarkdownListItem(.bullet, "d"),
        ])])
        #expect(MarkdownBlocks.document("1. a\n   - b\n2. c") == [.list([
            MarkdownListItem(.number(1), "a", children: [MarkdownListItem(.bullet, "b")]), MarkdownListItem(.number(2), "c"),
        ])])
    }

    @Test func listAfterAParagraphAndHeading() {
        #expect(MarkdownBlocks.document("Checked:\n- a\n- b\n\nNot yet:\n1. c") == [
            .block(.prose("Checked:")), .list([MarkdownListItem(.bullet, "a"), MarkdownListItem(.bullet, "b")]),
            .block(.prose("Not yet:")), .list([MarkdownListItem(.number(1), "c")]),
        ])
        #expect(MarkdownBlocks.document("## How\n- a\n### Then\nb") == [
            .heading(level: 2, text: "How"), .list([MarkdownListItem(.bullet, "a")]), .heading(level: 3, text: "Then"), .block(.prose("b")),
        ])
    }

    @Test func aLooseListStaysOneList() {
        #expect(MarkdownBlocks.document("1. a\n\n2. b\n\n\n3. c\n\nafter") == [
            .list([MarkdownListItem(.number(1), "a"), MarkdownListItem(.number(2), "b"), MarkdownListItem(.number(3), "c")]),
            .block(.prose("after")),
        ])
    }

    @Test func continuationLinesJoinTheItem() {
        #expect(MarkdownBlocks.document("- a\n  more\nlazy\n\n  second paragraph\n- b\n  - c\n    of c") == [.list([
            MarkdownListItem(.bullet, "a\nmore\nlazy\n\nsecond paragraph"),
            MarkdownListItem(.bullet, "b", children: [MarkdownListItem(.bullet, "c\nof c")]),
        ])])
    }

    @Test func aChangeOfMarkerKindStartsANewList() {
        #expect(MarkdownBlocks.document("- a\n1. b\n- c") == [
            .list([MarkdownListItem(.bullet, "a")]), .list([MarkdownListItem(.number(1), "b")]), .list([MarkdownListItem(.bullet, "c")]),
        ])
        #expect(MarkdownBlocks.document("- a\n\n1. b") == [.list([MarkdownListItem(.bullet, "a")]), .list([MarkdownListItem(.number(1), "b")])])
    }

    @Test func textThatOnlyLooksLikeAList() {
        for md in ["-1 degrees outside", "--flag turns it on", "use -v or\n--verbose here", "-", "- ", "*bold* word", "**bold** word", "1.5 is a version", "12 monkeys", "---", "- - -", "* * *", "    - indented code"] {
            #expect(MarkdownBlocks.document(md) == [.block(.prose(md))])
        }
        #expect(MarkdownBlocks.document("It was\n1986. A good year.") == [.block(.prose("It was\n1986. A good year."))])
        #expect(MarkdownBlocks.document("- a\n---\nb") == [.list([MarkdownListItem(.bullet, "a")]), .block(.prose("---\nb"))])
    }

    @Test func headings() {
        #expect(MarkdownBlocks.document("# One\n## Two ##\n   ### Three **b**\ntext") == [
            .heading(level: 1, text: "One"), .heading(level: 2, text: "Two"), .heading(level: 3, text: "Three **b**"), .block(.prose("text")),
        ])
    }

    @Test func textThatOnlyLooksLikeAHeading() {
        for md in ["#49 is the inbox", "#", "# ", "#### four", "    # indented"] {
            #expect(MarkdownBlocks.document(md) == [.block(.prose(md))])
        }
        #expect(MarkdownBlocks.document("# C#") == [.heading(level: 1, text: "C#")])
    }

    @Test func aFenceBetweenItemsSplitsTheList() {
        #expect(MarkdownBlocks.document("1. step\n\n   ```sh\n   ls\n   ```\n2. next") == [
            .list([MarkdownListItem(.number(1), "step")]), .block(.code(language: "sh", text: "ls")), .list([MarkdownListItem(.number(2), "next")]),
        ])
    }

    @Test func aTableAfterAListEndsIt() {
        #expect(MarkdownBlocks.document("- a\nx | y\n--- | ---\n1 | 2") == [
            .list([MarkdownListItem(.bullet, "a")]), .block(.table(header: ["x", "y"], rows: [["1", "2"]], alignments: [.leading, .leading])),
        ])
    }
}

@Suite struct PairingPayloadTests {
    @Test func canonicalCode() throws {
        let p = try PairingPayload.parse("ABCD-EFGH-JKMN")
        #expect(p == PairingPayload(code: "ABCD-EFGH-JKMN", relayURL: nil))
    }

    @Test func caseSpacesAndMissingDashesAreTolerated() throws {
        for input in ["abcd-efgh-jkmn", "abcd efgh jkmn", "ABCDEFGHJKMN", "  abcd-efgh jkmn\n", "ab cd-efgh-jk mn"] {
            #expect(try PairingPayload.parse(input).code == "ABCD-EFGH-JKMN", "\(input)")
        }
    }

    @Test func lookalikesReadAsCrockfordDigits() throws {
        #expect(try PairingPayload.parse("iIlL-oO12-0000").code == "1111-0012-0000")
    }

    @Test func malformedCodesAreRejected() {
        for input in ["ABCD-EFGH", "ABCD-EFGH-JKMN-PQRS", "ABCD-EFGH-JKMU", "ABCD-EFGH-JKM!", "ÄBCD-EFGH-JKMN"] {
            #expect(throws: PairingPayload.Failure.malformedCode, "\(input)") { try PairingPayload.parse(input) }
        }
        #expect(throws: PairingPayload.Failure.empty) { try PairingPayload.parse("  \n") }
    }

    @Test func qrPayloadGivesCodeAndURL() throws {
        let p = try PairingPayload.parse(#"{"v":1,"url":"https://relay.example.test","code":"abcd-efgh-jkmn"}"#)
        #expect(p.code == "ABCD-EFGH-JKMN")
        #expect(p.relayURL == URL(string: "https://relay.example.test"))
    }

    @Test func qrPayloadWithoutURLStillPairs() throws {
        #expect(try PairingPayload.parse(#"{"v":1,"code":"ABCDEFGHJKMN"}"#) == PairingPayload(code: "ABCD-EFGH-JKMN", relayURL: nil))
    }

    @Test func qrPayloadErrors() {
        func fails(_ json: String, _ f: PairingPayload.Failure) {
            #expect(throws: f, "\(json)") { try PairingPayload.parse(json) }
        }
        fails(#"{"v":1,"url":"http://relay.example.test","code":"ABCD-EFGH-JKMN"}"#, .insecureURL)
        fails(#"{"v":1,"url":"ws://relay.example.test","code":"ABCD-EFGH-JKMN"}"#, .insecureURL)
        fails(#"{"v":1,"url":"https://","code":"ABCD-EFGH-JKMN"}"#, .malformedURL)
        fails(#"{"v":1,"url":"relay.example.test","code":"ABCD-EFGH-JKMN"}"#, .malformedURL)
        fails(#"{"v":1,"url":"https://relay.example.test","code":"nope"}"#, .malformedCode)
        fails(#"{"v":2,"url":"https://relay.example.test","code":"ABCD-EFGH-JKMN"}"#, .malformedPayload)
        fails(#"{"url":"https://relay.example.test","code":"ABCD-EFGH-JKMN"}"#, .malformedPayload)
        fails(#"{"v":1,"url":"https://relay.example.test""#, .malformedPayload)
    }

    @Test func errorsHaveMessagesForTheSheet() {
        for f in [PairingPayload.Failure.empty, .malformedCode, .malformedPayload, .malformedURL, .insecureURL] {
            #expect(f.errorDescription?.isEmpty == false)
        }
    }
}
