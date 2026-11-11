import AppKit
import Foundation
import TrismegistusUI
import UserNotifications

/// UserDefaults keys of Settings' Notifications (#66): per event a banner switch (on when absent) and a sound name
/// (None, Default or a built-in macOS sound).
enum NotificationSettings {
    static let approvals = "notifications.approvalRequests"
    static let runFinished = "notifications.runFinishedWhileClosed"
    /// Absent: as run finished was (one switch covered both before #66).
    static let runFailed = "notifications.runFailed"
    /// Before #66 the approval sound's switch; off reads as the None sound while `sound.approval` is absent.
    static let approvalSound = "notifications.approvalSound"

    /// What a notification is about.
    enum Event: String, CaseIterable {
        case approval, finished, failed

        var title: String {
            switch self {
            case .approval: "Approval requests"
            case .finished: "Run finished"
            case .failed: "Run failed"
            }
        }

        var bannerKey: String {
            switch self {
            case .approval: NotificationSettings.approvals
            case .finished: NotificationSettings.runFinished
            case .failed: NotificationSettings.runFailed
            }
        }

        var soundKey: String { "notifications.sound.\(rawValue)" }

        var defaultSound: String {
            switch self {
            case .approval: NotificationTable.standard
            case .finished: "Glass"
            case .failed: "Basso"
            }
        }
    }

    static func isOn(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }

    /// `stored` is the event's banner key as read (nil when absent).
    static func banner(_ event: Event, stored: Bool?, defaults: UserDefaults = .standard) -> Bool {
        stored ?? (event == .failed ? isOn(runFinished, defaults: defaults) : true)
    }

    static func banner(_ event: Event, defaults: UserDefaults = .standard) -> Bool {
        banner(event, stored: defaults.object(forKey: event.bannerKey) as? Bool, defaults: defaults)
    }

    /// `stored` is the event's sound key as read (nil when absent).
    static func sound(_ event: Event, stored: String?, defaults: UserDefaults = .standard) -> String {
        if let stored { return stored }
        if event == .approval, defaults.object(forKey: approvalSound) as? Bool == false { return NotificationTable.none }
        return event.defaultSound
    }

    static func sound(_ event: Event, defaults: UserDefaults = .standard) -> String {
        sound(event, stored: defaults.string(forKey: event.soundKey), defaults: defaults)
    }

    /// The notification sound for a name: nil for None. `UNNotificationSound(named:)` looks in the app bundle and the
    /// container's `Library/Sounds`, not in `/System/Library/Sounds`, so a system sound is copied there first.
    static func notificationSound(_ name: String) -> UNNotificationSound? {
        guard name != NotificationTable.none else { return nil }
        guard NotificationTable.systemSounds.contains(name) else { return .default }
        let file = name + ".aiff"
        let folder = URL.libraryDirectory.appending(path: "Sounds")
        let copy = folder.appending(path: file)
        if !FileManager.default.fileExists(atPath: copy.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? FileManager.default.copyItem(at: URL(filePath: "/System/Library/Sounds").appending(path: file), to: copy)
        }
        return UNNotificationSound(named: UNNotificationSoundName(file))
    }

    /// Settings' ▶: the sound as it would play. Default is the system alert sound.
    static func preview(_ name: String) {
        if name == NotificationTable.standard { NSSound.beep() } else { NSSound(named: name)?.play() }
    }
}
