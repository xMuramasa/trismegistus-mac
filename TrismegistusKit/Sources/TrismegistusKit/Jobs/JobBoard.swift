import Foundation
import Observation

/// Hermes' cron jobs through the relay; the shared `DeviceProfile` says whether this device may change them. A new one per
/// pairing; the list is fetched on every connect and while the Jobs view is shown. Writes keep the list current; a failed write reloads it
/// (Hermes may have saved a job whose schedule it then didn't register).
@MainActor @Observable
public final class JobBoard {
    public private(set) var jobs: [Job] = []
    /// The last refresh failed (`hermes_unavailable`: Hermes without its cron scheduler). The jobs it had stay.
    public private(set) var error: RelayAPIError?
    /// A refresh has finished (with or without jobs).
    public private(set) var isLoaded = false

    public let rest: RelayREST
    let device: DeviceProfile

    public init(rest: RelayREST, device: DeviceProfile) {
        self.rest = rest
        self.device = device
    }

    /// Nil until the relay answered: no write controls until then.
    public var role: DeviceRole? { device.role }
    public var canManage: Bool { device.canManage }
    /// The last run of some job failed.
    public var anyFailed: Bool { jobs.contains(where: \.lastRunFailed) }

    public func refresh() async {
        do {
            jobs = try await rest.jobs()
            error = nil
        } catch {
            self.error = error as? RelayAPIError
                ?? RelayAPIError(status: 0, code: .hermesUnavailable, message: "Can't reach the relay.")
        }
        isLoaded = true
    }

    @discardableResult
    public func create(_ draft: JobDraft) async throws -> Job {
        let job = try await write { try await rest.createJob(draft.createBody) }
        jobs.append(job)
        return job
    }

    /// Sends what differs from `job`; nothing when nothing does.
    public func save(_ draft: JobDraft, to job: Job) async throws {
        let body = draft.updateBody(from: job)
        guard !body.isEmpty else { return }
        replace(try await write { try await rest.updateJob(job.id, body) })
    }

    public func perform(_ action: RelayREST.JobAction, on job: Job) async throws {
        replace(try await write { try await rest.jobAction(job.id, action) })
    }

    public func delete(_ job: Job) async throws {
        try await write { try await rest.deleteJob(job.id) }
        jobs.removeAll { $0.id == job.id }
    }

    private func replace(_ job: Job) {
        if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i] = job } else { jobs.append(job) }
    }

    private func write<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch {
            await refresh()
            throw error
        }
    }
}
