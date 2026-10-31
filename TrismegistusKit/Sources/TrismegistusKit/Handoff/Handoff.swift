import Foundation

/// A handoff that stopped after the new conversation was made: it is listed and usable, the prompt wasn't sent.
public struct HandoffError: Error, Sendable, Equatable {
    public let sessionID: String
    public let message: String
}

/// Threads and handoffs on top of the store's links.
extension SessionStore {
    /// The newest part of the thread `id` is in (itself when it isn't continued).
    public func threadTip(of id: String) -> String {
        links.isEmpty ? id : HandoffChain.tip(of: id, links: links, listed: Set(sessionList.map(\.id)))
    }

    /// The parts `id` continues, newest first.
    public func olderParts(of id: String) -> [String] {
        HandoffChain.older(than: id, links: links)
    }

    /// The parts a delete of the thread ending at `id` removes, newest first: `id` and the older ones whose source the
    /// relay lets the Mac delete. Unlisted parts are tried (gone or protected, they are skipped).
    public func deletableParts(of id: String) -> [String] {
        [id] + olderParts(of: id).filter { part in
            sessionList.first { $0.id == part }.map { SessionCapabilities($0).canDelete } ?? true
        }
    }

    /// Deletes the thread from the newest part to the oldest (the relay drops a deleted session's links on both
    /// sides). Older parts that are already gone or protected are skipped; any other refusal stops it and is thrown.
    public func deleteThread(_ id: String) async throws {
        for part in deletableParts(of: id) {
            do {
                try await deleteSession(part)
            } catch let error as RelayAPIError where part != id && (error.status == 404 || error.code == .readOnly) {
                continue
            }
        }
    }

    /// Continues `old` in a new conversation: create it, link it, copy title, tags and pin (unpinning the old one),
    /// set `model` when it differs from the relay's current one, then send `prompt` through the outbox. Returns the
    /// new id and the steps that failed without stopping it. Without the link the prompt isn't sent: `HandoffError`.
    public func handOff(_ old: SessionInfo, model: ModelChoice?, prompt: String) async throws -> (sessionID: String, problems: [String]) {
        let new = try await createSession().id
        do {
            try await setContinues(new, from: old.id)
        } catch {
            throw HandoffError(sessionID: new, message: "Couldn't link the new conversation: " + Self.message(for: error))
        }
        var problems: [String] = []
        func step(_ what: String, _ call: () async throws -> Void) async {
            do { try await call() } catch { problems.append("\(what): " + Self.message(for: error)) }
        }
        if let title = old.title, !title.isEmpty {
            await step("Title not copied") { try await renameSession(new, to: title) }
        }
        if let oldTags = tags[old.id], !oldTags.isEmpty {
            await step("Tags not copied") { try await setTags(new, oldTags) }
        }
        if old.isPinned {
            await step("Pin not moved") {
                try await setPinned(new, true)
                try await setPinned(old.id, false)
            }
        }
        if let model, model != models?.current {
            await step("Model not set") { try await setModel(new, model) }
        }
        await open(new)
        await sendPrompt(prompt, to: new)
        return (new, problems)
    }
}
