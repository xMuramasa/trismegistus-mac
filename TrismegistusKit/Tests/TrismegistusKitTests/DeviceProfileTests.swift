import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

@MainActor @Suite struct DeviceProfileTests {
    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: URL(string: "https://relay.invalid")!, token: fakeToken, http: http), http)
    }

    @Test func forbiddenDecodes() throws {
        #expect(try Wire.decode(ServerMessage.self, from: Data(#"{"type":"error","code":"forbidden","message":"x"}"#.utf8)) == .error(code: .forbidden, message: "x"))
        // The relay's code or, for a body that isn't its JSON, the HTTP status: either way the viewer's sentence.
        for body in [#"{"error":{"code":"forbidden","message":"manager only"}}"#, "<html>forbidden</html>"] {
            let error = RelayAPIError(status: 403, body: Data(body.utf8))
            #expect(error.code == .forbidden && error.message == DeviceRole.viewerNotice)
        }
        // A read-only session keeps its own code and message.
        let readOnly = RelayAPIError(status: 403, body: Data(#"{"error":{"code":"read_only","message":"read-only here"}}"#.utf8))
        #expect(readOnly.code == .readOnly && readOnly.message == "read-only here")
    }

    @Test func viewerWritesReadTheSameForJobsAndAgents() async {
        let (api, _) = rest { _ in (403, #"{"error":{"code":"forbidden","message":"x"}}"#) }
        let job = await #expect(throws: RelayAPIError.self) { try await api.deleteJob("0000000000a1") }
        let agent = await #expect(throws: AgentsError.self) { try await api.stopAgent("proc_a1") }
        let github = await #expect(throws: GitHubError.self) { _ = try await api.githubComment(repo: "xMuramasa/m", number: 1, body: "x") }
        #expect(job?.message == DeviceRole.viewerNotice)
        #expect(AgentsError.describe(agent!) == DeviceRole.viewerNotice)
        // GitHub keeps the relay's text: its `forbidden` also covers another owner's repo or a token scope, for managers.
        #expect(GitHubError.describe(github!) == "x")
    }

    @Test func roles() async {
        for (body, status, role) in [
            (#"{"device":"mac","role":"manager"}"#, 200, DeviceRole.manager),
            (#"{"device":"mac","role":"owner"}"#, 200, .viewer),
            (#"{"device":"mac","role":"viewer"}"#, 200, .viewer),
        ] {
            let (api, _) = rest { _ in (status, body) }
            let device = DeviceProfile(rest: api)
            #expect(device.role == nil && !device.canManage)
            await device.refresh()
            #expect(device.role == role && device.info?.device == "mac")
        }
    }

    @Test func aFailedRefreshKeepsTheLastAnswer() async {
        let up = Watched(true)
        let (api, _) = rest { _ in up.current ? (200, #"{"device":"mac","role":"manager"}"#) : (404, "404 page not found") }
        let device = DeviceProfile(rest: api)
        await device.refresh()
        up.mutate { $0 = false }
        await device.refresh()
        #expect(device.canManage)
        // A relay that predates roles never gives one: no write controls.
        let (old, _) = rest { _ in (404, "404 page not found") }
        let none = DeviceProfile(rest: old)
        await none.refresh()
        #expect(none.role == nil && !none.canManage)
    }

    @Test func oneMeForAllThreeBoards() async {
        let role = Watched("viewer")
        let (api, http) = rest { r in
            switch r.url!.path {
            case "/api/me": (200, #"{"device":"mac","role":"\#(role.current)"}"#)
            case "/api/jobs": (200, #"{"jobs":[]}"#)
            default: (200, #"{"agents":[]}"#)
            }
        }
        let device = DeviceProfile(rest: api)
        let jobs = JobBoard(rest: api, device: device)
        let agents = AgentBoard(rest: api, device: device)
        await device.refresh() // the connect
        await jobs.refresh()
        await agents.refresh()
        await jobs.refresh()
        await agents.refresh()
        #expect(http.requests.current.filter { $0.url!.path == "/api/me" }.count == 1)
        #expect(!jobs.canManage && !agents.canManage && jobs.role == .viewer)

        // `devices set-role` applies at the next refresh (the app coming to the foreground), for every board at once.
        role.mutate { $0 = "manager" }
        await device.refresh()
        #expect(jobs.canManage && agents.canManage && jobs.role == .manager)
        #expect(http.requests.current.filter { $0.url!.path == "/api/me" }.count == 2)
    }
}
