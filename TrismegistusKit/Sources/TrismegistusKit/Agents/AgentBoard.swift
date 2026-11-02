import Foundation
import Observation

/// Background agents through the relay; the shared `DeviceProfile` says whether this device may stop them. A new one per
/// pairing; the list is fetched on every connect, every 15 s in the background and every 3 s while the Agents view is shown.
@MainActor @Observable
public final class AgentBoard {
    /// Running first, then newest first (the relay's order).
    public private(set) var agents: [Agent] = []
    /// The last refresh failed. The agents it had stay, except for `not_configured`, which empties the list.
    public private(set) var error: AgentsError?
    public private(set) var isLoaded = false
    /// Stopped from here and still alive: the helper answers at once and the list shows the end a moment later.
    public private(set) var stopping: Set<String> = []

    public let rest: RelayREST
    let device: DeviceProfile

    public init(rest: RelayREST, device: DeviceProfile) {
        self.rest = rest
        self.device = device
    }

    /// No stop button until the relay has said this device is a manager.
    public var canManage: Bool { device.canManage }
    public var runningCount: Int { agents.filter(\.alive).count }
    /// A run is alive: the menu bar glyph's mark.
    public var anyRunning: Bool { agents.contains(where: \.alive) }
    /// The host helper isn't installed or isn't running.
    public var notConfigured: Bool { error?.isNotConfigured == true }

    /// The run on an issue (`owner/name` and number), if the helper lists one.
    public func run(on repo: String, issue: Int) -> Agent? { Agent.run(on: repo, issue: issue, in: agents) }

    public func refresh() async {
        do {
            agents = try await rest.agents()
            error = nil
        } catch {
            // A view that went away cancels its load; that is not the relay's answer.
            guard !Task.isCancelled else { return }
            self.error = AgentsError.wrap(error)
            if notConfigured { agents = [] }
        }
        stopping.formIntersection(agents.filter(\.alive).map(\.id))
        isLoaded = true
    }

    /// Manager only. Returns once the helper accepted; `alive` turns false in a later `refresh()`.
    public func stop(_ agent: Agent) async throws {
        try await rest.stopAgent(agent.id)
        stopping.insert(agent.id)
        await refresh()
    }
}
