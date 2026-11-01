import Foundation
import Observation

/// One agent's transcript, read forward with `after=`. A new one per agent shown.
@MainActor @Observable
public final class AgentTranscript {
    /// Kept in memory at most; the oldest go first.
    public static let maxSteps = 2000
    /// The relay's cap per answer: a full page means more is waiting.
    static let pageSize = 200

    public private(set) var steps: [AgentStep] = []
    /// Steps dropped from the front to stay within `maxSteps`.
    public private(set) var dropped = 0
    /// The agent's state as the last answer said it; nil before one, or for a process without a transcript.
    public private(set) var alive: Bool?
    public private(set) var error: AgentsError?
    public private(set) var isLoaded = false

    public let id: String
    let rest: RelayREST
    private var next = 0

    public init(id: String, rest: RelayREST) {
        self.id = id
        self.rest = rest
    }

    /// Reads what is new, page after page until the relay has no more.
    public func poll() async {
        do {
            while true {
                let page = try await rest.agentTranscript(id, after: next)
                append(page.steps)
                // A relay that sent an older `next` would loop on the same page.
                let more = page.steps.count >= Self.pageSize && page.next > next
                next = max(next, page.next)
                alive = page.alive
                error = nil
                if !more { break }
            }
        } catch {
            guard !Task.isCancelled else { return }
            self.error = AgentsError.wrap(error)
        }
        isLoaded = true
    }

    /// Polls every `interval` while the agent is alive and returns once it is finished (a finished one is read once).
    /// Ends too when the relay no longer knows the agent. Cancel it when the view goes away.
    public func follow(every interval: Duration = .seconds(2)) async {
        var previous: Bool?
        while !Task.isCancelled {
            await poll()
            if error?.isNotFound == true { return }
            // One more read after the end shows the last lines; a finished agent seen first needs none.
            if alive == false, previous != true { return }
            previous = alive
            try? await Task.sleep(for: interval)
        }
    }

    private func append(_ new: [AgentStep]) {
        steps += new
        if steps.count > Self.maxSteps {
            dropped += steps.count - Self.maxSteps
            steps.removeFirst(steps.count - Self.maxSteps)
        }
    }
}
