import Foundation
import Observation

/// The app's model: connection state, the session list with a live row for each, and every open session's state,
/// fed by RelayClient's outputs and REST history. Send approve/steer/stop through `client` directly; prompts go
/// through sendPrompt.
@MainActor @Observable
public final class SessionStore {
    /// The menu bar glyph. Failed and done (an unseen run end, #66) rank below running: disconnected, approval,
    /// running, failed, done, idle.
    public enum Activity: Sendable, Equatable {
        case disconnected, idle, running, approvalWaiting, failed, done

        /// This activity with the strongest unseen mark: it shows only while nothing stronger does.
        public func with(unseen: Unseen.Mark?) -> Activity {
            guard self == .idle, let unseen else { return self }
            return unseen == .failed ? .failed : .done
        }
    }

    public private(set) var connection: RelayClient.ConnectionState = .disconnected
    public private(set) var sessionList: [SessionInfo] = []
    /// Tags by session id, from the relay (they follow every device). May hold ids the list doesn't have.
    public private(set) var tags: [String: [String]] = [:]
    /// Handoff links, newer id → the older id it continues (`HandoffChain`). Empty from a relay without them.
    public private(set) var links: [String: String] = [:]
    /// Hermes' connected models; nil until loaded and from a relay without the endpoint (hide the picker then).
    public private(set) var models: ModelCatalog?
    /// The sessions with a model of their own; the others use `models.current`.
    public private(set) var sessionModels: [String: ModelChoice] = [:]
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
        return isWorking ? .running : Activity.idle.with(unseen: unseen.strongest)
    }

    /// Runs that ended unseen (#66). The app loads it at connect and keeps it across launches; Kit never persists it.
    public var unseen = Unseen()

    /// The mark of the thread whose newest part is `id`: the strongest among its parts.
    public func unseenMark(_ id: String) -> Unseen.Mark? {
        unseen.marks.isEmpty ? nil : unseen.mark([id] + olderParts(of: id))
    }

    public let client: RelayClient
    public let rest: RelayREST
    /// The chat's images on disk; uploads land here so the sender's own message shows without a download.
    @ObservationIgnored public var images: ImageFiles?
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
                // Resubscribed live only: the relay re-sends the status of a run that is still going (and its pending
                // approval), so forget what was live. A run that ended while the socket was down (a relay or gateway
                // restart) would otherwise stay "working" in the open chat forever: nothing would ever end it.
                for id in overview.keys where overview[id]?.lastSeq == 0 { overview[id]?.lostTrack() }
                for id in sessions.keys where sessions[id]?.lastSeq == 0 { sessions[id]?.lostTrack() }
            }
            connection = state
        case .message(let message):
            for id in sessions.keys { sessions[id]?.apply(message) }
            let at = now()
            for id in overview.keys { overview[id]?.apply(message, at: at) }
        }
        for (id, s) in sessions where (!s.historyLoaded || s.historyStale) && s.historyError == nil && !loading.contains(id) {
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

    /// Sends a prompt to an open session; it waits in the session's outbox until the history has it. Images not
    /// uploaded yet are uploaded first. One run per session: during a run the relay answers `busy` (offer to send it
    /// as a steer). Returns the client_msg_id.
    @discardableResult
    public func sendPrompt(_ text: String, images: [ImageUpload] = [], to sessionID: String) async -> String {
        let id = UUID().uuidString.lowercased()
        sessions[sessionID]?.outbox.append(OutgoingPrompt(id: id, text: text, status: .pending, images: images))
        func failed(_ code: ErrorCode?, _ message: String) {
            if let i = sessions[sessionID]?.outbox.firstIndex(where: { $0.id == id }) {
                sessions[sessionID]?.outbox[i].status = .failed(code: code, message: message)
            }
        }
        do {
            var ids: [String] = []
            for (n, image) in images.enumerated() {
                if let known = image.attachmentID {
                    ids.append(known)
                    continue
                }
                let ref = try await rest.uploadAttachment(image.data, mime: image.mime)
                await self.images?.store(image.data, for: ref)
                ids.append(ref.id)
                if let i = sessions[sessionID]?.outbox.firstIndex(where: { $0.id == id }) {
                    sessions[sessionID]?.outbox[i].images[n].attachmentID = ref.id
                }
            }
            try await client.send(.prompt(clientMsgID: id, sessionID: sessionID, text: text, attachments: ids))
        } catch let error as RelayAPIError {
            failed(error.code, error.message)
        } catch {
            failed(nil, "Not connected to the relay.")
        }
        return id
    }

    /// Steers `runID` with `text` and keeps it in the session's outbox until the history has it (steers are text
    /// only). Throws when the client can't send it (not connected): nothing is added then.
    @discardableResult
    public func sendSteer(_ text: String, runID: String, in sessionID: String) async throws -> String {
        try await client.send(.steer(runID: runID, text: text))
        let id = UUID().uuidString.lowercased()
        sessions[sessionID]?.steerSent(id: id, runID: runID, text: text)
        return id
    }

    /// A failed prompt again, in place of the old entry. Its images are uploaded again: the relay deletes uploads no
    /// prompt used within an hour, and the same bytes answer the same id. Nil when it isn't a failed prompt.
    @discardableResult
    public func retryPrompt(_ promptID: String, in sessionID: String) async -> String? {
        guard let i = sessions[sessionID]?.outbox.firstIndex(where: { $0.id == promptID }),
            let prompt = sessions[sessionID]?.outbox[i], case .failed = prompt.status
        else { return nil }
        sessions[sessionID]?.outbox.remove(at: i)
        let images = prompt.images.map { image in
            var image = image
            image.attachmentID = nil
            return image
        }
        return await sendPrompt(prompt.text, images: images, to: sessionID)
    }

    /// Also adds and drops subscriptions to match the list.
    public func refreshSessions() async throws {
        sessionList = try await rest.listSessions()
        await follow()
        await refreshTags()
        await refreshLinksAndModels()
    }

    /// Keeps the tags it has when the relay can't be reached; a relay without the endpoint has none.
    public func refreshTags() async {
        if let fresh = try? await rest.tags() { tags = fresh }
    }

    /// Like refreshTags: what the relay can't answer stays as it was; a relay without the endpoints has none.
    public func refreshLinksAndModels() async {
        if let fresh = try? await rest.links() { links = fresh }
        if let fresh = try? await rest.models() { models = fresh }
        if let fresh = try? await rest.sessionModels() { sessionModels = fresh }
    }

    /// The model the session's next run uses: its own choice, else the relay's current one.
    public func model(for id: String) -> ModelChoice? {
        sessionModels[id] ?? models?.current
    }

    /// Optimistic like renameSession; keeps what the relay stored.
    public func setModel(_ id: String, _ choice: ModelChoice) async throws {
        let old = sessionModels[id]
        sessionModels[id] = choice
        do {
            sessionModels[id] = try await rest.setModel(id, choice)
        } catch {
            if sessionModels[id] == choice { sessionModels[id] = old }
            throw error
        }
    }

    /// Records that `id` continues `from` (nil drops the link); the lists show the thread at once.
    public func setContinues(_ id: String, from: String?) async throws {
        let stored = try await rest.setContinues(id, from: from)
        links[id] = stored
    }

    @discardableResult
    public func createSession() async throws -> SessionInfo {
        let session = try await rest.createSession()
        sessionList.insert(session, at: 0)
        await follow()
        return session
    }

    /// The row shows the new title at once; it goes back, and the error is thrown, if the relay refuses.
    public func renameSession(_ id: String, to title: String) async throws {
        let old = sessionList.first { $0.id == id }?.title
        update(id) { $0.title = title }
        do {
            let session = try await rest.renameSession(id, title: title)
            update(id) { $0.title = session.title ?? title }
        } catch {
            update(id, ifTitle: title) { $0.title = old }
            throw error
        }
    }

    /// Optimistic like renameSession.
    public func setPinned(_ id: String, _ pinned: Bool) async throws {
        let old = sessionList.first { $0.id == id }?.pinned
        update(id) { $0.pinned = pinned }
        do {
            _ = try await rest.setPinned(id, pinned)
        } catch {
            update(id) { $0.pinned = old }
            throw error
        }
    }

    /// Replaces the session's tags with the validated set (`TagRules` throws before anything changes). Optimistic
    /// like renameSession; keeps what the relay stored.
    public func setTags(_ id: String, _ new: [String]) async throws {
        let new = try TagRules.normalize(new)
        let old = tags[id]
        tags[id] = new
        do {
            tags[id] = try await rest.setTags(id, new)
        } catch {
            if tags[id] == new { tags[id] = old } // not if a refresh already replaced it
            throw error
        }
    }

    public func deleteSession(_ id: String) async throws {
        try await rest.deleteSession(id)
        sessionList.removeAll { $0.id == id }
        tags[id] = nil
        sessionModels[id] = nil
        links = links.filter { $0.key != id && $0.value != id } // the relay drops both sides
        sessions[id] = nil
        await follow()
    }

    /// One line for the UI: the relay's own message, or why the Mac could not ask.
    public static func message(for error: any Error) -> String {
        if let error = error as? RelayAPIError { return error.message }
        if let error = error as? TagRules.Violation { return error.message }
        return "Can't reach the relay."
    }

    private func update(_ id: String, ifTitle title: String? = nil, _ change: (inout SessionInfo) -> Void) {
        guard let i = sessionList.firstIndex(where: { $0.id == id }) else { return }
        if let title, sessionList[i].title != title { return } // a refresh already replaced it
        change(&sessionList[i])
        overview[id]?.info = sessionList[i]
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
