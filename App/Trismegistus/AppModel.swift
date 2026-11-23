import AppKit
import Foundation
import Observation
import TrismegistusKit

/// The app's state: the device token, the relay connection and the session store. Every scene gets it through the
/// environment (`@Environment(AppModel.self)`).
@MainActor @Observable
final class AppModel {
    static let defaultRelayURL = URL(string: "https://hermes.lab.x-muramasa.dev")!

    /// The relay this device is paired with.
    private(set) var relayURL: URL
    /// The name the relay gave this device when pairing.
    private(set) var deviceName: String?
    /// Nil until paired. Per-session state (`sessions[id]`), `open`/`close`, history and the REST calls live here.
    private(set) var store: SessionStore?
    /// This device's name and role (`GET /api/me`), fetched on each (re)connect and when the app comes to the
    /// foreground; Jobs, GitHub and Agents all read it.
    private(set) var device: DeviceProfile?
    /// Hermes' cron jobs (#21), refreshed on each (re)connect.
    private(set) var jobs: JobBoard?
    /// The GitHub row and view (#22): the Work board; a new one per connection.
    private(set) var github: GitHubModel?
    /// Background agents (#23): polled every 15 s while connected for the menu bar glyph's mark
    /// (the Agents view polls faster while shown).
    private(set) var agents: AgentBoard?
    /// The token couldn't be read at launch; shown on the pairing screen.
    private(set) var keychainError: String?
    /// The last session list refresh failed.
    private(set) var sessionsError: String?

    var role: DeviceRole? { device?.role }
    var connection: RelayClient.ConnectionState { store?.connection ?? .disconnected }
    var sessions: [SessionInfo] { store?.sessionList ?? [] }
    var pendingApprovals: [PendingApproval] { store?.pendingApprovals ?? [] }
    var isWorking: Bool { store?.isWorking ?? false }
    /// No token, or the relay refused it.
    var needsPairing: Bool {
        if case .authFailed = connection { return true }
        return store == nil
    }

    let notifications = Notifications()
    private let tokens: any TokenStore
    private let defaults: UserDefaults
    @ObservationIgnored private var watch: Task<Void, Never>?
    @ObservationIgnored private var agentsWatch: Task<Void, Never>?
    /// Saves `store.unseen` on each change (#66).
    @ObservationIgnored private var unseenWatch: Task<Void, Never>?
    /// Moves `trackedUntil` every 30 s once the launch has caught up; nil before.
    @ObservationIgnored private var tracking: Task<Void, Never>?
    @ObservationIgnored private var loadingAhead: Task<Void, Never>?
    /// The conversation each place shows, and its window: who is looking (#66).
    @ObservationIgnored private var viewers: [Viewer: Shown] = [:]

    /// Where a conversation can be open.
    enum Viewer {
        case window, popover
    }

    private struct Shown {
        let session: String
        weak var window: NSWindow?
    }

