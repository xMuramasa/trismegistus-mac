import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// A real app conversation (Resources/history/app-session.json, trimmed): 23 messages, 9 tool calls (8 terminal, incl.
/// two parallel ones and an approval run; one patch refused by Hermes).
func appSession() throws -> [HistoryMessage] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/history/app-session.json")
    struct Page: Decodable { var data: [HistoryMessage] }
    return try Wire.decode(Page.self, from: Data(contentsOf: url)).data
}

private func decodeHistory(_ json: String) throws -> [HistoryMessage] { try Wire.decode([HistoryMessage].self, from: Data(json.utf8)) }

private func live(_ seq: Int, ms: Int, _ preview: String?, completed result: String? = nil, tool: String = "terminal") -> [Event] {
    var events = [Event(sessionID: "s1", runID: "r1", seq: seq, ts: ms, payload: .toolStarted(.init(tool: tool, preview: preview)))]
    if let result {
        events.append(Event(sessionID: "s1", runID: "r1", seq: seq + 1, ts: ms + 100,
                            payload: .toolCompleted(.init(tool: tool, duration: 0.1, error: false, preview: result))))
    }
    return events
}

@Suite struct CommandGroupTests {
    private func entry(_ session: String, id: Int, time: Int, exit: Int = 0) -> TerminalEntry {
        TerminalEntry(id: id, runID: "", tool: "terminal", time: time, exitCode: exit, isError: false, isTruncated: false,
                      isRunning: false, sessionID: session)
    }

    @Test func oneGroupPerConversationNewestFirst() {
        // Interleaved, newest first, as `CommandLog.all` gives them.
        let groups = TerminalTranscript.groups([
            entry("b", id: 1, time: 50), entry("a", id: 2, time: 40), entry("b", id: 3, time: 30, exit: 1),
            entry("a", id: 4, time: 20), entry("c", id: 5, time: 10, exit: 2), entry("b", id: 6, time: 5, exit: 127),
        ])
        #expect(groups.map(\.id) == ["b", "a", "c"])
        #expect(groups[0].entries.map(\.id) == [1, 3, 6] && groups[1].entries.map(\.id) == [2, 4])
        #expect(groups.map(\.failedCount) == [2, 0, 1])
    }

