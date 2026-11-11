import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

@Suite struct SessionCapabilitiesTests {
    @Test func everySourceCanPinRenameAndTag() {
        for source in ["api_server", "cron", "cli", "telegram", "discord", nil] {
            let c = SessionCapabilities(source: source)
            #expect(c.canPin && c.canRename && c.canTag)
        }
    }

    @Test func onlyApiServerCronAndCliCanBeDeleted() {
        #expect(["api_server", "cron", "cli"].allSatisfy { SessionCapabilities(source: $0).canDelete })
        #expect(["telegram", "discord", "slack", "", nil].allSatisfy { !SessionCapabilities(source: $0).canDelete })
        // Hand off follows delete: never for a live messaging chat.
        #expect(["api_server", "cron", "cli"].allSatisfy { SessionCapabilities(source: $0).canHandOff })
        #expect(["telegram", "discord", "", nil].allSatisfy { !SessionCapabilities(source: $0).canHandOff })
    }

    @Test func aCronSessionIsReadOnlyEvenWhenUnlisted() {
        let run = "cron_8f3a1c_20261030_090000"
        #expect(SessionInfo.isReadOnly(id: run, info: nil))
        #expect(SessionInfo.isReadOnly(id: run, info: SessionInfo(id: run, source: "cron")))
        // Other unlisted ids stay writable; a listed non-api_server session is read-only; an api_server one is writable.
        #expect(!SessionInfo.isReadOnly(id: "api_1", info: nil))
        #expect(SessionInfo.isReadOnly(id: "tg_1", info: SessionInfo(id: "tg_1", source: "telegram")))
        #expect(!SessionInfo.isReadOnly(id: "api_1", info: SessionInfo(id: "api_1", source: "api_server")))
    }
}

@Suite struct TagRulesTests {
    @Test func trimsAndKeepsTheFirstSpelling() throws {
        #expect(try TagRules.normalize(["  Work ", "work", "Home", "WORK"]) == ["Work", "Home"])
        #expect(try TagRules.normalize([]) == [])
    }

    @Test func lengthIsCountedInCharactersAfterTrimming() throws {
        #expect(try TagRules.validate(String(repeating: "a", count: 32) + "  ").count == 32)
        #expect(throws: TagRules.Violation.tooLong) { try TagRules.validate(String(repeating: "a", count: 33)) }
        #expect(throws: TagRules.Violation.empty) { try TagRules.validate("   ") }
        #expect(throws: TagRules.Violation.controlCharacters) { try TagRules.validate("a\tb") }
    }

    @Test func atMostTenTagsCountingDistinctOnes() throws {
        let ten = (1...10).map { "t\($0)" }
        #expect(try TagRules.normalize(ten).count == 10)
        #expect(try TagRules.adding("T3", to: ten) == ten) // already there: no eleventh
        #expect(throws: TagRules.Violation.tooMany) { try TagRules.adding("t11", to: ten) }
    }

    @Test func removingIsCaseInsensitive() {
        #expect(TagRules.removing("WORK", from: ["Work", "Home"]) == ["Home"])
    }
}

@Suite struct SessionListingTests {
    @Test func pinnedGoApartEachGroupKeepingItsOrder() {
        let items = [("a", false), ("b", true), ("c", false), ("d", true)]
        let listing = SessionListing.pinnedApart(items, isPinned: \.1)
        #expect(listing.pinned.map(\.0) == ["b", "d"])
        #expect(listing.rest.map(\.0) == ["a", "c"])
    }

    /// Live ones leave Pinned and the rest for In progress, approvals before runs, each group keeping the order (#72).
    @Test func liveOnesGoToInProgressApprovalFirst() {
        // (id, pinned, attention), most recent first.
        let items: [(String, Bool, ConversationKind.Attention?)] = [
            ("run1", false, .running), ("quiet", false, nil), ("pinRun", true, .running), ("ask1", false, .approval),
            ("pin", true, nil), ("pinAsk", true, .approval), ("old", false, nil),
        ]
        let groups = SessionListing.groups(items, attention: \.2, isPinned: \.1)
        #expect(groups.inProgress.map(\.0) == ["ask1", "pinAsk", "run1", "pinRun"])
        #expect(groups.pinned.map(\.0) == ["pin"])
        #expect(groups.rest.map(\.0) == ["quiet", "old"])
    }

