import Foundation

/// One conversation's row in the session list and the window sidebar: what the relay says about it live, for every
/// followed session whether open or not. A pure value; SessionStore feeds it.
public struct SessionOverview: Sendable, Equatable, Identifiable {
    public struct Run: Sendable, Equatable {
        public var id: String
        public var status: RunStatus
        /// When the Mac first saw the run: its start, unless it was already going when the session was subscribed.
        public var startedAt: Date
        /// Tools started in this run since the Mac saw it.
        public var toolCount = 0
    }

    public let id: String
    /// From the REST list; nil for an open session the list doesn't have (yet).
    public var info: SessionInfo?
    public var run: Run?
    public var approvals: [PendingApproval] = []
    /// Highest seq applied; 0 before the first event and after the relay lost track (replay_gap, live resubscribe).
    public var lastSeq = 0
    /// The newest event's time.
    public var lastEventAt: Date?

    public init(id: String, info: SessionInfo? = nil) {
        self.id = id
        self.info = info
    }

    public var source: String? { info?.source }
    public var isReadOnly: Bool { info?.isReadOnly ?? false }
    public var pendingApproval: PendingApproval? { approvals.first }
    /// True also when the relay says a run waits but its request came before the Mac subscribed (no request id).
    public var isWaitingForApproval: Bool { !approvals.isEmpty || run?.status == .waitingForApproval }
    public var lastActivity: Date? {
        let listed = info?.lastActive.map { Date(timeIntervalSince1970: $0) }
        guard let listed, let lastEventAt else { return lastEventAt ?? listed }
        return max(listed, lastEventAt)
    }

    public mutating func apply(_ message: ServerMessage, at now: Date) {
        switch message {
        case .event(let e) where e.sessionID == id:
            apply(e)
        case .run(let runID, let sessionID, let status) where sessionID == id:
            if status.isTerminal {
                end(runID)
            } else {
                if run?.id != runID { run = Run(id: runID, status: status, startedAt: now) }
                run?.status = status
            }
        case .error(.replayGap, _, let ref?) where ref == id:
            lostTrack()
        default:
            break
        }
    }

    mutating func apply(_ e: Event) {
        guard e.seq > lastSeq else { return } // a repeat
        lastSeq = e.seq
        let at = Date(timeIntervalSince1970: Double(e.ts) / 1000)
        lastEventAt = max(lastEventAt ?? at, at)
        if e.payload.isTerminal { return end(e.runID) }
        if run?.id != e.runID {
            run = Run(id: e.runID, status: .running, startedAt: at)
        } else if let started = run?.startedAt, at < started {
            run?.startedAt = at // replayed events are older than the `run` message
        }
        switch e.payload {
        case .toolStarted:
            run?.toolCount += 1
        case .approvalRequested(let request):
            if !approvals.contains(where: { $0.id == request.requestID }) {
                approvals.append(PendingApproval(sessionID: id, runID: e.runID, request: request))
            }
            run?.status = .waitingForApproval
        case .approvalResolved(let resolved):
            approvals.removeAll { $0.id == resolved.requestID }
            if approvals.isEmpty { run?.status = .running }
        default:
            break
        }
    }

    /// The session was (re)subscribed without a seq: what was live may be over. The relay sends the active run's
    /// status again on subscribe.
    mutating func lostTrack() {
        lastSeq = 0
        run = nil
        approvals = []
    }

    private mutating func end(_ runID: String) {
        if run?.id == runID { run = nil }
        approvals.removeAll { $0.runID == runID }
    }
}
