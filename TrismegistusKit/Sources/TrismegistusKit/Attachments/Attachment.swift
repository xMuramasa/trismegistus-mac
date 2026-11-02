import Foundation

/// An image the relay stores (`POST /api/attachments`), as the upload answers it and as history messages list it.
public struct AttachmentRef: Decodable, Sendable, Equatable, Hashable {
    /// The bytes' sha256, 64 lowercase hex characters.
    public var id: String
    public var mime: String
    public var width: Int
    public var height: Int

    public init(id: String, mime: String, width: Int, height: Int) {
        self.id = id
        self.mime = mime
        self.width = width
        self.height = height
    }

    static func isValidID(_ id: String) -> Bool {
        id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// A prepared image waiting in the outbox: the bytes to upload (kept so a failed send can upload them again) and,
/// once uploaded, the relay's id.
public struct ImageUpload: Sendable, Hashable, Identifiable {
    /// Local, stable across retries.
    public let id: UUID
    public var data: Data
    /// `image/png`, `image/jpeg` or `image/gif`.
    public var mime: String
    public var width: Int
    public var height: Int
    public var attachmentID: String?

    public init(id: UUID = UUID(), data: Data, mime: String, width: Int, height: Int, attachmentID: String? = nil) {
        self.id = id
        self.data = data
        self.mime = mime
        self.width = width
        self.height = height
        self.attachmentID = attachmentID
    }

    /// By the local id: hashing the bytes on every lookup would cost.
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// The relay's limit for one prompt's images.
    public static let maxMessageBytes = 7 << 20
    public static let maxPerMessage = 4
}

/// The chat's images on disk: relay attachments by id (immutable, kept), Hermes' media by session and path (an hour).
/// Fetches through RelayREST on a miss; a failed fetch is remembered until the next `forgetFailures()`.
/// shortcut: nothing is evicted (the folder is in Caches, which macOS may purge, and unpairing deletes it); add a size
/// cap if it grows.
public actor ImageFiles {
    public let directory: URL
    let rest: RelayREST
    let now: @Sendable () -> Date
    private var failed: Set<String> = []
    private var inFlight: [String: Task<URL, any Error>] = [:]

    public static let mediaMaxAge: TimeInterval = 3600

    public init(directory: URL, rest: RelayREST, now: @escaping @Sendable () -> Date = Date.init) {
        self.directory = directory
        self.rest = rest
        self.now = now
    }

    /// The file of an uploaded or listed attachment; nil when the relay doesn't have it or can't be reached.
    public func attachment(_ ref: AttachmentRef) async -> URL? {
        guard AttachmentRef.isValidID(ref.id) else { return nil }
        let url = directory.appending(path: "a-" + ref.id + "." + Self.fileExtension(mime: ref.mime))
        return await file(url, maxAge: nil) { [rest] in try await rest.attachment(ref.id) }
    }

    /// Keeps bytes this Mac uploaded, so its own message shows without a download.
    public func store(_ data: Data, for ref: AttachmentRef) {
        guard AttachmentRef.isValidID(ref.id) else { return }
        write(data, to: directory.appending(path: "a-" + ref.id + "." + Self.fileExtension(mime: ref.mime)))
    }

    /// One of Hermes' files a session's messages name (`MEDIA:` or Telegram's `[Image attached at:]`).
    public func media(session: String, path: String) async -> URL? {
        let ext = (path as NSString).pathExtension.lowercased()
        let url = directory.appending(path: "m-" + Self.key((session + "\n" + path).utf8) + "." + (ext.isEmpty ? "img" : ext))
        return await file(url, maxAge: Self.mediaMaxAge) { [rest] in try await rest.sessionMedia(session, path: path) }
    }

    /// A file for bytes not uploaded yet (Quick Look on a tray image).
    public func scratch(_ data: Data, mime: String) -> URL {
        let url = directory.appending(path: "t-" + Self.key(data) + "." + Self.fileExtension(mime: mime))
        if !FileManager.default.fileExists(atPath: url.path) { write(data, to: url) }
        return url
    }

    /// Lets the next look at a failed image ask the relay again (a reopened conversation).
    public func forgetFailures() { failed = [] }

    private func file(_ url: URL, maxAge: TimeInterval?, fetch: @escaping @Sendable () async throws -> Data) async -> URL? {
        let key = url.lastPathComponent
        if let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
            maxAge.map({ now().timeIntervalSince(date) < $0 }) ?? true
        {
            return url
        }
        guard !failed.contains(key) else { return nil }
        let task = inFlight[key] ?? Task {
            let data = try await fetch()
            write(data, to: url)
            return url
        }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        do {
            return try await task.value
        } catch {
            failed.insert(key)
            return nil
        }
    }

    private func write(_ data: Data, to url: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func fileExtension(mime: String) -> String {
        switch mime {
        case "image/png": "png"
        case "image/jpeg": "jpg"
        case "image/gif": "gif"
        case "image/webp": "webp"
        default: "img"
        }
    }

    /// FNV-1a 64, hex: a stable file name for any bytes (Hasher is seeded per launch).
    static func key(_ bytes: some Sequence<UInt8>) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in bytes {
            h ^= UInt64(b)
            h = h &* 0x100_0000_01b3
        }
        return String(h, radix: 16)
    }
}
