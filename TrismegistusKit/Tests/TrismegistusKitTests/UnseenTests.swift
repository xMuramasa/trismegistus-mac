import Foundation
import Testing
@testable import TrismegistusKit

@Suite struct UnseenTests {
    private let launch = Date(timeIntervalSince1970: 1_792_800_000)

    // #expect can't take a mutating call.
    private func end(_ u: inout Unseen, session: String, status: RunStatus, watched: Bool) -> Unseen.Mark? {
        u.runEnded(session: session, status: status, watched: watched)
    }

    private func allow(_ gate: inout SoundGate, approval: Bool, at now: Date) -> Bool {
        gate.allows(approval: approval, at: now)
    }

    @Test func aFinishedRunMarksDoneAndAFailedOneFailed() {
        var u = Unseen()
        #expect(end(&u, session: "a", status: .completed, watched: false) == .done)
        #expect(end(&u, session: "b", status: .failed, watched: false) == .failed)
        #expect(u.marks == ["a": .done, "b": .failed])
        #expect(u.strongest == .failed)
    }

    @Test func aCancelledOrWatchedRunLeavesNothing() {
        var u = Unseen()
        #expect(end(&u, session: "a", status: .cancelled, watched: false) == nil)
        #expect(end(&u, session: "a", status: .completed, watched: true) == nil)
        #expect(end(&u, session: "a", status: .failed, watched: true) == nil)
        #expect(end(&u, session: "a", status: .running, watched: false) == nil)
        #expect(u.marks.isEmpty && u.strongest == nil)
    }

    @Test func failedStaysAfterALaterSuccess() {
        var u = Unseen()
        u.runEnded(session: "a", status: .failed, watched: false)
        #expect(end(&u, session: "a", status: .completed, watched: false) == .done, "the finished sound still plays")
        #expect(u.marks["a"] == .failed)
        u.runEnded(session: "b", status: .completed, watched: false)
        u.runEnded(session: "b", status: .failed, watched: false)
        #expect(u.marks["b"] == .failed)
    }

    @Test func viewingClearsTheWholeThread() {
        var u = Unseen()
        u.runEnded(session: "new", status: .completed, watched: false)
        u.runEnded(session: "old", status: .failed, watched: false)
        u.runEnded(session: "other", status: .completed, watched: false)
        #expect(u.mark(["new", "old"]) == .failed)
        u.viewed(["new", "old"])
        #expect(u.marks == ["other": .done])
        #expect(u.mark(["new", "old"]) == nil)
    }

    @Test func theFirstLaunchMarksNothing() {
        var u = Unseen()
        u.catchUp([SessionInfo(id: "a", source: "api_server", lastActive: launch.timeIntervalSince1970 + 100)])
        #expect(u.marks.isEmpty && u.trackedUntil == nil)
        u.tracked(at: launch)
        #expect(u.trackedUntil == launch)
    }

    @Test func catchUpMarksAppConversationsThatChangedWhileQuit() {
        var u = Unseen()
        u.tracked(at: launch)
        u.runEnded(session: "failed", status: .failed, watched: false)
        let t = launch.timeIntervalSince1970
        u.catchUp([
            SessionInfo(id: "changed", source: "api_server", lastActive: t + 60),
            SessionInfo(id: "slack", source: "api_server", lastActive: t + Unseen.catchUpSlack),
            SessionInfo(id: "before", source: "api_server", lastActive: t - 60),
            SessionInfo(id: "never", source: "api_server"),
            SessionInfo(id: "telegram", source: "telegram", lastActive: t + 60),
            SessionInfo(id: "cron", source: "cron", lastActive: t + 60),
            SessionInfo(id: "watched", source: "api_server", lastActive: t + 60),
            SessionInfo(id: "failed", source: "api_server", lastActive: t + 60),
        ], watched: ["watched"])
        #expect(u.marks == ["changed": .done, "failed": .failed])
    }

