import Foundation

/// Dispatch: the first prompt Hermes reacts to (it runs `dispatch check` and `dispatch start`), and when the button shows.
public enum GitHubDispatch {
    public static let readyStatus = "Ready"

    /// Labels that keep an issue from being dispatched, with the reason the tooltip gives.
    static let blocking: [(label: String, reason: String)] = [
        ("needs-decision", "waiting for your decision"), ("needs-design", "design not agreed"), ("on-hold", "parked"),
    ]

    public enum Option: Equatable, Sendable {
        /// The yellow Dispatch button.
        case button
        /// An info mark with this tooltip in its place.
        case hidden(tooltip: String)
        /// Nothing: a viewer, a closed issue or a live run.
        case none
    }

    /// `Dispatch owner/repo#N`, exactly: the whole message.
    public static func prompt(repo: String, number: Int) -> String { "Dispatch \(repo)#\(number)" }

    public static func option(labels: [String], isOpen: Bool, canManage: Bool, hasLiveRun: Bool) -> Option {
        guard canManage, isOpen, !hasLiveRun else { return .none }
        let lower = labels.map { $0.lowercased() }
        if let hit = blocking.first(where: { lower.contains($0.label) }) {
            return .hidden(tooltip: "Dispatch hidden: \(hit.label) (\(hit.reason))")
        }
        return .button
    }
}

/// The Needs-check inbox: which board items, what Hermes asked Martin to look at, and the two answers.
public enum GitHubInbox {
    public static let status = "Needs check"
    public static let confirmation = "Confirmed on screen by Martin."
    static let maxLines = 6

    public static func isNeedsCheck(_ status: String) -> Bool { status.caseInsensitiveCompare(Self.status) == .orderedSame }

    /// What the panel shows from the newest comment that carries a marker line.
    public struct Note: Equatable, Sendable {
        public var lines: [String]
        /// RFC 3339, the comment's.
        public var date: String
    }

    /// The "look at" part of the newest comment with a marker line (`On screen for Martin`, `On screen:`,
    /// `What to look at`); nil when no comment has one or the marker has nothing after it. The author is not looked at:
    /// Hermes posts through Martin's account.
    public static func note(in comments: [GitHubComment]) -> Note? {
        for comment in comments.reversed() {
            if let lines = lookAt(comment.body) { return Note(lines: lines, date: comment.createdAt) }
        }
        return nil
    }

    /// The check panel's ticks, a personal aid: per issue (`owner/repo#n`), in memory, never sent. By line text, so a
    /// newer note starts unticked.
    public struct Ticks: Sendable {
        private var byIssue: [String: Set<String>] = [:]

        public init() {}

        public func ticked(_ issue: String) -> Set<String> { byIssue[issue] ?? [] }

        public mutating func toggle(_ line: String, issue: String) {
            if byIssue[issue, default: []].remove(line) == nil { byIssue[issue, default: []].insert(line) }
        }
    }

    static func lookAt(_ body: String) -> [String]? {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let start = lines.firstIndex(where: { markerRemainder($0) != nil }) else { return nil }
        var out: [String] = []
        if let first = markerRemainder(lines[start]), !first.isEmpty { out.append(first) }
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            if line.isEmpty {
                // A blank line ends the block unless a list goes on after it.
                guard let next = lines[i...].first(where: { !$0.isEmpty }), isListItem(next) else { break }
            } else if line.hasPrefix("#") {
                break
            } else {
                let text = clean(isListItem(line) ? stripBullet(line) : line)
                if !text.isEmpty { out.append(text) }
            }
            i += 1
        }
        // One long line is a list written with semicolons.
        if out.count == 1 { out = out[0].components(separatedBy: "; ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        return out.isEmpty ? nil : Array(out.prefix(maxLines))
    }

    /// The text after the colon of a marker line, cleaned; nil when the line is not a marker line.
    private static func markerRemainder(_ line: String) -> String? {
        let text = clean(line).drop(while: { "#- ".contains($0) })
        let head = ["on screen for martin", "on screen:", "what to look at"]
        guard head.contains(where: { text.lowercased().hasPrefix($0) }) else { return nil }
        guard let colon = text.firstIndex(of: ":") else { return "" }
        return text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "").trimmingCharacters(in: .whitespaces)
    }

    private static func isListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") || line.range(of: #"^\d+[.)] "#, options: .regularExpression) != nil
    }

    private static func stripBullet(_ line: String) -> String {
        line.replacingOccurrences(of: #"^([-*+]|\d+[.)]) +"#, with: "", options: .regularExpression)
    }

    /// `owner/repo#N` of the item (or `owner/repo` alone): the name without the owner.
    public static func shortName(_ repo: String) -> String { repo.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repo }

    // MARK: Answers

    /// Looks good: the comment, then Status Done.
    public static func confirm(_ rest: RelayREST, repo: String, number: Int) async throws {
        _ = try await rest.githubComment(repo: repo, number: number, body: confirmation)
        _ = try await rest.githubSetBoard(repo: repo, number: number, status: "Done")
    }

    /// Not right: the note as a comment, the issue reopened if it is closed, Status Todo. A blank note is refused.
    public static func reject(_ rest: RelayREST, repo: String, number: Int, note: String, isOpen: Bool) async throws {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw GitHubError(status: 0, code: "bad_request", message: "Say what's not right first.") }
        _ = try await rest.githubComment(repo: repo, number: number, body: text)
        if !isOpen { try await rest.githubSetOpen(repo: repo, number: number, true) }
        _ = try await rest.githubSetBoard(repo: repo, number: number, status: "Todo")
    }

    /// Dispatch: Status Ready first; `start` (the conversation) runs only when that worked.
    public static func dispatch(_ rest: RelayREST, repo: String, number: Int, start: @MainActor () async throws -> Void) async throws {
        _ = try await rest.githubSetBoard(repo: repo, number: number, status: GitHubDispatch.readyStatus)
        try await start()
    }
}

public extension GitHubBoard {
    /// Items whose Status is Needs check (open or closed), by repo name, newest updated first within a repo; `repo` and
    /// `matching` (a title or `owner/repo#n` fragment) narrow them.
    func needsCheck(repo: String? = nil, matching needle: String = "") -> [(repo: String, items: [GitHubBoardItem])] {
        let needle = needle.trimmingCharacters(in: .whitespaces)
        let shown = items.filter {
            GitHubInbox.isNeedsCheck($0.status) && (repo == nil || $0.repo == repo)
                && (needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle) || $0.id.localizedCaseInsensitiveContains(needle))
        }
        return Dictionary(grouping: shown, by: \.repo).keys.sorted().map { name in
            (name, shown.filter { $0.repo == name }.sorted { Self.date($0.updatedAt) > Self.date($1.updatedAt) })
        }
    }

    /// How many items are in the inbox, whatever the filters.
    var needsCheckCount: Int { items.filter { GitHubInbox.isNeedsCheck($0.status) }.count }

    private static func date(_ text: String) -> Date {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text)) ?? .distantPast
    }
}
