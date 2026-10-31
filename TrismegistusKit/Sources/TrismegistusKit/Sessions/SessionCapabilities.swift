import Foundation

/// What the relay lets a client do with a session, by its Hermes source (relay/internal/server/rest.go): pin, rename
/// and tag every session; delete only the ones the Mac could have made or that nothing else owns.
public struct SessionCapabilities: Sendable, Equatable {
    public static let deletableSources: Set<String> = ["api_server", "cron", "cli"]

    public var canPin: Bool { true }
    public var canRename: Bool { true }
    public var canTag: Bool { true }
    public let canDelete: Bool

    /// `source` nil (not listed yet) can't be deleted: the relay answers 403 read_only for a messaging source.
    public init(source: String?) {
        canDelete = source.map(Self.deletableSources.contains) ?? false
    }

    public init(_ info: SessionInfo) { self.init(source: info.source) }
}
