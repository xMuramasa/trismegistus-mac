import Foundation
import Observation

/// The app's model: connection state, the session list with a live row for each, and every open session's state,
/// fed by RelayClient's outputs and REST history. Send approve/steer/stop through `client` directly; prompts go
/// through sendPrompt.
@MainActor @Observable
public final class SessionStore {
    /// The menu bar glyph.
    public enum Activity: Sendable, Equatable {
        case disconnected, idle, running, approvalWaiting
    }

    public private(set) var connection: RelayClient.ConnectionState = .disconnected
    public private(set) var sessionList: [SessionInfo] = []
    /// Open sessions by id.
    public private(set) var sessions: [String: SessionState] = [:]
    /// A row for every listed or open session. The open ones and the RelayClient.maxSubscriptions most recent are
    /// subscribed and kept live; the others only have their list info.
    public private(set) var overview: [String: SessionOverview] = [:]

    /// Every approval waiting in a followed session, open or not.
    public var pendingApprovals: [PendingApproval] {
        var seen = Set<String>()
        return (sessions.values.flatMap(\.approvals) + overview.values.flatMap(\.approvals)).filter { seen.insert($0.id).inserted }
    }
    /// A run is going in any followed session.
    public var isWorking: Bool { sessions.values.contains { $0.run != nil } || overview.values.contains { $0.run != nil } }

    public var activity: Activity {
        guard case .connected = connection else { return .disconnected }
        if !pendingApprovals.isEmpty || overview.values.contains(where: \.isWaitingForApproval) { return .approvalWaiting }
        return isWorking ? .running : .idle
    }

    public let client: RelayClient
    public let rest: RelayREST
    @ObservationIgnored private var feed: Task<Void, Never>?
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private var wasConnected = false
    @ObservationIgnored private let now: @Sendable () -> Date

    /// now is injectable so tests control run start times.
    public init(client: RelayClient, rest: RelayREST, now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.rest = rest
        self.now = now
    }

    public func start() {
        guard feed == nil else { return }
        let client = client
        feed = Task { [weak self] in
            await client.start()
            for await output in client.outputs {
                guard let self else { return }
                await self.handle(output)
            }
        }
    }

    public func stop() async {
        feed?.cancel()
        feed = nil
        await client.stop()
    }

    /// Applies one RelayClient output, then reloads the history of open sessions that lost track. Awaiting the
    /// reload here keeps the next live events behind it.
    public func handle(_ output: RelayClient.Output) async {
        switch output {
        case .state(let state):
            if case .connected = state {
                // After a drop, sessions with no seq yet were resubscribed live only: what happened meanwhile is
                // only in the history.
                if wasConnected {
                    for id in sessions.keys where sessions[id]?.lastSeq == 0 { sessions[id]?.historyLoaded = false }
                }
                wasConnected = true
                // Resubscribed live only: the relay re-sends the status of a run that is still going.
                for id in overview.keys where overview[id]?.lastSeq == 0 { overview[id]?.lostTrack() }
            }
            connection = state
        case .message(let message):
            for id in sessions.keys { sessions[id]?.apply(message) }
            let at = now()
            for id in overview.keys { overview[id]?.apply(message, at: at) }
        }
        for (id, s) in sessions where !s.historyLoaded && s.historyError == nil && !loading.contains(id) {
            await loadHistory(id)
        }
    }

    /// Subscribes to a session (unless its row already is) and loads its history.
    public func open(_ id: String) async {
        guard sessions[id] == nil else { return }
        var state = SessionState(id: id)
        // Already followed: the relay won't send the run's status again, so start from what the row knows.
        if let row = overview[id] {
            state.run = row.run.map { ActiveRun(id: $0.id, status: $0.status) }
            state.approvals = row.approvals
        }
        sessions[id] = state
        await follow()
        await loadHistory(id)
    }

    /// The session stays subscribed while it is among the listed ones followed.
    public func close(_ id: String) async {
        sessions[id] = nil
        await follow()
    }

    /// Also the retry after historyError.
    public func loadHistory(_ id: String) async {
        guard sessions[id] != nil, loading.insert(id).inserted else { return }
        defer { loading.remove(id) }
        do {
            let messages = try await rest.messages(id)
            sessions[id]?.applyHistory(messages)
        } catch {
            sessions[id]?.historyError = (error as? RelayAPIError)?.message ?? "Can't reach the relay."
        }
    }

    /// Sends a prompt to an open session; it waits in the session's outbox until the history has it. One run per
    /// session: during a run the relay answers `busy` (offer to send it as a steer). Returns the client_msg_id.
    @discardableResult
    public func sendPrompt(_ text: String, to sessionID: String) async -> String {
        let id = UUID().uuidString.lowercased()
        sessions[sessionID]?.outbox.append(OutgoingPrompt(id: id, text: text, status: .pending))
        do {
            try await client.send(.prompt(clientMsgID: id, sessionID: sessionID, text: text))
        } catch {
            if let i = sessions[sessionID]?.outbox.firstIndex(where: { $0.id == id }) {
                sessions[sessionID]?.outbox[i].status = .failed(code: nil, message: "Not connected to the relay.")
            }
        }
        return id
    }

    /// Also adds and drops subscriptions to match the list.
    public func refreshSessions() async throws {
        sessionList = try await rest.listSessions()
        await follow()
    }

    @discardableResult
    public func createSession() async throws -> SessionInfo {
        let session = try await rest.createSession()
        sessionList.insert(session, at: 0)
        await follow()
        return session
    }

    public func renameSession(_ id: String, to title: String) async throws {
        let session = try await rest.renameSession(id, title: title)
        if let i = sessionList.firstIndex(where: { $0.id == id }) {
            sessionList[i].title = session.title ?? title
            overview[id]?.info = sessionList[i]
        }
    }

    public func deleteSession(_ id: String) async throws {
        try await rest.deleteSession(id)
        sessionList.removeAll { $0.id == id }
        sessions[id] = nil
        await follow()
    }

    /// Follows the open sessions, then the listed ones most recent first (RelayClient keeps the first
    /// maxSubscriptions), and keeps a row for each.
    private func follow() async {
        let byRecency = sessionList.enumerated().sorted { a, b in
            let (x, y) = (a.element.lastActive ?? a.element.startedAt ?? 0, b.element.lastActive ?? b.element.startedAt ?? 0)
            return x != y ? x > y : a.offset < b.offset
        }
        let info = Dictionary(sessionList.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let ids = (sessions.keys.sorted() + byRecency.map(\.element.id)).filter { seen.insert($0).inserted }
        overview = Dictionary(uniqueKeysWithValues: ids.enumerated().map { i, id in
            var row = overview[id] ?? SessionOverview(id: id)
            row.info = info[id]
            if i >= RelayClient.maxSubscriptions { row.lostTrack() } // not subscribed: nothing live to show
            return (id, row)
        })
        await client.follow(ids)
    }
}
