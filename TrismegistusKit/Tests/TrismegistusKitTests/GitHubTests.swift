import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// The relay's `/api/github/*` and `/api/me` through RelayREST (bodies as relay/internal/server/github.go writes them),
/// the board's grouping and filters, and the prompt that starts a conversation from an issue.
@Suite struct GitHubTests {
    static let board = #"""
        {"status_options":["Todo","In progress","Needs check","Done"],"priority_options":["P0","P1","P2"],"items":[
         {"repo":"xMuramasa/trismegistus-mac","number":22,"title":"GitHub projects","state":"open","status":"In progress","priority":"P1","labels":["app"],"updated_at":"2026-11-01T09:30:00Z","url":"https://github.com/xMuramasa/trismegistus-mac/issues/22"},
         {"repo":"xMuramasa/trismegistus","number":21,"title":"GitHub endpoints","state":"closed","status":"Done","priority":"P1","labels":[],"updated_at":"2026-11-01T08:00:00Z","url":"https://github.com/xMuramasa/trismegistus/issues/21"},
         {"repo":"xMuramasa/trismegistus-mac","number":30,"title":"Jobs","state":"open","status":"Todo","priority":"","labels":["app","cron"],"updated_at":"2026-10-31T20:00:00.5Z","url":"https://github.com/xMuramasa/trismegistus-mac/issues/30"},
         {"repo":"xMuramasa/homelab","number":4,"title":"Backups","state":"open","status":"","priority":"P2","labels":[],"updated_at":"2026-10-30T10:00:00Z","url":"https://github.com/xMuramasa/homelab/issues/4"},
         {"repo":"xMuramasa/trismegistus-mac","number":12,"title":"Old done but open","state":"open","status":"Done","priority":"P0","labels":[],"updated_at":"2026-10-29T10:00:00Z","url":"https://github.com/xMuramasa/trismegistus-mac/issues/12"}]}
        """#

    static let issue = #"""
        {"repo":"xMuramasa/trismegistus-mac","number":22,"title":"GitHub projects","body":"Read + act on GitHub.\n\n- [ ] Board","state":"open","author":"xMuramasa","labels":["app"],"created_at":"2026-10-31T10:00:00Z","updated_at":"2026-11-01T09:30:00Z","url":"https://github.com/xMuramasa/trismegistus-mac/issues/22","on_board":true,"status":"In progress","priority":"P1","comments_total":1,"comments":[{"author":"hermes","body":"On it.","created_at":"2026-11-01T09:00:00Z","url":"https://github.com/xMuramasa/trismegistus-mac/issues/22#issuecomment-1"}]}
        """#

    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: URL(string: "https://relay.invalid/")!, token: fakeToken, http: http), http)
    }

    func body(_ r: URLRequest) -> JSONValue? { r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) } }

    // MARK: Decoding and paths

    @Test func board() async throws {
        let (api, http) = rest { _ in (200, Self.board) }
        let board = try await api.githubBoard()
        #expect(board.statusOptions == ["Todo", "In progress", "Needs check", "Done"])
        #expect(board.priorityOptions == ["P0", "P1", "P2"])
        #expect(board.items.map(\.id) == ["xMuramasa/trismegistus-mac#22", "xMuramasa/trismegistus#21", "xMuramasa/trismegistus-mac#30",
                                          "xMuramasa/homelab#4", "xMuramasa/trismegistus-mac#12"])
        #expect(board.items[2].labels == ["app", "cron"] && board.items[2].priority == "")
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "GET" && r.url?.absoluteString == "https://relay.invalid/api/github/board")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer \(fakeToken)")
    }

    @Test func issues() async throws {
        let (api, http) = rest { _ in
            (200, #"{"repo":"xMuramasa/homelab","state":"closed","total":120,"issues":[{"number":3,"title":"DNS","state":"closed","labels":["infra"],"comments":2,"updated_at":"2026-10-01T00:00:00Z","url":"https://github.com/xMuramasa/homelab/issues/3"}]}"#)
        }
        let list = try await api.githubIssues(repo: "xMuramasa/homelab", state: "closed")
        #expect(list.total == 120 && list.issues.map(\.number) == [3] && list.issues[0].comments == 2)
        #expect(http.requests.current.first?.url?.absoluteString == "https://relay.invalid/api/github/repos/xMuramasa/homelab/issues?state=closed")
        _ = try await api.githubIssues(repo: "xMuramasa/homelab", state: "anything")
        #expect(http.requests.current.last?.url?.query == "state=open")
    }

    @Test func issue() async throws {
        let (api, http) = rest { _ in (200, Self.issue) }
        let issue = try await api.githubIssue(repo: "xMuramasa/trismegistus-mac", number: 22)
        #expect(issue.isOpen && issue.onBoard && issue.status == "In progress" && issue.commentsTotal == 1)
        #expect(issue.comments.map(\.author) == ["hermes"])
        #expect(http.requests.current.first?.url?.path == "/api/github/repos/xMuramasa/trismegistus-mac/issues/22")
    }

    @Test func badRepoNamesNeverReachTheRelay() async {
        let (api, http) = rest { _ in (200, Self.issue) }
        for repo in ["xMuramasa", "xMuramasa/../api", "a/b/c", "xMuramasa/..", "xMuramasa/x?y", "/x", "xMuramasa/x%2F"] {
            await #expect(throws: GitHubError.self) { try await api.githubIssue(repo: repo, number: 1) }
        }
        await #expect(throws: GitHubError.self) { try await api.githubIssue(repo: "xMuramasa/x", number: 0) }
        #expect(http.requests.current.isEmpty)
    }

    @Test func writes() async throws {
        let (api, http) = rest { r in
            switch r.httpMethod {
            case "POST": (201, #"{"author":"xMuramasa","body":"Done.","created_at":"2026-11-01T10:00:00Z","url":"https://github.com/x"}"#)
            case "PATCH": (200, #"{"state":"closed"}"#)
            default: (200, #"{"status":"Needs check","priority":"P1"}"#)
            }
        }
        #expect(try await api.githubComment(repo: "xMuramasa/m", number: 5, body: "Done.").author == "xMuramasa")
        #expect(try await api.githubSetOpen(repo: "xMuramasa/m", number: 5, false) == "closed")
        let set = try await api.githubSetBoard(repo: "xMuramasa/m", number: 5, status: "Needs check")
        #expect(set.status == "Needs check" && set.priority == "P1")
        let rs = http.requests.current
        #expect(rs.map { "\($0.httpMethod!) \($0.url!.path)" } == [
            "POST /api/github/repos/xMuramasa/m/issues/5/comments", "PATCH /api/github/repos/xMuramasa/m/issues/5",
            "PUT /api/github/repos/xMuramasa/m/issues/5/board",
        ])
        #expect(body(rs[0]) == .object(["body": .string("Done.")]))
        #expect(body(rs[1]) == .object(["state": .string("closed")]))
        #expect(body(rs[2]) == .object(["status": .string("Needs check")])) // only what is set
    }

    @Test func me() async throws {
        let (api, http) = rest { _ in (200, #"{"device":"mac","role":"manager"}"#) }
        #expect(try await api.me().isManager)
        #expect(http.requests.current.first?.url?.path == "/api/me")
        let (viewer, _) = rest { _ in (200, #"{"device":"phone","role":"viewer"}"#) }
        #expect(try await !viewer.me().isManager)
    }

    // MARK: Errors

    @Test func errors() async {
        let (api, _) = rest { r in
            switch r.url!.path {
            case "/api/github/board": (503, #"{"error":{"code":"not_configured","message":"GitHub is not configured"}}"#)
            case "/api/github/repos/xMuramasa/a/issues/1": (429, #"{"error":{"code":"rate_limited","message":"GitHub rate limit; try again later","retry_at":"2026-11-01T14:05:00Z"}}"#)
            case "/api/github/repos/xMuramasa/a/issues/2": (403, #"{"error":{"code":"forbidden","message":"this needs a manager device"}}"#)
            default: (502, "<html>bad gateway</html>")
            }
        }
        await #expect(throws: GitHubError(status: 503, code: "not_configured", message: "GitHub is not configured")) { try await api.githubBoard() }
        let at = Date(timeIntervalSince1970: 1_793_541_900) // 2026-11-01T14:05:00Z
        await #expect(throws: GitHubError(status: 429, code: "rate_limited", message: "GitHub rate limit; try again later", retryAt: at)) {
            try await api.githubIssue(repo: "xMuramasa/a", number: 1)
        }
        await #expect(throws: GitHubError(status: 403, code: "forbidden", message: "this needs a manager device")) {
            try await api.githubIssue(repo: "xMuramasa/a", number: 2)
        }
        await #expect(throws: GitHubError(status: 502, code: "http_502", message: "The relay answered 502.")) {
            try await api.githubIssue(repo: "xMuramasa/a", number: 3)
        }
    }

    @Test func describe() {
        #expect(GitHubError.describe(GitHubError(status: 503, code: "not_configured", message: "x")).contains("GITHUB_TOKEN"))
        let at = Date(timeIntervalSince1970: 1_793_541_900)
        let santiago = TimeZone(secondsFromGMT: -3 * 3600)! // Santiago's summer time; no tz database needed
        #expect(GitHubError.describe(GitHubError(status: 429, code: "rate_limited", message: "x", retryAt: at), timeZone: santiago)
            == "GitHub rate limit, retry at 11:05")
        #expect(GitHubError.describe(GitHubError(status: 429, code: "rate_limited", message: "x")) == "GitHub rate limit, retry later.")
        #expect(GitHubError.describe(GitHubError(status: 400, code: "bad_request", message: "unknown status \"Later\"")) == "unknown status \"Later\"")
        #expect(GitHubError.describe(RelayAPIError.unexpected) == "The relay sent an unexpected response.")
        #expect(GitHubError.describe(URLError(.timedOut)) == "Can't reach the relay.")
    }

    // MARK: Grouping and filters

    func decoded() throws -> GitHubBoard { try Wire.decode(GitHubBoard.self, from: Data(Self.board.utf8)) }

    @Test func groupsByStatusInBoardOrder() throws {
        let groups = try decoded().groups()
        #expect(groups.map(\.status) == ["Todo", "In progress", "Needs check", "Done", ""])
        #expect(groups.map { $0.items.map(\.number) } == [[30], [22], [], [21, 12], [4]])
    }

    @Test func filters() throws {
        let board = try decoded()
        let mac = board.groups(repo: "xMuramasa/trismegistus-mac")
        #expect(mac.map(\.status) == ["Todo", "In progress", "Needs check", "Done"]) // no status-less group when none
        #expect(mac.flatMap(\.items).map(\.number) == [30, 22, 12])
        #expect(board.groups(priority: "P1").flatMap(\.items).map(\.number) == [22, 21])
        #expect(board.groups(priority: "").flatMap(\.items).map(\.number) == [30])
        #expect(board.groups(repo: "xMuramasa/trismegistus-mac", priority: "P0").flatMap(\.items).map(\.number) == [12])
        #expect(board.repos == ["xMuramasa/homelab", "xMuramasa/trismegistus", "xMuramasa/trismegistus-mac"])
    }

    @Test func openCountLeavesOutDoneAndClosed() throws {
        #expect(try decoded().openCount == 3) // 22, 30, 4; not 21 (closed) or 12 (Done)
        #expect(GitHubBoard.isDone("done") && !GitHubBoard.isDone("Needs check"))
    }

    // MARK: Start a conversation

    func issue(body: String, title: String = "GitHub projects") throws -> GitHubIssue {
        var issue = try Wire.decode(GitHubIssue.self, from: Data(Self.issue.utf8))
        issue.body = body
        issue.title = title
        return issue
    }

    @Test func prompt() throws {
        let issue = try issue(body: "Read + act on GitHub.\n\n- [ ] Board\n")
        #expect(GitHubPrompt.title(issue) == "xMuramasa/trismegistus-mac#22: GitHub projects")
        #expect(GitHubPrompt.text(issue) == """
            GitHub issue xMuramasa/trismegistus-mac#22: GitHub projects
            https://github.com/xMuramasa/trismegistus-mac/issues/22

            Read + act on GitHub.

            - [ ] Board

            Read this issue and its comments, then propose next steps.
            """)
        #expect(GitHubPrompt.text(try self.issue(body: "  \n")).contains("(The issue has no description.)"))
    }

    @Test func aLabelThatRepeatsThePriorityIsDropped() {
        #expect(["bug", "p0", "P1"].withoutPriority("P0") == ["bug", "P1"])
        #expect(["bug", "P0"].withoutPriority("") == ["bug", "P0"])
    }

    @Test func promptCapsTheBodyAndTheTitle() throws {
        let long = try issue(body: String(repeating: "é", count: 5000), title: String(repeating: "t", count: 300))
        let text = GitHubPrompt.text(long)
        #expect(text.contains(String(repeating: "é", count: 4000) + "\n\n[Cut at 4000 characters; the rest is on GitHub.]"))
        #expect(!text.contains(String(repeating: "é", count: 4001)))
        #expect(GitHubPrompt.title(long).unicodeScalars.count == 200)
        #expect(GitHubPrompt.title(long).hasPrefix("xMuramasa/trismegistus-mac#22: ttt"))
    }
}