    @Test func catchUpLeavesARunningConversation() {
        var u = Unseen()
        u.tracked(at: launch)
        let t = launch.timeIntervalSince1970
        u.catchUp([
            SessionInfo(id: "running", source: "api_server", lastActive: t + 60),
            SessionInfo(id: "ended", source: "api_server", lastActive: t + 60),
        ], running: ["running"])
        #expect(u.marks == ["ended": .done])
    }

    @Test func aGapAfterTheLaunchIsLostTrack() {
        var u = Unseen()
        #expect(!u.lostTrack(at: launch))
        u.tracked(at: launch)
        #expect(!u.lostTrack(at: launch.addingTimeInterval(30)))
        #expect(!u.lostTrack(at: launch.addingTimeInterval(Unseen.gap)))
        #expect(u.lostTrack(at: launch.addingTimeInterval(Unseen.gap + 1)))
    }

    @Test func pruneDropsConversationsThatLeft() {
        var u = Unseen()
        u.runEnded(session: "a", status: .completed, watched: false)
        u.runEnded(session: "b", status: .failed, watched: false)
        u.prune(keeping: ["a", "c"])
        #expect(u.marks == ["a": .done])
    }

    @Test func itSurvivesARestart() throws {
        var u = Unseen()
        u.runEnded(session: "a", status: .completed, watched: false)
        u.runEnded(session: "b", status: .failed, watched: false)
        u.tracked(at: launch)
        let back = try JSONDecoder().decode(Unseen.self, from: JSONEncoder().encode(u))
        #expect(back == u)
    }

    @Test func runSoundsAreTwoSecondsApartAndApprovalsAlwaysPlay() {
        var gate = SoundGate()
        #expect(allow(&gate, approval: false, at: launch))
        #expect(!allow(&gate, approval: false, at: launch), "two ends at once give one sound")
        #expect(allow(&gate, approval: true, at: launch.addingTimeInterval(0.5)))
        #expect(!allow(&gate, approval: false, at: launch.addingTimeInterval(1.9)))
        #expect(allow(&gate, approval: false, at: launch.addingTimeInterval(2)))
        #expect(allow(&gate, approval: true, at: launch.addingTimeInterval(2.1)))
        #expect(!allow(&gate, approval: false, at: launch.addingTimeInterval(3)), "a dropped sound doesn't hold the gate longer")
        #expect(allow(&gate, approval: false, at: launch.addingTimeInterval(4)))
    }

    @Test func theStrongestStateWins() {
        typealias A = ConversationKind.Attention
        #expect(A(isWaitingForApproval: true, isRunning: true, unseen: .failed) == .approval)
        #expect(A(isWaitingForApproval: false, isRunning: true, unseen: .failed) == .running)
        #expect(A(isWaitingForApproval: false, isRunning: false, unseen: .failed) == .failed)
        #expect(A(isWaitingForApproval: false, isRunning: false, unseen: .done) == .done)
        #expect(A.approval > A.running && A.running > A.failed && A.failed > A.done)
        #expect(ConversationKind.Summary([("api_server", .done), ("api_server", .failed), ("telegram", .done)])[.app].attention == .failed)
        #expect(ConversationKind.Summary([("oneshot", .done), ("cron", .failed)]).moreAttention == .failed)
    }

    @Test func doneAndFailedStayOutOfInProgress() {
        let items: [(String, ConversationKind.Attention?)] = [("d", .done), ("r", .running), ("f", .failed), ("q", nil)]
        let g = SessionListing.groups(items, attention: \.1) { $0.0 == "f" }
        #expect(g.inProgress.map(\.0) == ["r"])
        #expect(g.pinned.map(\.0) == ["f"])
        #expect(g.rest.map(\.0) == ["d", "q"])
    }

    @Test func theGlyphShowsAnUnseenMarkOnlyWhenIdle() {
        typealias A = SessionStore.Activity
        #expect(A.idle.with(unseen: .done) == .done)
        #expect(A.idle.with(unseen: .failed) == .failed)
        #expect(A.idle.with(unseen: nil) == .idle)
        #expect(A.running.with(unseen: .failed) == .running)
        #expect(A.approvalWaiting.with(unseen: .done) == .approvalWaiting)
        #expect(A.disconnected.with(unseen: .failed) == .disconnected)
    }
}