    @Test func nothingLiveMeansNoInProgress() {
        let items: [(String, Bool)] = [("a", false), ("b", true), ("c", false)]
        let groups = SessionListing.groups(items, attention: { _ in nil }, isPinned: \.1)
        #expect(groups.inProgress.isEmpty)
        #expect(groups.pinned.map(\.0) == ["b"])
        #expect(groups.rest.map(\.0) == ["a", "c"])
    }

    /// The daily feed runs are ordinary cron conversations (#57): each keeps its row, in the Cron tab.
    @Test func feedRunsAreListedLikeAnyCronRun() {
        let items = [("a", "api_server"), ("cron_news_1", "cron"), ("b", "telegram"), ("cron_news_2", "cron")]
        #expect(SessionListing.pinnedApart(items) { _ in false }.rest.map(\.0) == items.map(\.0))
        #expect(items.filter { ConversationKind.cron.includes($0.1) }.map(\.0) == ["cron_news_1", "cron_news_2"])
    }

    @Test func selectionMovesToTheNextConversationWhenItsOwnLeaves() {
        let old = ["a", "b", "c"]
        #expect(SessionListing.selection("b", from: old, to: ["a", "c"]) == "c")
        #expect(SessionListing.selection("c", from: old, to: ["a", "b"]) == "b")
        #expect(SessionListing.selection("a", from: ["a"], to: []) == nil)
        #expect(SessionListing.selection("b", from: old, to: ["c", "b", "a"]) == "b") // reordered, not removed
        #expect(SessionListing.selection("x", from: old, to: ["a"]) == "x") // not in the list (Commands)
        #expect(SessionListing.selection(nil, from: old, to: []) == nil)
    }

    @Test func tagCountsOnlyCountListedSessionsAndMergeCase() {
        let tags = ["a": ["Work", "x"], "b": ["work"], "c": ["y"], "gone": ["Work", "x", "z"]]
        let counts = SessionListing.tagCounts(ids: ["a", "b", "c"], tags: tags)
        #expect(counts.map(\.tag) == ["Work", "x", "y"])
        #expect(counts.map(\.count) == [2, 1, 1])
    }
}