    init(tokens: any TokenStore = KeychainTokenStore(), defaults: UserDefaults = .standard) {
        self.tokens = tokens
        self.defaults = defaults
        relayURL = defaults.url(forKey: Keys.relayURL) ?? Self.defaultRelayURL
        deviceName = defaults.string(forKey: Keys.deviceName)
        do {
            if let token = try tokens.token() { connect(token: token) }
        } catch {
            keychainError = "Can't read the device token from the Keychain."
        }
        notifications.start(model: self)
        // `devices set-role` applies from the device's next request.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.markSeen()
                await self?.device?.refresh()
            }
        }
        // A window uncovered or shown (the popover opening) may put an open conversation in view.
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.markSeen() }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackNow() }
        }
    }

    // MARK: Run alerts (#66)

    /// `place` shows `session` (nil: no conversation) in `window`; a mark on what is now in view goes.
    func show(_ session: String?, in place: Viewer, window: NSWindow?) {
        viewers[place] = session.map { Shown(session: $0, window: window) }
        markSeen()
    }

    /// Someone looks at the thread `session` is in: it is open in the window or the popover, the app is active (or the
    /// popover key) and that window is on screen, not covered.
    func isWatching(_ session: String) -> Bool {
        guard let store else { return false }
        let tip = store.threadTip(of: session)
        return watched.contains { store.threadTip(of: $0) == tip }
    }

    /// The conversations in view now.
    private var watched: [String] {
        viewers.values.compactMap { viewer in
            // The popover is a panel: it can be key while the app isn't active.
            guard let window = viewer.window, NSApp.isActive || window.isKeyWindow, window.isVisible,
                  window.occlusionState.contains(.visible) else { return nil }
            return viewer.session
        }
    }

    /// Every part of the threads in view.
    private var watchedParts: Set<String> {
        guard let store else { return [] }
        return Set(watched.flatMap { id in
            let tip = store.threadTip(of: id)
            return [tip] + store.olderParts(of: tip)
        })
    }

    /// Opening a conversation is the only way its mark goes.
    func markSeen() {
        guard let store, !store.unseen.marks.isEmpty else { return }
        let parts = watchedParts
        if store.unseen.mark(parts) != nil { store.unseen.viewed(parts) }
    }

    /// The first conversations of the window's tab load their histories ahead, so picking one shows it at once rather
    /// than after a fetch that can take seconds on a slow link (Martin, 2026-11-23).
    private func loadAhead(_ store: SessionStore) {
        let listing = ConversationSidebar.listing(self)
        let stored = defaults.string(forKey: "chat.kind").flatMap(ConversationKind.init(rawValue:)) ?? .app
        let kind = ConversationSidebar.summary(listing, store: store).resolving(stored)
        let ids = (listing.inProgress + listing.pinned + listing.rest).filter { kind.includes($0.source) }.map(\.id)
        loadingAhead?.cancel()
        loadingAhead = Task { await store.prefetch(ids) }
    }

    /// The first list load of the launch catches up on what changed while the app was quit (a done mark, no sound),
    /// then `trackedUntil` follows the clock; a list load after a gap in that (the Mac asleep, the relay unreachable)
    /// catches up on the gap the same way. Every list load drops the marks of conversations that left it.
    private func listLoaded(_ store: SessionStore) {
        store.unseen.prune(keeping: Set(store.sessionList.map(\.id)))
        if tracking != nil {
            guard case .connected = store.connection, store.unseen.lostTrack(at: Date()) else { return }
            catchUp(store)
            return
        }
        catchUp(store)
        tracking = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.trackNow()
            }
        }
    }

    /// Marks what ended while the app couldn't follow, then follows from now. A conversation still running is left to
    /// its run's end, which marks it when it comes.
    private func catchUp(_ store: SessionStore) {
        let running = Set(store.overview.filter { $0.value.run != nil || $0.value.isWaitingForApproval }.keys)
        store.unseen.catchUp(store.sessionList, watched: watchedParts, running: running)
        store.unseen.tracked(at: Date())
    }

    /// Only after the catch-up and while connected, and never across a gap: that is the next list load's to catch up
    /// (`listLoaded`), or the next launch's.
    private func trackNow() {
        guard tracking != nil, let store, case .connected = store.connection, !store.unseen.lostTrack(at: Date()) else { return }
        store.unseen.tracked(at: Date())
    }

    private static func loadUnseen(_ defaults: UserDefaults) -> Unseen {
        defaults.data(forKey: Keys.unseen).flatMap { try? JSONDecoder().decode(Unseen.self, from: $0) } ?? Unseen()
    }

    /// Trades a pairing code for a device token, keeps it in the Keychain and connects. Throws RelayAPIError (a bad,
    /// used or expired code is `.unauthorized`) or KeychainError.
    func pair(code: String, url: URL) async throws {
        guard url.scheme == "https", url.host() != nil else {
            throw RelayAPIError(status: 0, code: .badRequest, message: "The relay URL must start with https://.")
        }
        let pairing = try await RelayREST.pair(baseURL: url, code: code)
        await disconnect()
        try tokens.setToken(pairing.token)
        relayURL = url
        deviceName = pairing.device
        defaults.set(url, forKey: Keys.relayURL)
        defaults.set(pairing.device, forKey: Keys.deviceName)
        keychainError = nil
        connect(token: pairing.token)
    }

    /// Disconnects and forgets the token. The relay keeps the device until it is revoked there.
    func unpair() async throws {
        await disconnect()
        // The command log's cache holds command output from this relay.
        try? FileManager.default.removeItem(at: CommandLog.cacheURL(for: relayURL))
        try? FileManager.default.removeItem(at: Self.imagesURL(for: relayURL))
        deviceName = nil
        defaults.removeObject(forKey: Keys.deviceName)
        try tokens.deleteToken()
    }

    /// Sends a prompt (opening the session first); it waits in the session's outbox until the history has it.
    /// Returns the client_msg_id, or nil when not paired. During a run the relay answers `busy`: offer steer.
    @discardableResult
    func send(_ text: String, images: [ImageUpload] = [], to sessionID: String) async -> String? {
        guard let store else { return nil }
        await store.open(sessionID)
        return await store.sendPrompt(text, images: images, to: sessionID)
    }

    func approve(_ approval: PendingApproval, choice: ApprovalChoice) async throws {
        try await relay().send(.approve(runID: approval.runID, requestID: approval.id, choice: choice))
    }

    /// Kept in the conversation's outbox until the history has it (trismegistus-mac #54).
    func steer(runID: String, text: String, in sessionID: String) async throws {
        guard let store else { throw RelayClient.SendError.notConnected }
        try await store.sendSteer(text, runID: runID, in: sessionID)
    }

    func stop(runID: String) async throws {
        try await relay().send(.stop(runID: runID))
    }

    private func relay() throws -> RelayClient {
        guard let store else { throw RelayClient.SendError.notConnected }
        return store.client
    }

    private func connect(token: String) {
        let store = SessionStore(
            client: RelayClient(relayURL: relayURL, token: token),
            rest: RelayREST(baseURL: relayURL, token: token)
        )
        store.images = ImageFiles(directory: Self.imagesURL(for: relayURL), rest: store.rest)
        store.unseen = Self.loadUnseen(defaults)
        self.store = store
        let device = DeviceProfile(rest: store.rest)
        self.device = device
        let jobs = JobBoard(rest: store.rest, device: device)
        self.jobs = jobs
        github = GitHubModel(rest: store.rest, device: device)
        let agents = AgentBoard(rest: store.rest, device: device)
        self.agents = agents
        store.start()
        // The session list and the jobs are reloaded on every (re)connect.
        watch = Task { [weak self] in
            for await state in Observations({ store.connection }) {
                guard case .connected = state else { continue }
                Task { await device.refresh() }
                Task { await jobs.refresh() }
                Task { await agents.refresh() }
                do {
                    try await store.refreshSessions()
                    self?.sessionsError = nil
                    self?.listLoaded(store)
                    self?.loadAhead(store)
                } catch {
                    self?.sessionsError = (error as? RelayAPIError)?.message ?? "Can't reach the relay."
                }
            }
        }
        agentsWatch = Task {
            while !Task.isCancelled {
                if case .connected = store.connection { await agents.refresh() }
                try? await Task.sleep(for: .seconds(15))
            }
        }
        let defaults = defaults
        unseenWatch = Task {
            for await unseen in Observations({ store.unseen }) {
                defaults.set(try? JSONEncoder().encode(unseen), forKey: Keys.unseen)
            }
        }
    }

    private func disconnect() async {
        watch?.cancel()
        watch = nil
        agentsWatch?.cancel()
        agentsWatch = nil
        unseenWatch?.cancel()
        unseenWatch = nil
        tracking?.cancel()
        tracking = nil
        loadingAhead?.cancel()
        loadingAhead = nil
        await store?.stop()
        store = nil
        device = nil
        jobs = nil
        github = nil
        agents = nil
    }

    /// The chat's images from this relay, in the app's Caches.
    private static func imagesURL(for relay: URL) -> URL {
        URL.cachesDirectory.appending(path: "images-" + (relay.host() ?? "relay"))
    }

    private enum Keys {
        static let relayURL = "relayURL"
        static let deviceName = "deviceName"
        /// The run alerts' marks and `trackedUntil` (JSON), local to this Mac.
        static let unseen = "notifications.unseen"
    }
}
