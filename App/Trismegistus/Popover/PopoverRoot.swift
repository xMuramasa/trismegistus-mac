import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The menu bar popover (380×560): the sessions list (02, 02b, 02c), with a chat or the settings pushed inside it.
struct PopoverRoot: View {
    private enum Page: Equatable {
        case list, chat(String), news, settings
    }

    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage("chat.kind") private var chatKind = ConversationKind.app
    @State private var page = Page.list
    @State private var reconnect = Reconnect()
    @State private var error: String?
    @State private var lastRefresh = Date.distantPast

    private var isConnected: Bool {
        if case .connected = model.connection { return true }
        return false
    }

    var body: some View {
        Group {
            switch page {
            case .list: home
            case .chat(let id): ChatPage(sessionID: id) { page = .list }
            case .news: NewsPage { page = .list }
            case .settings: settings
            }
        }
        .frame(width: Size.popover.width, height: Size.popover.height)
        .background(Ink.surface.window)
        .refreshesNews(model)
        .onChange(of: model.connection, initial: true) { _, state in reconnect.observe(state) }
        .task { await refresh() }
        // A MenuBarExtra window is created once; becoming key is the nearest thing to "the popover opened".
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await refresh() }
        }
    }

    // MARK: Home

    private var home: some View {
        VStack(spacing: 0) {
            header
            if !isConnected { reconnectNotice.padding(.horizontal, Space.l).padding(.bottom, Space.s) }
            if let message = error ?? model.sessionsError, isConnected {
                Notice(title: "Sessions", message: message, isError: true) {
                    EndfieldButton("Dismiss", symbol: Symbol.close, kind: .quiet, iconOnly: true) { error = nil }
                }
                .padding(.horizontal, Space.l).padding(.bottom, Space.s)
            }
            SessionList(isStale: !isConnected, error: $error, onOpen: { page = $0 == NewsRowView.id ? .news : .chat($0) }, onNew: newSession)
            KeyHintStrip(homeHints)
        }
    }

    private var homeHints: [(key: String, action: String)] {
        if !isConnected { return [("⌘R", "retry now"), ("⌘,", "settings"), ("esc", "close")] }
        if model.sessions.isEmpty { return [("⌘N", "new"), ("⌘,", "settings"), ("esc", "close")] }
        return [("↑↓", "move"), ("↩", "open"), ("⌘N", "new"), ("⌘,", "settings")]
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            TMark().scaleEffect(1.3).frame(width: Size.headerMark, height: Size.headerMark).foregroundStyle(Ink.text.primary)
            TitleRule("Trismegistus").fixedSize()
            Spacer(minLength: Space.s)
            StatusReadout(isConnected ? .linked : .reconnecting, detail: isConnected ? model.deviceName ?? "" : "")
            EndfieldButton("Open window", symbol: Symbol.window, kind: .quiet, iconOnly: true) {
                openWindow(id: "main")
                NSApp.activate() // the window may already be open behind other apps
            }
            EndfieldButton("Settings", symbol: "slider.horizontal.3", kind: .quiet, iconOnly: true, shortcut: KeyboardShortcut(",")) {
                page = .settings
            }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    private var reconnectNotice: some View {
        let connecting = model.connection == .connecting
        return countdownNotice(connecting: connecting, attempt: max(reconnect.attempt, 1))
    }

    /// The message is rebuilt every second for the countdown.
    private func countdownNotice(connecting: Bool, attempt: Int) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let message: String
            if connecting {
                message = "Showing the last known state. Attempt \(attempt), connecting."
            } else if case .reconnecting(_, let at) = model.connection {
                message = "Showing the last known state. Attempt \(attempt), next in \(max(0, Int(at.timeIntervalSince(context.date).rounded(.up)))) s."
            } else {
                message = "Showing the last known state. Attempt \(attempt)."
            }
            return Notice(title: connecting && reconnect.attempt == 0 ? "Connecting" : "Relay unreachable", message: message) {
                EndfieldButton("Retry", symbol: Symbol.retry, iconOnly: true, shortcut: KeyboardShortcut("r")) { retryNow() }
            }
        }
    }

    // MARK: Settings

    private var settings: some View {
        VStack(spacing: 0) {
            HStack {
                EndfieldButton("Back", symbol: "chevron.left", kind: .quiet, iconOnly: true, shortcut: .cancelAction) { page = .list }
                Spacer()
            }
            .padding(.horizontal, Space.l).frame(height: Size.rowCompact)
            SettingsView()
        }
    }

    // MARK: Actions

    private func newSession() {
        guard let store = model.store else { return }
        Task {
            do {
                let session = try await store.createSession()
                chatKind = .app // back on the list it is in the tab
                page = .chat(session.id)
            } catch {
                self.error = (error as? RelayAPIError)?.message ?? "Can't reach the relay."
            }
        }
    }

    private func retryNow() {
        guard let client = model.store?.client else { return }
        Task { await client.retryNow() }
    }

    private func refresh() async {
        guard isConnected, Date().timeIntervalSince(lastRefresh) > 2 else { return }
        lastRefresh = Date()
        do { try await model.store?.refreshSessions() } catch {
            self.error = (error as? RelayAPIError)?.message ?? "Can't reach the relay."
        }
    }
}
