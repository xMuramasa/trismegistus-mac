import AppKit
import Observation
import TrismegistusKit
import UserNotifications

/// Local notifications from the open socket: approval requests, answered from the notification (Once / Session /
/// Deny), and runs that end while the popover and the window are closed. AppModel calls start once, at launch.
@MainActor @Observable
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    /// A notification was clicked: the session to show. The main window selects it and sets this back to nil.
    var openRequest: String?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private static let approvalCategory = UNNotificationCategory(
        identifier: "approval",
        // Never "always" (the protocol forbids it). No .foreground: answering doesn't bring the app up.
        actions: [
            UNNotificationAction(identifier: ApprovalChoice.once.rawValue, title: "Once"),
            UNNotificationAction(identifier: ApprovalChoice.session.rawValue, title: "Session"),
            UNNotificationAction(identifier: ApprovalChoice.deny.rawValue, title: "Deny", options: .destructive),
        ],
        intentIdentifiers: []
    )

    func start(model: AppModel) {
        self.model = model
        // Set before launch finishes, so an action that launched the app still reaches us.
        center.delegate = self
        center.setNotificationCategories([Self.approvalCategory])
        tasks = [
            Task { [weak self] in
                // Ask once paired; the system shows its prompt only the first time. Refusal or a failure (ad-hoc
                // signing) leaves notifications off, which Settings can't override; nothing else depends on it.
                for await paired in Observations({ !model.needsPairing }) where paired {
                    _ = try? await self?.center.requestAuthorization(options: [.alert, .sound])
                    return
                }
            },
            Task { [weak self] in
                var shown = Set<String>()
                for await approvals in Observations({ model.pendingApprovals }) {
                    guard let self else { return }
                    let ids = Set(approvals.map(\.id))
                    // Resolved anywhere (phone, popover, this notification) or the run ended.
                    let gone = shown.subtracting(ids).map { "approval.\($0)" }
                    center.removeDeliveredNotifications(withIdentifiers: gone)
                    center.removePendingNotificationRequests(withIdentifiers: gone)
                    for approval in approvals where !shown.contains(approval.id) { post(approval) }
                    shown = ids
                }
            },
            Task { [weak self] in
                var runs: [String: String] = [:] // session id → run id
                for await rows in Observations({ model.store?.overview ?? [:] }) {
                    guard let self else { return }
                    // lostTrack (reconnect, replay_gap) also drops the run but resets lastSeq: not an ending.
                    for (id, runID) in runs where rows[id]?.run?.id != runID && (rows[id]?.lastSeq ?? 0) > 0 {
                        runEnded(session: id, runID: runID)
                    }
                    runs = rows.compactMapValues(\.run?.id)
                }
            },
        ]
    }

    private func post(_ approval: PendingApproval) {
        guard NotificationSettings.isOn(NotificationSettings.approvals) else { return }
        let content = UNMutableNotificationContent()
        content.title = name(approval.sessionID)
        content.subtitle = "Approval requested"
        content.body = [approval.request.command, approval.request.description].compactMap(\.self).joined(separator: "\n")
        content.categoryIdentifier = Self.approvalCategory.identifier
        content.threadIdentifier = approval.sessionID
        content.userInfo = ["session": approval.sessionID, "request": approval.id]
        if NotificationSettings.isOn(NotificationSettings.approvalSound) { content.sound = .default }
        center.add(UNNotificationRequest(identifier: "approval.\(approval.id)", content: content, trigger: nil))
    }

    private func runEnded(session: String, runID: String) {
        guard NotificationSettings.isOn(NotificationSettings.runFinished), !isOnScreen else { return }
        // shortcut: the row only knows the run is gone; an open session's events say how it ended. A closed one
        // reads "finished" even if it failed or was stopped. Upgrade when SessionOverview keeps the end status.
        let end = model?.store?.sessions[session]?.events.last { $0.runID == runID && $0.payload.isTerminal }?.payload
        let body: String
        switch end {
        case .runCancelled: return // stopped by someone
        case .runFailed: body = "Run failed"
        default: body = "Run finished"
        }
        let content = UNMutableNotificationContent()
        content.title = name(session)
        content.body = body
        content.threadIdentifier = session
        content.userInfo = ["session": session]
        center.add(UNNotificationRequest(identifier: "run.\(runID)", content: content, trigger: nil))
    }

    /// The popover or an app window is up and not covered. The status item is a window too, but can't become key.
    private var isOnScreen: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeKey && $0.occlusionState.contains(.visible) }
    }

    private func name(_ session: String) -> String {
        model?.store?.overview[session]?.info?.title ?? "Hermes"
    }

    private func respond(action: String, session: String, request: String?) async {
        if let choice = ApprovalChoice(rawValue: action), let model,
           let approval = model.pendingApprovals.first(where: { $0.id == request }),
           approval.request.choices.contains(choice),
           (try? await model.approve(approval, choice: choice)) != nil {
            return
        }
        // A click, or an answer that can't be sent (already resolved, not offered, not connected): show the chat.
        openRequest = session
        NSApp.activate()
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        guard let session = info["session"] as? String else { return }
        let request = info["request"] as? String
        await respond(action: action, session: session, request: request)
    }
}
