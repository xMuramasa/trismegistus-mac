import Foundation
import Testing
@testable import TrismegistusKit

/// ChatTimeline: a session's history, live events and outbox as chat rows, compact (popover) and window.
@Suite struct ChatTimelineTests {
    static let toolHistory = history(#"""
    [{"id":1,"role":"user","content":"List it","timestamp":1792801000},
     {"id":2,"role":"assistant","content":"","tool_calls":[{"id":"call_1","function":{"name":"terminal","arguments":"{\"command\":\"ls\"}"}}]},
     {"id":3,"role":"tool","content":"{\"output\":\"a.txt\",\"exit_code\":0}","tool_call_id":"call_1"},
     {"id":4,"role":"assistant","content":"One file."}]
    """#)

    /// A terminal call in run_1: started at seq, completed at seq + 1.
    static func command(_ seq: Int, _ cmd: String, exit: Int = 0, run: String = "run_1") -> [Event] {
        [event("s1", seq, run: run, .toolStarted(ToolStarted(tool: "terminal", preview: cmd))),
         event("s1", seq + 1, run: run, .toolCompleted(ToolCompleted(
             tool: "terminal", duration: 0.5, error: false, preview: #"{"output":"out","exit_code":\#(exit)}"#)))]
    }

    static func at(_ seq: Int) -> Date { Date(timeIntervalSince1970: Double(1_792_801_004_583 + seq) / 1000) }

    func state(_ events: [Event], outbox: [OutgoingPrompt] = [], history: [HistoryMessage] = []) -> SessionState {
        var s = SessionState(id: "s1")
        s.applyHistory(history)
        s.outbox = outbox
        for e in events { s.apply(.event(e)) }
        return s
    }

    @Test func historyOnly() {
        let s = state([], history: Self.toolHistory)
        let user = ChatItem.user(id: "h-1", text: "List it", time: Date(timeIntervalSince1970: 1_792_801_000))
        let answer = ChatItem.answer(id: "h-4", text: "One file.", time: nil)
        #expect(ChatTimeline.items(s, compact: true) == [
            user, .tool(id: "h-2-0", ToolRow(tool: "terminal", summary: "ls", duration: "", output: "a.txt", exitCode: 0)), answer,
        ])
        #expect(ChatTimeline.items(s, compact: false) == [user, answer]) // no marker for history turns
    }

    @Test func liveRunAfterAnOutboxPrompt() {
        var s = state([])
        s.outbox = [OutgoingPrompt(id: "c1", text: "What's in it?", status: .pending)]
        s.apply(.ack(clientMsgID: "c1", runID: "run_1", replayed: false))
        for e in Self.command(1, "ls\n-la") + [event("s1", 3, .answer(Answer(text: "Two files.")))] { s.apply(.event(e)) }
        let prompt = ChatItem.prompt(OutgoingPrompt(id: "c1", text: "What's in it?", status: .sent(runID: "run_1")), time: Self.at(1))
        let answer = ChatItem.answer(id: "e-3", text: "Two files.", time: Self.at(3))
        #expect(ChatTimeline.items(s, compact: true) == [
            prompt, .tool(id: "e-1", ToolRow(tool: "terminal", summary: "ls", duration: "0.5s", output: "out", exitCode: 0)), answer,
        ])
        #expect(ChatTimeline.items(s, compact: false) == [
            prompt, .marker(id: "m-run_1", RunSummary(commandCount: 1, totalDuration: 0.5, failedCount: 0)), answer,
        ])
        #expect(ChatTimeline.toolCount(s, runID: "run_1") == 1)
    }

    /// From the phone or Telegram: no prompt in the outbox, the run's rows stand alone; a prompt still pending stays last.
    @Test func runStartedElsewhere() {
        let pending = OutgoingPrompt(id: "c2", text: "next", status: .pending)
        let s = state([event("s1", 1, run: "run_9", .toolStarted(ToolStarted(tool: "terminal", preview: "make")))], outbox: [pending])
        #expect(ChatTimeline.items(s, compact: true) == [
            .tool(id: "e-1", ToolRow(tool: "terminal", summary: "make", duration: "…", output: nil, exitCode: nil)),
            .prompt(pending, time: nil),
        ])
    }

    @Test func failedPrompt() {
        let failed = OutgoingPrompt(id: "c1", text: "hi", status: .failed(code: nil, message: "Not connected to the relay."))
        let s = state([], outbox: [failed], history: Self.toolHistory)
        #expect(ChatTimeline.items(s, compact: false).last == .prompt(failed, time: nil))
    }

    /// The window's marker sits where the run's first tool call was, once per run, and only when it ran commands.
    @Test func markerPlacement() {
        let events = [event("s1", 1, .answer(Answer(text: "Looking.")))] + Self.command(2, "ls") + Self.command(4, "false", exit: 1)
            + [event("s1", 6, .runFailed(error: "boom")),
               event("s1", 7, run: "run_2", .toolStarted(ToolStarted(tool: "read_file", preview: "a.txt"))),
               event("s1", 8, run: "run_2", .toolCompleted(ToolCompleted(tool: "read_file", duration: 0.1, error: false)))]
        let s = state(events)
        #expect(ChatTimeline.items(s, compact: false).map(\.id) == ["e-1", "m-run_1", "e-6"])
        #expect(ChatTimeline.items(s, compact: false)[1]
            == .marker(id: "m-run_1", RunSummary(commandCount: 2, totalDuration: 1, failedCount: 1)))
        #expect(ChatTimeline.items(s, compact: false)[2] == .note(id: "e-6", text: "Run failed: boom", isError: true))
        #expect(ChatTimeline.items(s, compact: true).map(\.id) == ["e-1", "e-2", "e-4", "e-6", "e-7"])
    }

    /// trismegistus #11: the history that arrives after a finished run holds it; nothing shows twice.
    @Test func historyAfterAFinishedRunShowsNothingTwice() {
        var s = state([])
        s.outbox = [OutgoingPrompt(id: "c1", text: "List it", status: .pending)]
        s.apply(.ack(clientMsgID: "c1", runID: "run_1", replayed: false))
        for e in Self.command(1, "ls") + [event("s1", 3, .answer(Answer(text: "One file."))), event("s1", 4, .runCompleted)] {
            s.apply(.event(e))
        }
        s.applyHistory(Self.toolHistory)
        #expect(ChatTimeline.items(s, compact: true) == ChatTimeline.items(state([], history: Self.toolHistory), compact: true))
        #expect(ChatTimeline.items(s, compact: false).map(\.id) == ["h-1", "h-4"])
    }

    /// #54: a steer sits after the event it was sent after; a stored one is marked, without Hermes' wrapper.
    @Test func steersSitAmongTheirRunsEvents() {
        let prompt = OutgoingPrompt(id: "c1", text: "Draw the menu", status: .sent(runID: "run_1"))
        let steer = OutgoingPrompt(id: "st", text: "with the camera", status: .sent(runID: "run_1"), isSteer: true, afterSeq: 1)
        let events = [event("s1", 1, .answer(Answer(text: "Looking."))), event("s1", 2, .answer(Answer(text: "Drawn.")))]
        let items = ChatTimeline.items(state(events, outbox: [prompt, steer]), compact: true)
        #expect(items.map(\.id) == ["o-c1", "e-1", "o-st", "e-2"])
        let early = ChatTimeline.items(state([], outbox: [OutgoingPrompt(id: "st", text: "x", status: .sent(runID: "run_1"), isSteer: true)]), compact: false)
        #expect(early.map(\.id) == ["o-st"])
        let stored = state([], history: history(#"[{"id":9,"role":"user","display_kind":"steer","content":"with the camera"}]"#))
        #expect(ChatTimeline.items(stored, compact: false) == [.user(id: "h-9", text: "with the camera", time: nil, steer: true)])
    }
}
