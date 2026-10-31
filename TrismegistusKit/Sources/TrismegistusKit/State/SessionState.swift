import Foundation

public struct ActiveRun: Sendable, Equatable {
    public var id: String
    public var status: RunStatus
}

public struct PendingApproval: Sendable, Equatable, Identifiable {
    public var sessionID: String
    public var runID: String
    public var request: ApprovalRequest
    public var id: String { request.requestID }
}

/// A prompt the app sent, shown until the history has it.
public struct OutgoingPrompt: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        case pending
        case sent(runID: String)
        /// code is nil when it never reached the relay.
        case failed(code: ErrorCode?, message: String)
    }

    /// The prompt's client_msg_id.
    public var id: String
    public var text: String
    public var status: Status
}

/// One open session: REST history plus the live events the history doesn't have yet. A pure value; SessionStore
/// feeds it, and the rules (dedupe, trismegistus #10 and #11) are tested on it directly.
public struct SessionState: Sendable, Equatable {
    public let id: String
    public var history: [HistoryMessage] = []
    /// False until the history arrives, and again when it must be reloaded (replay_gap, a reconnect that couldn't
    /// resume from a seq). SessionStore reloads it.
    public var historyLoaded = false
    public var historyError: String?
    /// Live events, oldest first. Events of finished runs leave when the history arrives (it has them).
    public var events: [Event] = []
    /// Highest seq applied; 0 before the first event and after a replay_gap.
    public var lastSeq = 0
    public var run: ActiveRun?
    public var approvals: [PendingApproval] = []
    public var outbox: [OutgoingPrompt] = []

    public static let maxEvents = 1000

    public init(id: String) { self.id = id }

    public mutating func apply(_ message: ServerMessage) {
        switch message {
        case .event(let e) where e.sessionID == id:
            apply(e)
        case .run(let runID, let sessionID, let status) where sessionID == id:
            if status.isTerminal { end(runID) } else { run = ActiveRun(id: runID, status: status) }
        case .ack(let clientMsgID, let runID, let replayed):
            guard let i = outbox.firstIndex(where: { $0.id == clientMsgID }) else { return }
            outbox[i].status = .sent(runID: runID)
            // A replayed ack may name a run that already ended; the relay sends `run` for live ones.
            if !replayed && run?.id != runID { run = ActiveRun(id: runID, status: .running) }
        case .error(.replayGap, _, let ref?) where ref == id:
            // trismegistus #10: the relay no longer has the events after our seq (pruned, or its database was
            // reset and seqs start again at 1). Forget the seq so new events aren't dropped as repeats, and reload.
            lastSeq = 0
            historyLoaded = false
        case .error(let code, let message, let ref?):
            if let i = outbox.firstIndex(where: { $0.id == ref && $0.status == .pending }) {
                outbox[i].status = .failed(code: code, message: message)
            }
        default:
            break
        }
    }

    mutating func apply(_ e: Event) {
        // The relay sends a session's events in seq order (replay, then live): at or below lastSeq is a repeat.
        guard e.seq > lastSeq else { return }
        lastSeq = e.seq
        events.append(e)
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
        switch e.payload {
        case .approvalRequested(let request):
            if !approvals.contains(where: { $0.id == request.requestID }) {
                approvals.append(PendingApproval(sessionID: id, runID: e.runID, request: request))
            }
            run = ActiveRun(id: e.runID, status: .waitingForApproval)
        case .approvalResolved(let resolved):
            approvals.removeAll { $0.id == resolved.requestID }
            if run?.id == e.runID { run?.status = .running }
        case .runCompleted, .runFailed, .runCancelled:
            end(e.runID)
        case .toolStarted, .toolCompleted, .subagentStarted, .subagentCompleted, .steerQueued:
            if run?.id != e.runID { run = ActiveRun(id: e.runID, status: .running) }
        case .answer, .reconnected, .unknown:
            break
        }
    }

    private mutating func end(_ runID: String) {
        if run?.id == runID { run = nil }
        approvals.removeAll { $0.runID == runID }
    }

    /// trismegistus #11: history that arrives after live events already holds every finished turn. Keep only the
    /// live events of the run still going and the prompts the relay hasn't acknowledged, so nothing shows twice.
    public mutating func applyHistory(_ messages: [HistoryMessage]) {
        history = messages
        historyLoaded = true
        historyError = nil
        events.removeAll { $0.runID != run?.id }
        outbox.removeAll { if case .sent = $0.status { true } else { false } }
    }
}
