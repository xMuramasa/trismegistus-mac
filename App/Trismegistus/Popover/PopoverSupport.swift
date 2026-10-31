import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Names, times and labels the popover shows for a session.
enum PopoverFormat {
    static func title(_ info: SessionInfo) -> String {
        for candidate in [info.title, info.preview] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return text }
        }
        return "Untitled"
    }

    static func source(_ raw: String?) -> SessionSource {
        switch raw {
        case "api_server": .trismegistus
        case "telegram": .telegram
        case "cron": .cron
        default: .cli
        }
    }

    static func sourceName(_ raw: String?) -> String {
        switch source(raw) {
        case .trismegistus: "Trismegistus"
        case .telegram: "Telegram"
        case .cron: "Cron"
        case .cli: "CLI"
        }
    }

    /// "now", "3 min", "2 h", "yesterday", "5 d".
    static func ago(_ date: Date?, now: Date) -> String {
        guard let date else { return "—" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60) min"
        case ..<86400: return "\(s / 3600) h"
        case ..<172_800: return "yesterday"
        default: return "\(s / 86400) d"
        }
    }

    /// "00:42".
    static func elapsed(since start: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// Attempt number and next-retry time while the socket is down. The Kit doesn't expose them, so this follows its
/// state changes and repeats its backoff (1 s doubling to 30 s, jitter ignored): the countdown is an estimate.
struct Reconnect {
    private(set) var attempt = 0
    private(set) var retryAt: Date?

    mutating func observe(_ state: RelayClient.ConnectionState, now: Date = .now) {
        switch state {
        case .connecting:
            attempt += 1
            retryAt = nil
        case .disconnected:
            retryAt = now.addingTimeInterval(min(30, Double(1 << min(max(attempt - 1, 0), 5))))
        case .connected, .authFailed:
            attempt = 0
            retryAt = nil
        }
    }
}

/// A strip under the header: yellow edge, caps title, one line of text, an optional trailing view.
struct Notice<Trailing: View>: View {
    let title: String
    let message: String
    var isError = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).typeRole(.label).foregroundStyle(Theme.ink)
                Text(message).typeRole(.caption).foregroundStyle(isError ? Theme.red : Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background(Theme.raised)
        .overlay(alignment: .leading) { Rectangle().fill(isError ? Theme.red : Theme.yellow).frame(width: 3) }
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

extension Notice where Trailing == EmptyView {
    init(title: String, message: String, isError: Bool = false) {
        self.init(title: title, message: message, isError: isError) { EmptyView() }
    }
}
