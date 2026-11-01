import Foundation
import Observation

/// This device's name and role (`GET /api/me`), fetched once for the whole app: on each connect and when the app comes
/// to the foreground (`devices set-role` applies from the device's next request). Jobs, Agents and GitHub read it.
@MainActor @Observable
public final class DeviceProfile {
    /// Nil until the relay answered. A failed refresh keeps the last answer; a relay that predates roles (404) never
    /// gives one, so no write controls.
    public private(set) var info: DeviceInfo?

    private let rest: RelayREST

    public init(rest: RelayREST) {
        self.rest = rest
    }

    public var role: DeviceRole? { info.map { DeviceRole(rawValue: $0.role) ?? .viewer } }
    public var canManage: Bool { role == .manager }

    public func refresh() async {
        if let me = try? await rest.me() { info = me }
    }
}