    @Test func noCallsNoGroups() { #expect(TerminalTranscript.groups([]).isEmpty) }

    @Test func oneLineIsOnUntilTurnedOff() { #expect(TerminalTranscript.oneLineByDefault) }
}

@Suite struct HistoryTranscriptTests {
    @Test func toolCallsWithTheirResults() throws {
        let e = TerminalTranscript.entries(fromHistory: try appSession(), sessionID: "s1")
        #expect(e.count == 9 && e.filter(\.isCommand).count == 8)
        #expect(e.allSatisfy { $0.sessionID == "s1" && !$0.awaitsResult && $0.id < 0 })
        let echo = e[0]
        #expect(echo.command == "echo hello world" && echo.output == "hello world" && echo.exitCode == 0 && !echo.failed)
        #expect(echo.id == -629_000 && echo.callID == "toolu_016fmKiqKtYah8BxmuhiJnT1")
        #expect(echo.time == 1_793_443_408_052)
        #expect(abs((echo.duration ?? 0) - 0.15) < 0.01)
        // The whole output, not a 4,000-character preview; smart approval's note doesn't make it an error.
        #expect(e[1].output?.hasPrefix("94:approvals:\n95-") == true && !e[1].isTruncated)
        #expect(e[5].command == "rm -rf ~/.hermes/cache/scratch/trismegistus-approval-test" && !e[5].failed)
    }

    @Test func otherToolsKeepTheirArgumentsAndErrors() throws {
        let patch = try #require(TerminalTranscript.entries(fromHistory: try appSession(), sessionID: "s1").first { $0.tool == "patch" })
        #expect(!patch.isCommand && patch.isError && patch.failed && patch.exitCode == nil)
        #expect(patch.command?.hasPrefix(#"{"path":"/home/muramasa/.hermes/config.yaml""#) == true)
        #expect(patch.output?.contains("Refusing to write to Hermes config file") == true)
    }

    @Test func parallelCallsAndResultsInALaterPage() throws {
        let all = try appSession()
        let cut = try #require(all.firstIndex { $0.id == "6343" })
        let first = TerminalTranscript.entries(fromHistory: Array(all[..<cut]), sessionID: "s1")
        #expect(first.suffix(2).map(\.awaitsResult) == [true, true])
        #expect(first.suffix(2).map(\.id) == [-634_200, -634_201])
        #expect(first.last?.output == nil && first.last?.failed == false)

        let rest = TerminalTranscript.entries(fromHistory: Array(all[cut...]), sessionID: "s1", after: first)
        #expect(rest == TerminalTranscript.entries(fromHistory: all, sessionID: "s1"))
        #expect(rest.suffix(2).map(\.awaitsResult) == [false, false])
        #expect(rest.last?.command == "mkdir -p ~/.hermes/cache/scratch/trismegistus-approval-test && rm -rf ~/.hermes/cache/scratch/trismegistus-approval-test")
        // Waited for the approval.
        #expect((rest.last?.duration ?? 0) > 13)
    }

    @Test func blockedCodeOrphanAndLongResults() throws {
        let big = String(repeating: "x", count: 5000)
        let messages = try decodeHistory(#"""
        [{"id": 1, "role": "assistant", "content": "", "timestamp": 100, "tool_calls": [
           {"id": "c1", "function": {"name": "terminal", "arguments": "{\"command\":\"rm -rf /tmp/x\",\"workdir\":\"/srv\"}"}},
           {"id": "c2", "function": {"name": "execute_code", "arguments": "{\"code\":\"print(1/0)\"}"}},
           {"id": "c3", "function": {"name": "web_search", "arguments": "{\"query\":\"q\"}"}},
           {"id": "c4", "function": {"name": "execute_code", "arguments": "{\"code\":\"print(2)\"}"}},
           {"id": "c5", "function": {"name": "terminal", "arguments": "not json"}}]},
         {"id": 2, "role": "tool", "tool_call_id": "c1", "timestamp": 101, "content": "{\"output\": \"\", \"exit_code\": -1, \"error\": \"BLOCKED: Command denied by user.\"}"},
         {"id": 3, "role": "tool", "tool_call_id": "c2", "timestamp": 102, "content": "{\"status\": \"error\", \"output\": \"ZeroDivisionError\", \"error\": \"\"}"},
         {"id": 4, "role": "tool", "tool_call_id": "c3", "timestamp": 103, "content": "\#(big)"},
         {"id": 5, "role": "tool", "tool_call_id": "c4", "timestamp": 104, "content": "plain text"},
         {"id": 6, "role": "tool", "tool_call_id": "nobody", "content": "orphan"},
         {"id": 7, "role": "tool", "tool_call_id": "c5", "timestamp": 105, "content": "{\"output\": \"ok\", \"exit_code\": 0, \"error\": null}"}]
        """#)
        let e = TerminalTranscript.entries(fromHistory: messages, sessionID: "s1")
        #expect(e.count == 5)
        #expect(e[0].cwd == "/srv" && e[0].exitCode == -1 && e[0].isError && e[0].errorText == "BLOCKED: Command denied by user.")
        #expect(e[1].command == "print(1/0)" && e[1].output == "ZeroDivisionError" && e[1].failed && !e[1].isCommand)
        #expect(e[2].output?.count == 4000 && e[2].isTruncated && !e[2].failed)
        #expect(e[3].output == "plain text" && !e[3].failed) // execute_code with a result that isn't JSON
        #expect(e[4].command == "not json" && e[4].output == "ok" && e[4].duration == 5)
    }

    @Test func mergeKeepsHistoryAndAddsWhatOnlyLiveHas() throws {
        let all = try appSession()
        let cut = try #require(all.firstIndex { $0.id == "6343" })
        let hist = TerminalTranscript.entries(fromHistory: Array(all[..<cut]), sessionID: "s1")
        let events =
            live(1, ms: 1_793_443_408_100, "echo hello world", completed: #"{"output":"hello world","exit_code":0,"error":null}"#)
            + live(3, ms: 1_793_443_480_400, "mkdir -p ~/.hermes/cache/scratch/trisme...", completed: #"{"output":"cut"#)
            + live(5, ms: 1_793_443_994_000, "hermes config get approvals.smart_policy", completed: #"{"output":"x","exit_code":0,"error":null}"#)
            + live(7, ms: 1_793_443_994_100, "mkdir -p ~/.hermes/cache/scratch/trisme...") // still waiting for approval
            + live(8, ms: 1_793_450_000_000, "git status") // a later run the history doesn't have yet
        let merged = TerminalTranscript.merged(history: hist, live: TerminalTranscript.entries(from: events))
        #expect(merged.count == hist.count + 1)
        // Finished calls come from the history (full output); where the history still waits for a result, the live one.
        #expect(merged.filter { $0.id > 0 }.map(\.command) == [
            "hermes config get approvals.smart_policy", "mkdir -p ~/.hermes/cache/scratch/trisme...", "git status",
        ])
        #expect(merged[merged.count - 2].isRunning && merged.last?.command == "git status")
        #expect(merged.first { $0.callID == "toolu_01Td1uuCUm2sjSJFg2DYzCDJ" }?.isTruncated == false)
        #expect(merged.map(\.time) == merged.map(\.time).sorted())
        // No history yet: the live entries as they are.
        #expect(TerminalTranscript.merged(history: [], live: TerminalTranscript.entries(from: events)).count == 5)
    }

    @Test func sameCommandTwiceIsTwoCalls() throws {
        let hist = TerminalTranscript.entries(fromHistory: try decodeHistory(#"""
        [{"id": 1, "role": "assistant", "timestamp": 100, "tool_calls": [{"id": "a", "function": {"name": "terminal", "arguments": "{\"command\":\"ls\"}"}}]},
         {"id": 2, "role": "tool", "tool_call_id": "a", "timestamp": 101, "content": "{\"output\": \"A\", \"exit_code\": 0}"}]
        """#), sessionID: "s1")
        let events = live(1, ms: 100_100, "ls", completed: #"{"output":"A","exit_code":0}"#)
            + live(3, ms: 110_000, "ls", completed: #"{"output":"B","exit_code":0}"#)
        let merged = TerminalTranscript.merged(history: hist, live: TerminalTranscript.entries(from: events))
        #expect(merged.map(\.output) == ["A", "B"] && merged.map(\.id) == [-100, 3])
    }
}

/// CommandLog against FakeHTTP serving the fixture by `offset` and `limit`; `available` is how many messages Hermes has.
@MainActor @Suite struct CommandLogTests {
    let available = Watched(20) // up to the parallel calls, without their results

    func makeLog(cacheURL: URL? = nil) throws -> (CommandLog, FakeHTTP) {
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Resources/history/app-session.json"))) as! [String: Any]
        let raw = try JSONSerialization.data(withJSONObject: data["data"]!)
        let available = available
        let http = FakeHTTP { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            func q(_ name: String) -> Int { Int(items.first { $0.name == name }?.value ?? "") ?? 0 }
            let all = (try! JSONSerialization.jsonObject(with: raw) as! [Any]).prefix(available.current)
            let page = all.dropFirst(q("offset")).prefix(q("limit"))
            let body = try! JSONSerialization.data(withJSONObject: ["object": "list", "data": Array(page)])
            return (200, String(decoding: body, as: UTF8.self))
        }
        let rest = RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http)
        return (CommandLog(rest: rest, cacheURL: cacheURL), http)
    }

    func queries(_ http: FakeHTTP, from: Int = 0) -> [String] {
        http.requests.current.dropFirst(from).map { "\($0.url!.pathComponents.dropLast().last!)?\($0.url!.query ?? "")" }
    }

    func list(_ count: Int, tools: Int = 9) -> [SessionInfo] {
        [SessionInfo(id: "api_1", source: "api_server", lastActive: 10, messageCount: count, toolCallCount: tools),
         SessionInfo(id: "tg_1", source: "telegram", lastActive: 20, messageCount: 4, toolCallCount: 0)]
    }

    @Test func fetchesOnlyNewMessages() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("commandlog-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = dir.appendingPathComponent("commands.json")
        let (log, http) = try makeLog(cacheURL: cache)

        await log.refresh(list(20))
        // Sessions without tool calls are skipped.
        #expect(queries(http) == ["api_1?limit=200&offset=0&order=oldest"])
        #expect(log.entries(of: "api_1").count == 9 && log.entries(of: "api_1").suffix(2).allSatisfy(\.awaitsResult))

        await log.refresh(list(20)) // nothing new
        #expect(http.requests.current.count == 1)

        available.mutate { $0 = 23 }
        await log.refresh(list(23))
        #expect(queries(http, from: 1) == ["api_1?limit=200&offset=20&order=oldest"])
        #expect(log.entries(of: "api_1") == TerminalTranscript.entries(fromHistory: try appSession(), sessionID: "api_1"))
        #expect(log.all.first?.callID == "toolu_01TCR4Q3Pwxh3c9TnnsCKHTK") // newest first

        // A new launch starts from the file.
        let (again, http2) = try makeLog(cacheURL: cache)
        #expect(again.entries(of: "api_1") == log.entries(of: "api_1"))
        await again.refresh(list(23))
        #expect(http2.requests.current.isEmpty)

        // The pane asks whatever the list says, from the cached count.
        await again.sync("api_1")
        #expect(queries(http2) == ["api_1?limit=200&offset=23&order=oldest"])
    }

    @Test func rewrittenOrUnlistedSessions() async throws {
        let (log, http) = try makeLog()
        await log.refresh(list(20))
        available.mutate { $0 = 16 }
        await log.refresh(list(16)) // fewer messages than cached: fetched again from the start
        #expect(queries(http, from: 1) == ["api_1?limit=200&offset=0&order=oldest"])
        #expect(log.entries(of: "api_1").count == 6)
        await log.refresh([])
        #expect(log.entries(of: "api_1").isEmpty && log.all.isEmpty)
    }

    @Test func pagesUntilAShortPage() async throws {
        // 250 messages: 125 calls with their results.
        var json: [String] = []
        for i in 0..<125 {
            json.append(#"{"id": \#(2 * i + 1), "role": "assistant", "timestamp": \#(i), "tool_calls": [{"id": "c\#(i)", "function": {"name": "terminal", "arguments": "{\"command\":\"echo \#(i)\"}"}}]}"#)
            json.append(#"{"id": \#(2 * i + 2), "role": "tool", "tool_call_id": "c\#(i)", "content": "{\"output\": \"\#(i)\", \"exit_code\": 0}"}"#)
        }
        let messages = "[" + json.joined(separator: ",") + "]"
        let http = FakeHTTP { request in
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems ?? []
            func q(_ name: String) -> Int { Int(items.first { $0.name == name }?.value ?? "") ?? 0 }
            let all = try! JSONSerialization.jsonObject(with: Data(messages.utf8)) as! [Any]
            let page = all.dropFirst(q("offset")).prefix(q("limit"))
            return (200, String(decoding: try! JSONSerialization.data(withJSONObject: ["data": Array(page)]), as: UTF8.self))
        }
        let log = CommandLog(rest: RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http))
        await log.refresh([SessionInfo(id: "cli_1", messageCount: 250)])
        #expect(queries(http) == ["cli_1?limit=200&offset=0&order=oldest", "cli_1?limit=200&offset=200&order=oldest"])
        #expect(log.entries(of: "cli_1").map(\.output) == (0..<125).map { "\($0)" })
    }
}
