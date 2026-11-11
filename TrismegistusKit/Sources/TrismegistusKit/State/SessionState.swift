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

/// A prompt the app sent, shown until the history has it. A steer (`isSteer`) is `.sent` from the start (the relay
/// doesn't acknowledge steers) and stays until the history has its text or its run ends; `afterSeq` is the session's
/// seq when it was sent, so the chat places it among the run's events.
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
    /// Its images, with the bytes kept so a retry can upload them again.
    public var images: [ImageUpload] = []
    public var isSteer = false
    public var afterSeq = 0
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
    /// The first line of the newest thought Hermes stored during the current run (#74); nil after it ends.
    public var thought: String?
    public var approvals: [PendingApproval] = []
    public var outbox: [OutgoingPrompt] = []
    /// The history misses something: a run just finished, or (with a relay older than trismegistus#30, which sends no
    /// `user.message`) a run this device didn't start began (#54). SessionStore reloads it, keeping the chat on screen
    /// meanwhile (unlike `historyLoaded` false).
    public var historyStale = false
    /// The run this device didn't start whose first event was checked: `user.message`, or else a reload once.
    public var rechecked: String?

    public static let maxEvents = 1000

    public init(id: String) { self.id = id }

    /// This device's prompt started `runID` (its ack named it).
    public func isOwnRun(_ runID: String) -> Bool {
        outbox.contains { !$0.isSteer && $0.status == .sent(runID: runID) }
    }

    /// A steer sent into the running turn: shown at once, until the history has it.
    public mutating func steerSent(id: String, runID: String, text: String) {
        outbox.append(OutgoingPrompt(id: id, text: text, status: .sent(runID: runID), isSteer: true, afterSeq: lastSeq))
    }

    public mutating func apply(_ message: ServerMessage) {
        switch message {
        case .event(let e) where e.sessionID == id:
            apply(e)
        case .run(let runID, let sessionID, let status) where sessionID == id:
            if status.isTerminal {
                end(runID)
            } else {
                // Another device's prompt arrives as the run's first event (user.message); see apply(_ e:).
                run = ActiveRun(id: runID, status: status)
            }
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
            return
        case .toolStarted, .toolCompleted, .subagentStarted, .subagentCompleted, .steerQueued:
            if run?.id != e.runID { run = ActiveRun(id: e.runID, status: .running) }
        case .userMessage(let m):
            if run?.id != e.runID { run = ActiveRun(id: e.runID, status: .running) }
            // Our own steer, back from the relay at its place in the run: the event shows it from now on.
            if m.kind == .steer,
                let i = outbox.firstIndex(where: { $0.isSteer && $0.text == m.text && $0.status == .sent(runID: e.runID) })
            {
                outbox.remove(at: i)
            }
            rechecked = e.runID // the prompt itself came: no reload needed
            return
        case .answer, .reconnected, .unknown:
            break
        }
        // The first event of a run this device didn't start, when it isn't user.message (an older relay), asks for the
        // history: it has the prompt by then (Hermes stores it a few ms after the run starts).
        if rechecked != e.runID && !isOwnRun(e.runID) {
            rechecked = e.runID
            historyStale = true
        }
    }

    /// Subscribed again without a seq: what was live may be over. The relay re-sends the status of a run that is still
    /// going, with its pending approval, right after the subscription; the outbox stays.
    mutating func lostTrack() {
        run = nil
        thought = nil
        approvals = []
    }

    /// A run ended: the history has the finished turn (and any prompt or steer this device didn't see).
    private mutating func end(_ runID: String) {
        if run?.id == runID {
            run = nil
            thought = nil
        }
        approvals.removeAll { $0.runID == runID }
        historyStale = true
    }

    /// trismegistus #11: history that arrives after live events already holds every finished turn. Keep only the
    /// live events of the run still going and the prompts the relay hasn't acknowledged, so nothing shows twice.
    public mutating func applyHistory(_ messages: [HistoryMessage]) {
        history = messages
        historyLoaded = true
        historyError = nil
        historyStale = false
        events.removeAll { $0.runID != run?.id }
        let steers = Set(messages.filter(\.isSteer).map { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) })
        let running = run?.id
        outbox.removeAll { p in
            guard case .sent(let runID) = p.status else { return false }
            // A steer is stored when Hermes takes it (its next step), not when sent: keep it until then.
            guard p.isSteer else { return true }
            return runID != running || steers.contains(p.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
