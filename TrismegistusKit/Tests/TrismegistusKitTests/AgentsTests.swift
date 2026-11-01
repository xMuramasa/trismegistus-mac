import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// The relay's `/api/agents` (bodies as the Background agents section of the relay's SPEC describes them), the
/// transcript's paging and the board.
@Suite struct AgentsTests {
    static let list = #"""
        {"agents":[
         {"id":"run_issue-22","kind":"delegate","title":"issue-22","command":"bash /runs/issue-22-launch.sh","cwd":"/wt/issue-22","started_at":1793500000,"alive":true,"session_id":"20261101_090000_ab12","transcript":true,"progress":"Item 2 done, tests green"},
         {"id":"proc_a1b2","kind":"process","title":"npm run dev","command":"npm run dev","started_at":1793499000,"alive":true,"transcript":false},
         {"id":"run_issue-21","kind":"delegate","title":"issue-21","started_at":1793400000.5,"ended_at":1793403600,"alive":false,"transcript":true,"progress":"Report written","outcome":"success","num_turns":41,"duration_ms":3600000},
         {"id":"run_issue-20","kind":"delegate","title":"issue-20","started_at":1793300000,"ended_at":1793301000,"alive":false,"transcript":true,"outcome":"error_max_turns","num_turns":120,"duration_ms":1000000},
         {"id":"run_killed","kind":"delegate","title":"killed","alive":false,"transcript":true},
         {"nope":true}]}
        """#

    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: URL(string: "https://relay.invalid/")!, token: fakeToken, http: http), http)
    }

    /// `n` text steps from stream line `from`.
    func steps(_ from: Int, _ n: Int) -> String {
        (0..<n).map { #"{"line":\#(from + $0),"kind":"text","text":"step \#(from + $0)"}"# }.joined(separator: ",")
    }

    func after(_ r: URLRequest) -> Int {
        URLComponents(url: r.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "after" }?.value.flatMap(Int.init) ?? -1
    }

    // MARK: Decoding

    @Test func agents() async throws {
        let (api, http) = rest { _ in (200, Self.list) }
        let agents = try await api.agents()
        #expect(agents.map(\.id) == ["run_issue-22", "proc_a1b2", "run_issue-21", "run_issue-20", "run_killed"]) // the bad entry is skipped
        #expect(http.requests.current.first?.url?.path == "/api/agents" && http.requests.current.first?.httpMethod == "GET")

        let running = agents[0]
        #expect(running.isDelegate && running.alive && running.hasTranscript && running.sessionID == "20261101_090000_ab12")
        #expect(running.progress == "Item 2 done, tests green" && running.cwd == "/wt/issue-22" && running.statusWords == "running")
        #expect(running.started == Date(timeIntervalSince1970: 1_793_500_000) && running.ended == nil && !running.failed)

        let process = agents[1]
        #expect(!process.isDelegate && !process.hasTranscript && process.command == "npm run dev" && process.sessionID == nil)

        let done = agents[2]
        #expect(!done.alive && done.statusWords == "done" && !done.failed && done.numTurns == 41 && done.durationMs == 3_600_000)
        #expect(done.started == Date(timeIntervalSince1970: 1_793_400_000.5) && done.ended == Date(timeIntervalSince1970: 1_793_403_600))

        #expect(agents[3].failed && agents[3].statusWords == "out of turns")
        // Killed runs leave no result line: ended, neither done nor failed.
        #expect(agents[4].statusWords == "ended" && !agents[4].failed)
    }

    @Test func missingFieldsGetDefaults() throws {
        let agent = try Wire.decode(Agent.self, from: Data(#"{"id":"proc_x"}"#.utf8))
        #expect(agent.title == "proc_x" && agent.kind == "process" && !agent.alive && !agent.hasTranscript)
    }

    @Test func page() throws {
        let json = #"""
            {"steps":[{"line":3,"kind":"text","text":"Reading the spec."},{"line":4,"kind":"tool","text":"Bash: go test ./..."},
            {"line":5,"kind":"tool_result","text":"FAIL","error":true},{"line":6,"kind":"result","text":"# Done\nAll set."},
            {"line":7,"kind":"hologram","text":"?"},{"kind":"text"}],"next":8,"alive":false}
            """#
        let page = try Wire.decode(AgentTranscriptPage.self, from: Data(json.utf8))
        #expect(page.next == 8 && page.alive == false)
        #expect(page.steps.map(\.kind) == [.text, .tool, .toolResult, .result, .unknown]) // the step without a line is skipped
        #expect(page.steps[2].error && !page.steps[1].error && page.steps[3].text == "# Done\nAll set.")
        #expect(page.steps.map(\.id) == [3, 4, 5, 6, 7])
    }

    @Test func processWithoutTranscript() throws {
        let page = try Wire.decode(AgentTranscriptPage.self, from: Data(#"{"steps":[],"next":0}"#.utf8))
        #expect(page.steps.isEmpty && page.alive == nil)
    }

    // MARK: Paths and errors

    @Test func transcriptPath() async throws {
        let (api, http) = rest { _ in (200, #"{"steps":[],"next":12,"alive":true}"#) }
        _ = try await api.agentTranscript("run_issue-22", after: 12)
        let request = try #require(http.requests.current.first)
        #expect(request.url?.path == "/api/agents/run_issue-22/transcript" && after(request) == 12)
    }

    @Test func badIDsNeverReachTheRelay() async {
        let (api, http) = rest { _ in (200, "{}") }
        for id in ["", "proc_", "run_", "proc_../x", "proc_a/b", "run_a/b", "run_a b", "x_1", "proc_" + String(repeating: "a", count: 65)] {
            await #expect(throws: AgentsError.self) { try await api.stopAgent(id) }
            await #expect(throws: AgentsError.self) { _ = try await api.agentTranscript(id, after: 0) }
        }
        #expect(http.requests.current.isEmpty)
        _ = try? await api.stopAgent("run_issue-1.2_b")
        #expect(http.requests.current.count == 1)
    }

    @Test func notConfiguredAndForbidden() async throws {
        let (api, _) = rest { r in
            r.httpMethod == "POST"
                ? (403, #"{"error":{"code":"forbidden","message":"manager only"}}"#)
                : (503, #"{"error":{"code":"not_configured","message":"agents helper not configured"}}"#)
        }
        let listError = await #expect(throws: AgentsError.self) { _ = try await api.agents() }
        #expect(listError?.isNotConfigured == true && listError?.status == 503)
        let stopError = await #expect(throws: AgentsError.self) { try await api.stopAgent("proc_a1") }
        #expect(stopError?.code == "forbidden")
        #expect(AgentsError.describe(stopError!) == DeviceRole.viewerNotice)
    }

    @Test func stopPostsToTheAgent() async throws {
        let (api, http) = rest { _ in (202, #"{"stopping":true}"#) }
        try await api.stopAgent("proc_a1b2")
        let request = try #require(http.requests.current.first)
        #expect(request.httpMethod == "POST" && request.url?.path == "/api/agents/proc_a1b2/stop")
    }

    // MARK: Transcript paging

    /// The relay with `total` steps (lines 1...total), 200 to an answer, as the SPEC says.
    func relay(total: Int, alive: @escaping @Sendable () -> Bool = { false }) -> @Sendable (URLRequest) -> (Int, String) {
        { r in
            let from = max(0, self.after(r)) + 1
            let n = max(0, min(200, total - from + 1))
            return (200, #"{"steps":[\#(self.steps(from, n))],"next":\#(from + n - 1),"alive":\#(alive())}"#)
        }
    }

    @MainActor @Test func pagesUntilTheRelayHasNoMore() async {
        let (api, http) = rest(relay(total: 450))
        let transcript = AgentTranscript(id: "run_a", rest: api)
        await transcript.poll()
        #expect(transcript.steps.count == 450 && transcript.steps.first?.line == 1 && transcript.steps.last?.line == 450)
        #expect(http.requests.current.map(after) == [0, 200, 400])
        #expect(transcript.alive == false && transcript.isLoaded && transcript.error == nil)
    }

    @MainActor @Test func exactlyFullPageAsksOnceMore() async {
        let (api, http) = rest(relay(total: 400))
        let transcript = AgentTranscript(id: "run_a", rest: api)
        await transcript.poll()
        #expect(transcript.steps.count == 400 && http.requests.current.map(after) == [0, 200, 400])
    }

    @MainActor @Test func laterPollsReadOnlyWhatIsNew() async {
        let total = Watched(5)
        let (api, http) = rest { r in
            let n = total.current, from = max(0, self.after(r)) + 1
            return (200, #"{"steps":[\#(self.steps(from, max(0, n - from + 1)))],"next":\#(n),"alive":true}"#)
        }
        let transcript = AgentTranscript(id: "run_a", rest: api)
        await transcript.poll()
        await transcript.poll() // nothing new
        total.mutate { $0 = 8 }
        await transcript.poll()
        #expect(transcript.steps.map(\.line) == Array(1...8))
        #expect(http.requests.current.map(after) == [0, 5, 5])
        #expect(transcript.alive == true)
    }

    @MainActor @Test func keepsTheLast2000() async {
        let (api, _) = rest(relay(total: 2300))
        let transcript = AgentTranscript(id: "run_a", rest: api)
        await transcript.poll()
        #expect(transcript.steps.count == AgentTranscript.maxSteps && transcript.dropped == 300)
        #expect(transcript.steps.first?.line == 301 && transcript.steps.last?.line == 2300)
    }

    @MainActor @Test func aRelayThatDoesNotAdvanceDoesNotLoop() async {
        let (api, http) = rest { _ in (200, #"{"steps":[\#(self.steps(1, 200))],"next":0,"alive":true}"#) }
        let transcript = AgentTranscript(id: "run_a", rest: api)
        await transcript.poll()
        #expect(http.requests.current.count == 1)
    }

    @MainActor @Test func failedPollKeepsTheSteps() async {
        let ok = Watched(true)
        let (api, _) = rest { r in
            ok.current ? self.relay(total: 3)(r) : (503, #"{"error":{"code":"hermes_unavailable","message":"down"}}"#)
        }
        let transcript = AgentTranscript(id: "run_a", rest: api)
        await transcript.poll()
        ok.mutate { $0 = false }
        await transcript.poll()
        #expect(transcript.steps.count == 3 && transcript.error?.code == "hermes_unavailable")
    }

    @MainActor @Test func aFinishedAgentIsReadOnce() async {
        let (api, http) = rest(relay(total: 3))
        await AgentTranscript(id: "run_a", rest: api).follow(every: .milliseconds(1))
        #expect(http.requests.current.count == 1)
    }

    @MainActor @Test func followReadsOnceMoreAfterTheEnd() async {
        let polls = Watched(0)
        let (api, http) = rest { r in
            let n = polls.mutate { $0 += 1; return $0 }
            return self.relay(total: 3, alive: { n < 3 })(r)
        }
        await AgentTranscript(id: "run_a", rest: api).follow(every: .milliseconds(1))
        // Alive, alive, then ended (seen after being alive: one more read), then settled.
        #expect(http.requests.current.count == 4)
    }

    @MainActor @Test func followStopsWhenTheAgentIsGone() async {
        let (api, http) = rest { _ in (404, #"{"error":{"code":"not_found","message":"gone"}}"#) }
        await AgentTranscript(id: "run_a", rest: api).follow(every: .milliseconds(1))
        #expect(http.requests.current.count == 1)
    }

    // MARK: Board

    @MainActor @Test func boardCountsAndRole() async throws {
        let (api, http) = rest { r in
            r.url?.path == "/api/me" ? (200, #"{"device":"macbook","role":"manager"}"#) : (200, Self.list)
        }
        let device = DeviceProfile(rest: api)
        let board = AgentBoard(rest: api, device: device)
        #expect(!board.canManage && !board.anyRunning)
        await device.refresh()
        await board.refresh()
        #expect(board.agents.count == 5 && board.runningCount == 2 && board.anyRunning && board.canManage && board.isLoaded)
        #expect(http.requests.current.map { $0.url!.path } == ["/api/me", "/api/agents"])
    }

    @MainActor @Test func viewerCannotManage() async {
        let (api, _) = rest { _ in (200, #"{"device":"phone","role":"viewer"}"#) }
        let device = DeviceProfile(rest: api)
        await device.refresh()
        #expect(!AgentBoard(rest: api, device: device).canManage)
    }

    @MainActor @Test func notConfiguredEmptiesTheList() async {
        let configured = Watched(true)
        let (api, _) = rest { _ in
            configured.current ? (200, Self.list) : (503, #"{"error":{"code":"not_configured","message":"agents helper not configured"}}"#)
        }
        let board = AgentBoard(rest: api, device: DeviceProfile(rest: api))
        await board.refresh()
        configured.mutate { $0 = false }
        await board.refresh()
        #expect(board.notConfigured && board.agents.isEmpty && !board.anyRunning && board.isLoaded)
    }

    @MainActor @Test func otherFailuresKeepTheList() async {
        let up = Watched(true)
        let (api, _) = rest { _ in up.current ? (200, Self.list) : (502, "bad gateway") }
        let board = AgentBoard(rest: api, device: DeviceProfile(rest: api))
        await board.refresh()
        up.mutate { $0 = false }
        await board.refresh()
        #expect(board.agents.count == 5 && board.error?.status == 502 && !board.notConfigured)
    }

    @MainActor @Test func stopPostsThenRefreshes() async throws {
        let stopped = Watched(false)
        let (api, http) = rest { r in
            if r.httpMethod == "POST" { stopped.mutate { $0 = true }; return (202, #"{"stopping":true}"#) }
            return (200, stopped.current ? Self.list.replacingOccurrences(of: #""alive":true"#, with: #""alive":false"#) : Self.list)
        }
        let board = AgentBoard(rest: api, device: DeviceProfile(rest: api))
        await board.refresh()
        let agent = try #require(board.agents.first)
        try await board.stop(agent)
        #expect(http.requests.current.map(\.httpMethod) == ["GET", "POST", "GET"])
        #expect(board.runningCount == 0 && board.stopping.isEmpty)
    }

    @MainActor @Test func aFailedStopThrowsAndKeepsRunning() async throws {
        let (api, _) = rest { r in
            r.httpMethod == "POST" ? (403, #"{"error":{"code":"forbidden","message":"manager only"}}"#) : (200, Self.list)
        }
        let board = AgentBoard(rest: api, device: DeviceProfile(rest: api))
        await board.refresh()
        await #expect(throws: AgentsError.self) { try await board.stop(board.agents[0]) }
        #expect(board.stopping.isEmpty && board.runningCount == 2)
    }
}
