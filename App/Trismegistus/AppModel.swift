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
    /// The News conversation (#19): the daily feed runs folded into one; a new one per connection.
    private(set) var news: NewsFeed?
    /// Hermes' cron jobs (#21) and this device's role, refreshed on each (re)connect.
    private(set) var jobs: JobBoard?
    /// The token couldn't be read at launch; shown on the pairing screen.
    private(set) var keychainError: String?
    /// The last session list refresh failed.
    private(set) var sessionsError: String?

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
        deviceName = nil
        defaults.removeObject(forKey: Keys.deviceName)
        try tokens.deleteToken()
    }

    /// Sends a prompt (opening the session first); it waits in the session's outbox until the history has it.
    /// Returns the client_msg_id, or nil when not paired. During a run the relay answers `busy`: offer steer.
    @discardableResult
    func send(_ text: String, to sessionID: String) async -> String? {
        guard let store else { return nil }
        await store.open(sessionID)
        return await store.sendPrompt(text, to: sessionID)
    }

    func approve(_ approval: PendingApproval, choice: ApprovalChoice) async throws {
        try await relay().send(.approve(runID: approval.runID, requestID: approval.id, choice: choice))
    }

    func steer(runID: String, text: String) async throws {
        try await relay().send(.steer(runID: runID, text: text))
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
        self.store = store
        news = NewsFeed(rest: store.rest)
        let jobs = JobBoard(rest: store.rest)
        self.jobs = jobs
        store.start()
        // The session list and the jobs are reloaded on every (re)connect.
        watch = Task { [weak self] in
            for await state in Observations({ store.connection }) {
                guard case .connected = state else { continue }
                Task { await jobs.refresh() }
                do {
                    try await store.refreshSessions()
                    self?.sessionsError = nil
                } catch {
                    self?.sessionsError = (error as? RelayAPIError)?.message ?? "Can't reach the relay."
                }
            }
        }
    }

    private func disconnect() async {
        watch?.cancel()
        watch = nil
        await store?.stop()
        store = nil
        news = nil
        jobs = nil
    }

    private enum Keys {
        static let relayURL = "relayURL"
        static let deviceName = "deviceName"
    }
}
