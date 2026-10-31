import Foundation
import Observation

/// The app's model: connection state, the session list, and every open session's state, fed by RelayClient's
/// outputs and REST history. Send approve/steer/stop through `client` directly; prompts go through sendPrompt.
@MainActor @Observable
public final class SessionStore {
    public private(set) var connection: RelayClient.ConnectionState = .disconnected
    public private(set) var sessionList: [SessionInfo] = []
    /// Open (subscribed) sessions by id.
    public private(set) var sessions: [String: SessionState] = [:]

    public var pendingApprovals: [PendingApproval] { sessions.values.flatMap(\.approvals) }
    public var isWorking: Bool { sessions.values.contains { $0.run != nil } }

    public let client: RelayClient
    public let rest: RelayREST
    @ObservationIgnored private var feed: Task<Void, Never>?
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private var wasConnected = false

    public init(client: RelayClient, rest: RelayREST) {
        self.client = client
        self.rest = rest
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
            }
            connection = state
        case .message(let message):
            for id in sessions.keys { sessions[id]?.apply(message) }
        }
        for (id, s) in sessions where !s.historyLoaded && s.historyError == nil && !loading.contains(id) {
            await loadHistory(id)
        }
    }

    /// Subscribes to a session and loads its history.
    public func open(_ id: String) async {
        guard sessions[id] == nil else { return }
        sessions[id] = SessionState(id: id)
        await client.subscribe(id)
        await loadHistory(id)
    }

    public func close(_ id: String) async {
        sessions[id] = nil
        await client.unsubscribe(id)
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

    public func refreshSessions() async throws {
        sessionList = try await rest.listSessions()
    }

    @discardableResult
    public func createSession() async throws -> SessionInfo {
        let session = try await rest.createSession()
        sessionList.insert(session, at: 0)
        return session
    }

    public func renameSession(_ id: String, to title: String) async throws {
        let session = try await rest.renameSession(id, title: title)
        if let i = sessionList.firstIndex(where: { $0.id == id }) { sessionList[i].title = session.title ?? title }
    }

    public func deleteSession(_ id: String) async throws {
        try await rest.deleteSession(id)
        sessionList.removeAll { $0.id == id }
        if sessions[id] != nil { await close(id) }
    }
}
