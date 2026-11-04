import Foundation
import Observation
import TrismegistusKit

/// The Work board behind the sidebar's GitHub row and the GitHub view; the shared `DeviceProfile` says whether this
/// device may act on GitHub. One per connection. The relay caches GitHub reads for 30 s and drops the cache on every write.
@MainActor @Observable
final class GitHubModel {
    let rest: RelayREST
    private(set) var board: GitHubBoard?
    /// The last board load failed: what to show (`GitHubError.describe`). The board loaded before stays.
    private(set) var error: String?
    /// The relay has no GitHub token (or GitHub refused it): the view explains the setup.
    private(set) var notConfigured = false
    let device: DeviceProfile
    /// The sidebar's Needs check tab is selected: an answered item selects the next one of the inbox.
    var inboxShown = false
    /// The "look at" notes of the inbox's items by `owner/repo#n`, with the `updated_at` they were read at (nil: no marker comment).
    private(set) var notes: [String: (updatedAt: String, note: GitHubInbox.Note?)] = [:]

    /// Write controls only for a `manager` device; a viewer, a relay without roles or a failed `/api/me` gets none.
    var isManager: Bool { device.canManage }

    init(rest: RelayREST, device: DeviceProfile) {
        self.rest = rest
        self.device = device
    }

    func refresh() async {
        do {
            board = try await rest.githubBoard()
            error = nil
            notConfigured = false
        } catch {
            // A view that went away cancels its load; that is not the relay's answer.
            guard !Task.isCancelled else { return }
            self.error = GitHubError.describe(error)
            notConfigured = (error as? GitHubError)?.isNotConfigured == true
        }
    }

    /// Reads the comments of the items whose note is missing or older than the item, four issues at a time.
    func loadNotes(for items: [GitHubBoardItem]) async {
        let todo = items.filter { notes[$0.id]?.updatedAt != $0.updatedAt }
        for start in stride(from: 0, to: todo.count, by: 4) {
            guard !Task.isCancelled else { return }
            let rest = rest
            await withTaskGroup(of: (id: String, updatedAt: String, note: GitHubInbox.Note?)?.self) { group in
                for item in todo[start..<min(start + 4, todo.count)] {
                    group.addTask {
                        guard let issue = try? await rest.githubIssue(repo: item.repo, number: item.number) else { return nil }
                        return (item.id, item.updatedAt, GitHubInbox.note(in: issue.comments))
                    }
                }
                for await read in group { if let read { notes[read.id] = (read.updatedAt, read.note) } }
            }
        }
    }
}
