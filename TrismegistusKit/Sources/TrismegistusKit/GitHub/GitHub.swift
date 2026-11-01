import Foundation

/// The Work board (`GET /api/github/board`): option names in board order, the owner's issues on it in board order.
/// An unset status or priority is `""`.
public struct GitHubBoard: Decodable, Sendable, Equatable {
    public var statusOptions: [String]
    public var priorityOptions: [String]
    public var items: [GitHubBoardItem]

    enum CodingKeys: String, CodingKey { case statusOptions = "status_options", priorityOptions = "priority_options", items }

    /// The status the board folds and leaves out of the sidebar's count.
    public static func isDone(_ status: String) -> Bool { status.caseInsensitiveCompare("Done") == .orderedSame }

    /// Open issues not Done: the sidebar row's count.
    public var openCount: Int { items.filter { $0.state == "open" && !Self.isDone($0.status) }.count }

    /// The repos on the board, sorted.
    public var repos: [String] { Set(items.map(\.repo)).sorted() }

    /// The items of `repo` (nil: every repo) with `priority` (nil: any; `""`: unset), grouped by status in board order,
    /// every option kept (empty ones too); items without a status last, when there are any. Items keep board order.
    public func groups(repo: String? = nil, priority: String? = nil) -> [(status: String, items: [GitHubBoardItem])] {
        let shown = items.filter { (repo == nil || $0.repo == repo) && (priority == nil || $0.priority == priority) }
        let byStatus = Dictionary(grouping: shown, by: \.status)
        var out = statusOptions.map { ($0, byStatus[$0] ?? []) }
        // An option renamed on the board since the item was read lands here too.
        let other = shown.filter { !statusOptions.contains($0.status) }
        if !other.isEmpty { out.append(("", other)) }
        return out
    }
}

public struct GitHubBoardItem: Decodable, Sendable, Equatable, Identifiable {
    /// `owner/name`.
    public var repo: String
    public var number: Int
    public var title: String
    /// `open` or `closed`.
    public var state: String
    public var status: String
    public var priority: String
    public var labels: [String]
    /// RFC 3339.
    public var updatedAt: String
    public var url: String

    public var id: String { "\(repo)#\(number)" }

    enum CodingKeys: String, CodingKey { case repo, number, title, state, status, priority, labels, updatedAt = "updated_at", url }
}

/// A repo's issues (`GET /api/github/repos/{owner}/{repo}/issues?state=`): the 100 most recently updated of `total`.
public struct GitHubIssueList: Decodable, Sendable, Equatable {
    public struct Issue: Decodable, Sendable, Equatable, Identifiable {
        public var number: Int
        public var title: String
        public var state: String
        public var labels: [String]
        public var comments: Int
        public var updatedAt: String
        public var url: String

        public var id: Int { number }

        enum CodingKeys: String, CodingKey { case number, title, state, labels, comments, updatedAt = "updated_at", url }
    }

    public var repo: String
    public var state: String
    public var total: Int
    public var issues: [Issue]
}

/// One issue with its last 100 comments, oldest first (`GET /api/github/repos/{owner}/{repo}/issues/{number}`).
public struct GitHubIssue: Decodable, Sendable, Equatable {
    public var repo: String
    public var number: Int
    public var title: String
    public var body: String
    public var state: String
    public var author: String
    public var labels: [String]
    public var createdAt: String
    public var updatedAt: String
    public var url: String
    public var onBoard: Bool
    public var status: String
    public var priority: String
    public var commentsTotal: Int
    public var comments: [GitHubComment]

    public var isOpen: Bool { state == "open" }

    enum CodingKeys: String, CodingKey {
        case repo, number, title, body, state, author, labels, createdAt = "created_at", updatedAt = "updated_at", url
        case onBoard = "on_board", status, priority, commentsTotal = "comments_total", comments
    }
}

public struct GitHubComment: Decodable, Sendable, Equatable {
    public var author: String
    public var body: String
    public var createdAt: String
    public var url: String

    enum CodingKeys: String, CodingKey { case author, body, createdAt = "created_at", url }
}

/// The relay's GitHub errors (`{"error": {code, message, retry_at?}}`); `not_configured` and `rate_limited` are REST-only, so not `ErrorCode`.
public struct GitHubError: Error, Sendable, Equatable {
    /// HTTP status; 0 when the request was refused before it was sent (a bad repo name).
    public let status: Int
    /// `not_configured`, `rate_limited`, `not_found`, `forbidden`, `bad_request`, `github_error`, or a relay code.
    public let code: String
    public let message: String
    /// `rate_limited` only.
    public let retryAt: Date?

    public init(status: Int, code: String, message: String, retryAt: Date? = nil) {
        self.status = status
        self.code = code
        self.message = message
        self.retryAt = retryAt
    }

    init(status: Int, body: Data) {
        struct Body: Decodable {
            struct Inner: Decodable { var code: String?; var message: String?; var retry_at: String? }
            var error: Inner?
        }
        let inner = (try? Wire.decode(Body.self, from: body))?.error
        self.init(
            status: status, code: inner?.code ?? "http_\(status)",
            message: String((inner?.message ?? "The relay answered \(status).").prefix(512)),
            retryAt: inner?.retry_at.flatMap { try? Date.ISO8601FormatStyle().parse($0) })
    }

    public var isNotConfigured: Bool { code == "not_configured" }

    /// What the app shows for any error of a GitHub call.
    public static func describe(_ error: any Error, timeZone: TimeZone = .current) -> String {
        switch error {
        case let e as GitHubError where e.isNotConfigured:
            return "GitHub isn't set up on the relay: it needs a GITHUB_TOKEN in its .env (or GitHub refused the one it has)."
        case let e as GitHubError where e.code == "rate_limited":
            guard let at = e.retryAt else { return "GitHub rate limit, retry later." }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let c = calendar.dateComponents([.hour, .minute], from: at)
            return "GitHub rate limit, retry at " + String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        case let e as GitHubError: return e.message
        case let e as RelayAPIError: return e.message
        default: return "Can't reach the relay."
        }
    }
}

/// Starting a Hermes conversation from an issue: its title and first prompt.
public enum GitHubPrompt {
    /// Characters of the issue body put in the prompt.
    public static let bodyLimit = 4000

    /// `owner/repo#n: title`, cut to the relay's 200 characters.
    public static func title(_ issue: GitHubIssue) -> String {
        let full = "\(issue.repo)#\(issue.number): \(issue.title)"
        return String(String.UnicodeScalarView(full.unicodeScalars.prefix(200)))
    }

    public static func text(_ issue: GitHubIssue) -> String {
        var body = issue.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty {
            body = "(The issue has no description.)"
        } else if body.count > bodyLimit {
            body = String(body.prefix(bodyLimit)) + "\n\n[Cut at \(bodyLimit) characters; the rest is on GitHub.]"
        }
        return """
            GitHub issue \(issue.repo)#\(issue.number): \(issue.title)
            \(issue.url)

            \(body)

            Read this issue and its comments, then propose next steps.
            """
    }
}

/// `GET /api/me`: the device's name and role. Management endpoints (GitHub actions, cron) need a `manager`.
public struct DeviceInfo: Decodable, Sendable, Equatable {
    public var device: String
    /// `manager` or `viewer`.
    public var role: String

    public var isManager: Bool { role == "manager" }
}
