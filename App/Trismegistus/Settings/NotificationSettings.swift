import Foundation

/// UserDefaults keys of the notification toggles in Settings. All default to on (an absent key reads as on).
/// The notifications code reads them with `UserDefaults.standard.bool(forKey:)` after `register(defaults:)`, or with
/// `NotificationSettings.isOn(_:)`.
enum NotificationSettings {
    static let approvals = "notifications.approvalRequests"
    static let runFinished = "notifications.runFinishedWhileClosed"
    static let approvalSound = "notifications.approvalSound"

    static func isOn(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
