import ServiceManagement

/// `SMAppService.mainApp` as the toggle needs it. The status is the system's, read fresh on `refresh()`.
@MainActor @Observable
final class LaunchAtLogin {
    private(set) var status = SMAppService.mainApp.status
    private(set) var error: String?

    /// Registered, or registered and waiting for the user's approval in System Settings.
    var isOn: Bool { status == .enabled || status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            // An ad-hoc signed build may be refused; the toggle then snaps back to the real state.
            self.error = "macOS refused: \(error.localizedDescription)"
        }
        refresh()
    }

    func openLoginItems() { SMAppService.openSystemSettingsLoginItems() }
}
