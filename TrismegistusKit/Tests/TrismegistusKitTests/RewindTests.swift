import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

/// Retry and edit (#75): a prompt with `rewind_to` hides what it replaces until its run's history arrives.
@Suite struct RewindTimelineTests {
    /// Three turns; the second user message carries an image.
    static let turns = history(#"""
    [{"id":1,"role":"user","content":"First"},
     {"id":2,"role":"assistant","content":"One."},
     {"id":3,"role":"user","content":"Second\n\n[screenshot]","attachments":[{"id":"\#(imageID)","mime":"image/png","width":1280,"height":800}]},
     {"id":4,"role":"assistant","content":"Two."},
     {"id":5,"role":"user","content":"Third"},
     {"id":6,"role":"assistant","content":"Three."}]
    """#)

    func state(_ outbox: [OutgoingPrompt]) -> SessionState {
        var s = SessionState(id: "s1")
        s.applyHistory(Self.turns)
        s.outbox = outbox
        return s
    }

    @Test func aRewindHidesTheMessageAndWhatFollowsUntilItsHistory() {
        let edit = OutgoingPrompt(id: "c1", text: "Second, again", status: .pending, rewindTo: 3)
        var s = state([edit])
        #expect(ChatTimeline.items(s, compact: false).map(\.id) == ["h-1", "h-2", "o-c1"])
        // Acked: the new run's events show, the rewound ones stay hidden.
        s.apply(.ack(clientMsgID: "c1", runID: "run_2", replayed: false))
        s.apply(.event(event("s1", 1, run: "run_2", .answer(Answer(text: "Two, again.")))))
        #expect(ChatTimeline.items(s, compact: false).map(\.id) == ["h-1", "h-2", "o-c1", "e-1"])
        // The run's history replaces it all.
        s.apply(.event(event("s1", 2, run: "run_2", .runCompleted)))
        s.applyHistory(Array(Self.turns.prefix(2)) + history(#"[{"id":7,"role":"user","content":"Second, again"},{"id":8,"role":"assistant","content":"Two, again."}]"#))
        #expect(ChatTimeline.items(s, compact: false).map(\.id) == ["h-1", "h-2", "h-7", "h-8"])
    }

    @Test func aFailedRewindBringsEverythingBackAndAsksForTheHistory() {
        var s = state([OutgoingPrompt(id: "c1", text: "Second, again", status: .pending, rewindTo: 3)])
        s.apply(.error(code: .hermesError, message: "the rewind failed", ref: "c1"))
        #expect(s.outbox.first?.isFailed == true)
        #expect(s.historyStale) // the relay may have rewound before the run failed to start
        #expect(ChatTimeline.items(s, compact: false).map(\.id) == ["h-1", "h-2", "h-3", "h-4", "h-5", "h-6", "o-c1"])
    }

    @Test func aPlainPromptsErrorDoesntReloadTheHistory() {
        var s = state([OutgoingPrompt(id: "c1", text: "hi", status: .pending)])
        s.apply(.error(code: .busy, message: "busy", ref: "c1"))
        #expect(!s.historyStale)
    }

    @Test func rewindableMessagesRetryAndWhatAnEditRemoves() {
        let items = ChatTimeline.items(state([]), compact: false)
        let second = ChatTimeline.rewindable(items[2])
        #expect(second == ChatTimeline.Rewindable(itemID: "h-3", hermesID: 3, text: "Second", attachments: [imageRef]))
        #expect(ChatTimeline.rewindable(items[1]) == nil) // an answer
        #expect(ChatTimeline.rewindable(.user(id: "e-4", text: "live", time: nil)) == nil)
        #expect(ChatTimeline.rewindable(.user(id: "h-9", text: "steer", time: nil, steer: true)) == nil)

        // A failed edit back in the editor, its images by id; and back to what sendPrompt takes.
        let failed = OutgoingPrompt(id: "c1", text: "Second", status: .failed(code: .busy, message: "busy"), images: second!.uploads, rewindTo: 3)
        #expect(ChatTimeline.Rewindable(failed: failed) == second)
        #expect(second!.uploads.map(\.attachmentID) == [imageID])
        #expect(ChatTimeline.Rewindable(failed: OutgoingPrompt(id: "c2", text: "x", status: .pending)) == nil)

        let retry = ChatTimeline.retry(items)
        #expect(retry?.message.hermesID == 5)
        #expect(retry?.answerID == "h-6")

        #expect(ChatTimeline.removed(after: "h-1", in: items) == (2, true))
        #expect(ChatTimeline.removed(after: "h-5", in: items) == (0, true))
        #expect(ChatTimeline.removed(after: "h-6", in: items) == (0, false))
    }

    /// A run that left no answer: Retry sits on the message. One still sending can't be retried.
    @Test func retryWithoutAnAnswerAndWhileSending() {
        var s = SessionState(id: "s1")
        s.applyHistory(Array(Self.turns.prefix(5)))
        let items = ChatTimeline.items(s, compact: false)
        #expect(ChatTimeline.retry(items)?.message.itemID == "h-5")
        #expect(ChatTimeline.retry(items)?.answerID == nil)
        s.outbox = [OutgoingPrompt(id: "c1", text: "more", status: .pending)]
        #expect(ChatTimeline.retry(ChatTimeline.items(s, compact: false)) == nil)
    }
}

/// The store sends `rewind_to` and reloads the history when a rewind's prompt fails.
@MainActor @Suite struct RewindStoreTests {
    let transport = FakeTransport()
    let http = FakeHTTP { r in
        r.url?.path == "/api/sessions/s1/messages" ? (200, #"{"data":[{"id":1,"role":"user","content":"First"}]}"#)
            : (404, #"{"error":{"code":"not_found","message":"not found"}}"#)
    }
    let store: SessionStore

    init() {
        let clock = TestClock()
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport, sleep: { try await clock.sleep(for: $0) })
        store = SessionStore(client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http))
    }

    func historyLoads() -> Int { http.requests.current.filter { $0.url?.path == "/api/sessions/s1/messages" }.count }

    @Test func sendsRewindToWithKeptImagesAndReloadsAfterAnError() async {
        await store.open("s1")
        store.start()
        let c = await transport.connection(0)
        _ = await c.sent(1)
        c.push(.ready(device: "macbook", serverVersion: "0.1.0"))
        _ = await c.sent(2)
        let kept = ImageUpload(data: Data(), mime: "image/png", width: 1280, height: 800, attachmentID: imageID)
        let id = await store.sendPrompt("First, again", images: [kept], to: "s1", rewindTo: 1)
        #expect(await c.sent(3).last == .prompt(clientMsgID: id, sessionID: "s1", text: "First, again", attachments: [imageID], rewindTo: 1))
        #expect(http.requests.current.allSatisfy { $0.httpMethod != "POST" }) // a kept image isn't uploaded again
        let before = historyLoads()
        await store.handle(.message(.error(code: .notFound, message: "not one of the session's user messages", ref: id)))
        #expect(store.sessions["s1"]?.outbox.first?.isFailed == true)
        #expect(historyLoads() == before + 1)
        // The outbox's Retry sends the same rewind again, the kept image by its id.
        let again = await store.retryPrompt(id, in: "s1")
        #expect(await c.sent(4).last == .prompt(clientMsgID: again!, sessionID: "s1", text: "First, again", attachments: [imageID], rewindTo: 1))
        await store.stop()
    }
}
