import Foundation
import Observation
import TrismegistusKit

/// The Work board behind the sidebar's GitHub row and the GitHub view; the shared `DeviceProfile` says whether this
/// device may act on GitHub. One per connection, like `NewsFeed`. The relay caches GitHub reads for 30 s and drops the cache on every write.
@MainActor @Observable
final class GitHubModel {
    let rest: RelayREST
    private(set) var board: GitHubBoard?
    /// The last board load failed: what to show (`GitHubError.describe`). The board loaded before stays.
    private(set) var error: String?
    /// The relay has no GitHub token (or GitHub refused it): the view explains the setup.
    private(set) var notConfigured = false
    let device: DeviceProfile

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
}