@Suite struct SessionManagementRESTTests {
    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: URL(string: "https://relay.invalid/")!, token: fakeToken, http: http), http)
    }

    func body(_ r: URLRequest) -> JSONValue? { r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) } }

    @Test func decodesPinned() throws {
        let pinned = try Wire.decode(SessionInfo.self, from: Data(#"{"id":"a","pinned":true}"#.utf8))
        let absent = try Wire.decode(SessionInfo.self, from: Data(#"{"id":"b"}"#.utf8))
        #expect(pinned.isPinned && !absent.isPinned)
    }

    @Test func setPinnedPatchesOnlyPinned() async throws {
        let (api, http) = rest { _ in (200, #"{"session":{"id":"cli_1","source":"cli","pinned":true}}"#) }
        #expect(try await api.setPinned("cli_1", true).isPinned)
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "PATCH" && r.url?.path == "/api/sessions/cli_1")
        #expect(body(r) == .object(["pinned": .bool(true)]))
    }

    @Test func tagsListAndAMissingEndpointIsNoTags() async throws {
        let (api, http) = rest { _ in (200, #"{"sessions":{"a":["x","y"],"b":[]}}"#) }
        #expect(try await api.tags() == ["a": ["x", "y"], "b": []])
        #expect(http.requests.current.first?.url?.path == "/api/tags")
        let (old, _) = rest { _ in (404, #"{"error":{"code":"not_found","message":"not found"}}"#) }
        #expect(try await old.tags() == [:])
        let (down, _) = rest { _ in (401, #"{"error":{"code":"unauthorized","message":"unauthorized"}}"#) }
        await #expect(throws: RelayAPIError.self) { try await down.tags() }
    }

    @Test func setTagsPutsTheSetAndReturnsWhatIsStored() async throws {
        let (api, http) = rest { _ in (200, #"{"tags":["Work"]}"#) }
        #expect(try await api.setTags("a1", ["Work", "work"]) == ["Work"])
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "PUT" && r.url?.path == "/api/sessions/a1/tags")
        #expect(body(r) == .object(["tags": .array([.string("Work"), .string("work")])]))
    }
}

/// Pin, rename and tags change the store at once and go back when the relay refuses.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct OptimisticUpdateTests {
    let transport = FakeTransport()
    let clock = TestClock()
    let refuse = Watched<Bool>(false)
    let http: FakeHTTP
    let store: SessionStore

    init() {
        let refuse = refuse
        http = FakeHTTP { r in
            let path = r.url?.path ?? ""
            if refuse.current, ["PATCH", "PUT"].contains(r.httpMethod ?? "") {
                return (403, #"{"error":{"code":"read_only","message":"nope"}}"#)
            }
            switch (r.httpMethod ?? "", path) {
            case ("GET", "/api/sessions"):
                return (200, #"{"data":[{"id":"s1","source":"telegram","title":"Dates"},{"id":"s2","source":"cli","pinned":true}]}"#)
            case ("GET", "/api/tags"):
                return (200, #"{"sessions":{"s1":["a"],"gone":["z"]}}"#)
            case ("PATCH", "/api/sessions/s1"):
                let pinned = (r.httpBody.flatMap { try? Wire.decode(JSONValue.self, from: $0) }) == .object(["pinned": .bool(true)])
                return (200, pinned ? #"{"session":{"id":"s1","pinned":true}}"# : #"{"session":{"id":"s1","title":"Years"}}"#)
            case ("PUT", "/api/sessions/s1/tags"):
                return (200, #"{"tags":["a","B"]}"#)
            default:
                return (404, #"{"error":{"code":"not_found","message":"not found"}}"#)
            }
        }
        let clock = clock
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport,
                                 sleep: { try await clock.sleep(for: $0) })
        store = SessionStore(client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http))
    }

    func title(_ id: String) -> String? { store.sessionList.first { $0.id == id }?.title }
    func pinned(_ id: String) -> Bool { store.sessionList.first { $0.id == id }?.isPinned ?? false }

    @Test func refreshLoadsPinnedAndTags() async throws {
        try await store.refreshSessions()
        #expect(pinned("s2") && !pinned("s1"))
        #expect(store.tags["s1"] == ["a"])
    }

    @Test func pinSticksAndKeepsTheOverviewInStep() async throws {
        try await store.refreshSessions()
        try await store.setPinned("s1", true)
        #expect(pinned("s1") && store.overview["s1"]?.info?.isPinned == true)
    }

    @Test func refusedPinGoesBack() async throws {
        try await store.refreshSessions()
        refuse.mutate { $0 = true }
        await #expect(throws: RelayAPIError.self) { try await store.setPinned("s1", true) }
        #expect(!pinned("s1") && store.overview["s1"]?.info?.isPinned == false)
        await #expect(throws: RelayAPIError.self) { try await store.setPinned("s2", false) }
        #expect(pinned("s2"))
    }

    @Test func renameSticksAndARefusedRenameGoesBack() async throws {
        try await store.refreshSessions()
        try await store.renameSession("s1", to: "Years")
        #expect(title("s1") == "Years")
        refuse.mutate { $0 = true }
        await #expect(throws: RelayAPIError.self) { try await store.renameSession("s1", to: "Nope") }
        #expect(title("s1") == "Years" && store.overview["s1"]?.info?.title == "Years")
    }

    @Test func tagsKeepWhatTheRelayStoredAndAnInvalidSetNeverLeaves() async throws {
        try await store.refreshSessions()
        try await store.setTags("s1", ["a", " B "])
        #expect(store.tags["s1"] == ["a", "B"])
        let before = http.requests.current.count
        await #expect(throws: TagRules.Violation.tooMany) { try await store.setTags("s1", (1...11).map { "t\($0)" }) }
        #expect(http.requests.current.count == before && store.tags["s1"] == ["a", "B"])
    }

    @Test func refusedTagsGoBack() async throws {
        try await store.refreshSessions()
        refuse.mutate { $0 = true }
        await #expect(throws: RelayAPIError.self) { try await store.setTags("s1", ["a", "new"]) }
        #expect(store.tags["s1"] == ["a"])
        await #expect(throws: RelayAPIError.self) { try await store.setTags("s2", ["x"]) }
        #expect(store.tags["s2"] == nil)
    }

    @Test func errorsReadAsOneLine() {
        #expect(SessionStore.message(for: RelayAPIError(status: 409, code: .busy, message: "a run is still writing")) == "a run is still writing")
        #expect(SessionStore.message(for: TagRules.Violation.empty) == "A tag can't be empty.")
        #expect(SessionStore.message(for: URLError(.notConnectedToInternet)) == "Can't reach the relay.")
    }
}
