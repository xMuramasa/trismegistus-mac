import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// Dispatch's prompt and visibility, the Needs-check inbox (items, "look at" lines) and its answers, against the fake relay.
@Suite struct GitHubInboxTests {
    func comment(_ body: String, at date: String = "2026-11-02T00:48:00Z") -> GitHubComment {
        GitHubComment(author: "xMuramasa", body: body, createdAt: date, url: "https://github.com/x#\(date)")
    }

    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: URL(string: "https://relay.invalid/")!, token: fakeToken, http: http), http)
    }

    static func ok(_ r: URLRequest) -> (Int, String) {
        switch r.httpMethod {
        case "POST": (201, #"{"author":"xMuramasa","body":"x","created_at":"2026-11-03T10:00:00Z","url":"https://github.com/x"}"#)
        case "PATCH": (200, #"{"state":"open"}"#)
        default: (200, #"{"status":"Done","priority":"P1"}"#)
        }
    }

    func summary(_ rs: [URLRequest]) -> [String] { rs.map { "\($0.httpMethod!) \($0.url!.path.split(separator: "/").suffix(2).joined(separator: "/"))" } }

    func body(_ r: URLRequest) -> JSONValue? { r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) } }

    // MARK: Header and readout

    func issue(body: String) throws -> GitHubIssue {
        let json = #"{"repo":"o/r","number":3,"title":"t","body":\#(String(data: try JSONEncoder().encode(body), encoding: .utf8)!),"state":"open","author":"a","labels":[],"created_at":"2026-11-02T00:48:00Z","updated_at":"2026-11-02T00:48:00Z","url":"u","on_board":true,"status":"Todo","priority":"","comments_total":0,"comments":[]}"#
        return try JSONDecoder().decode(GitHubIssue.self, from: Data(json.utf8))
    }

    @Test func taskReadingCountsTheBody() throws {
        #expect(try issue(body: "## Monitors\n- [ ] a\n- [x] b\n  - [X] nested\n\nThen:\n- [ ] c").taskReading == "2/4")
        #expect(try issue(body: "- [ ] a\n- [ ] b\n- [ ] c\n- [ ] d\n- [ ] e\n- [ ] f\n- [ ] g\n- [ ] h\n- [ ] i").taskReading == "0/9")
    }

    @Test func noTaskListHidesTheReading() throws {
        #expect(try issue(body: "Prose with a\n- bullet\n1. and a number").taskReading == nil)
        #expect(try issue(body: "").taskReading == nil)
        #expect(try issue(body: "```\n- [ ] in code\n```").taskReading == nil)
    }

    @Test func agentIsTheLabelsValue() {
        #expect(["area: app", "agent: opus"].agentValue == "opus")
        #expect(["Agent:sonnet"].agentValue == "sonnet")
        #expect(["agent:", "agent: opus"].agentValue == "opus")
        #expect(["area: app", "agents", "reagent: x"].agentValue == nil)
        #expect([String]().agentValue == nil)
    }

    // MARK: Ticks

    @Test func ticksArePerIssue() {
        var ticks = GitHubInbox.Ticks()
        ticks.toggle("the sidebar", issue: "o/r#1")
        ticks.toggle("the icons", issue: "o/r#1")
        ticks.toggle("the sidebar", issue: "o/r#2")
        ticks.toggle("the icons", issue: "o/r#1")
        #expect(ticks.ticked("o/r#1") == ["the sidebar"])
        #expect(ticks.ticked("o/r#2") == ["the sidebar"])
        #expect(ticks.ticked("o/r#3").isEmpty)
    }

    // MARK: Dispatch

    @Test func promptIsTheWholeMessage() {
        #expect(GitHubDispatch.prompt(repo: "xMuramasa/trismegistus-mac", number: 49) == "Dispatch xMuramasa/trismegistus-mac#49")
    }

    @Test func visibility() {
        func option(_ labels: [String] = [], open: Bool = true, manager: Bool = true, run: Bool = false) -> GitHubDispatch.Option {
            GitHubDispatch.option(labels: labels, isOpen: open, canManage: manager, hasLiveRun: run)
        }
        #expect(option(["app", "P1"]) == .button)
        #expect(option(open: false) == .none)
        #expect(option(manager: false) == .none)
        #expect(option(run: true) == .none)
        #expect(option(["needs-design"]) == .hidden(tooltip: "Dispatch hidden: needs-design (design not agreed)"))
        #expect(option(["app", "needs-decision"]) == .hidden(tooltip: "Dispatch hidden: needs-decision (waiting for your decision)"))
        #expect(option(["On-Hold"]) == .hidden(tooltip: "Dispatch hidden: on-hold (parked)"))
        #expect(option(["needs-design"], open: false) == .none)
        #expect(option(["needs-design"], manager: false) == .none)
    }

    @Test func dispatchSetsReadyThenStarts() async throws {
        let (api, http) = rest(Self.ok)
        let started = Watched(0)
        try await GitHubInbox.dispatch(api, repo: "xMuramasa/m", number: 49) {
            // The status is already written when the chat starts.
            #expect(http.requests.current.count == 1)
            started.mutate { $0 += 1 }
        }
        #expect(started.current == 1 && summary(http.requests.current) == ["PUT 49/board"])
        #expect(body(http.requests.current[0]) == .object(["status": .string("Ready")]))
    }

    @Test func dispatchStartsNothingWhenTheStatusWriteFails() async {
        let (api, _) = rest { _ in (403, #"{"error":{"code":"forbidden","message":"this needs a manager device"}}"#) }
        let started = Watched(0)
        await #expect(throws: GitHubError.self) { try await GitHubInbox.dispatch(api, repo: "xMuramasa/m", number: 49) { started.mutate { $0 += 1 } } }
        #expect(started.current == 0)
    }

    // MARK: Look-at lines

    @Test func theOneLongLineOfIssue41IsSplit() {
        let text = "Merged 5e75ead.\n\nOn screen for Martin: the report's nine checks; the main ones are the grey sidebar against 09f, ⌘1–⌘6 / the icons; each section's list + detail; no width jitter (#28)"
        let note = GitHubInbox.note(in: [comment(text)])
        #expect(note?.lines == ["the report's nine checks", "the main ones are the grey sidebar against 09f, ⌘1–⌘6 / the icons",
                                "each section's list + detail", "no width jitter (#28)"])
        #expect(note?.date == "2026-11-02T00:48:00Z")
    }

    @Test func aLineWithoutSemicolonsStaysOne() {
        let note = GitHubInbox.note(in: [comment("**On screen for Martin:** open GitHub, issue #50 or trismegistus#27: the running mark")])
        #expect(note?.lines == ["open GitHub, issue #50 or trismegistus#27: the running mark"])
    }

    @Test func markerVariantsAndLists() {
        let heading = "Done.\n\n## On screen for Martin\n- the grey sidebar against `09f`\n- **⌘1–⌘6** switch sections\n\n- opened from Jobs\n\nNext steps\n- not this one"
        #expect(GitHubInbox.note(in: [comment(heading)])?.lines == ["the grey sidebar against 09f", "⌘1–⌘6 switch sections", "opened from Jobs"])
        #expect(GitHubInbox.note(in: [comment("- On screen: the tab row\n1. first\n2) second")])?.lines == ["the tab row", "first", "second"])
        #expect(GitHubInbox.note(in: [comment("**What to look at:**\n* one\n* two\n# Other\n* three")])?.lines == ["one", "two"])
        #expect(GitHubInbox.note(in: [comment("what to look at: the header\ncontinued here")])?.lines == ["the header", "continued here"])
    }

    @Test func theNewestCommentWithAMarkerWinsAndSixLinesAtMost() {
        let old = comment("On screen: old", at: "2026-11-01T00:00:00Z")
        let many = comment("On screen for Martin:\n" + (1...9).map { "- item \($0)" }.joined(separator: "\n"), at: "2026-11-02T00:00:00Z")
        let later = comment("Thanks, fixing it.", at: "2026-11-03T00:00:00Z")
        let note = GitHubInbox.note(in: [old, many, later])
        #expect(note?.lines == (1...6).map { "item \($0)" } && note?.date == "2026-11-02T00:00:00Z")
        #expect(GitHubInbox.note(in: [old, later])?.lines == ["old"])
    }

    @Test func noMarkerNoNote() {
        #expect(GitHubInbox.note(in: []) == nil)
        #expect(GitHubInbox.note(in: [comment("Merged. Looks fine on screen.")]) == nil)
        #expect(GitHubInbox.note(in: [comment("On screen for Martin")]) == nil) // marker with nothing after it
    }

    // MARK: Inbox items

    static let board = #"""
        {"status_options":["Todo","Ready","In progress","Needs check","Done"],"priority_options":["P1"],"items":[
         {"repo":"xMuramasa/trismegistus-mac","number":41,"title":"App: six sections","state":"closed","status":"Needs check","priority":"P1","labels":[],"updated_at":"2026-11-02T00:48:00Z","url":"u"},
         {"repo":"xMuramasa/trismegistus-mac","number":50,"title":"GitHub view: the live run","state":"open","status":"Needs check","priority":"P1","labels":[],"updated_at":"2026-11-03T08:00:00.5Z","url":"u"},
         {"repo":"xMuramasa/trismegistus-android","number":2,"title":"Phase 0","state":"open","status":"Needs check","priority":"","labels":[],"updated_at":"2026-11-01T00:00:00Z","url":"u"},
         {"repo":"xMuramasa/trismegistus-mac","number":49,"title":"Dispatch","state":"open","status":"Ready","priority":"P1","labels":[],"updated_at":"2026-11-03T09:00:00Z","url":"u"},
         {"repo":"xMuramasa/trismegistus-mac","number":3,"title":"Old","state":"open","status":"needs check","priority":"","labels":[],"updated_at":"2026-10-01T00:00:00Z","url":"u"}]}
        """#

    func board() throws -> GitHubBoard { try Wire.decode(GitHubBoard.self, from: Data(Self.board.utf8)) }

    @Test func inboxGroupsByRepoNewestFirst() throws {
        let groups = try board().needsCheck()
        #expect(groups.map(\.repo) == ["xMuramasa/trismegistus-android", "xMuramasa/trismegistus-mac"])
        #expect(groups.map { $0.items.map(\.number) } == [[2], [50, 41, 3]]) // open and closed, case-insensitive status
        #expect(try board().needsCheckCount == 4)
        #expect(GitHubInbox.shortName("xMuramasa/trismegistus-mac") == "trismegistus-mac")
    }

    @Test func inboxFilters() throws {
        let board = try board()
        #expect(board.needsCheck(repo: "xMuramasa/trismegistus-android").flatMap(\.items).map(\.number) == [2])
        #expect(board.needsCheck(matching: "six").flatMap(\.items).map(\.number) == [41])
        #expect(board.needsCheck(matching: "mac#50").flatMap(\.items).map(\.number) == [50])
        #expect(board.needsCheck(matching: "nothing").isEmpty)
    }

    // MARK: Answers

    @Test func looksGoodCommentsThenDone() async throws {
        let (api, http) = rest(Self.ok)
        try await GitHubInbox.confirm(api, repo: "xMuramasa/m", number: 41)
        let rs = http.requests.current
        #expect(summary(rs) == ["POST 41/comments", "PUT 41/board"])
        #expect(body(rs[0]) == .object(["body": .string("Confirmed on screen by Martin.")]))
        #expect(body(rs[1]) == .object(["status": .string("Done")]))
    }

    @Test func notRightCommentsReopensTheClosedAndSetsTodo() async throws {
        let (api, http) = rest(Self.ok)
        try await GitHubInbox.reject(api, repo: "xMuramasa/m", number: 41, note: "  The sidebar is still white.\n", isOpen: false)
        let rs = http.requests.current
        #expect(summary(rs) == ["POST 41/comments", "PATCH issues/41", "PUT 41/board"])
        #expect(body(rs[0]) == .object(["body": .string("The sidebar is still white.")]))
        #expect(body(rs[1]) == .object(["state": .string("open")]))
        #expect(body(rs[2]) == .object(["status": .string("Todo")]))
    }

    @Test func notRightOnAnOpenIssueDoesNotReopenAndABlankNoteWritesNothing() async throws {
        let (api, http) = rest(Self.ok)
        try await GitHubInbox.reject(api, repo: "xMuramasa/m", number: 50, note: "Wrong tab.", isOpen: true)
        #expect(summary(http.requests.current) == ["POST 50/comments", "PUT 50/board"])
        let (blank, none) = rest(Self.ok)
        await #expect(throws: GitHubError.self) { try await GitHubInbox.reject(blank, repo: "xMuramasa/m", number: 50, note: " \n", isOpen: true) }
        #expect(none.requests.current.isEmpty)
    }

    @Test func aFailedCommentStopsTheStatus() async {
        let (api, http) = rest { _ in (502, "<html>") }
        await #expect(throws: GitHubError.self) { try await GitHubInbox.confirm(api, repo: "xMuramasa/m", number: 41) }
        #expect(http.requests.current.count == 1)
    }
}
