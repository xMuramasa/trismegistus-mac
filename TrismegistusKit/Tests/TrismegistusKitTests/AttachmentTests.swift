import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import TrismegistusKit

let imageID = String(repeating: "ab", count: 32)
let imageID2 = String(repeating: "cd", count: 32)
let imageRef = AttachmentRef(id: imageID, mime: "image/png", width: 1280, height: 800)

/// Images in the chat (#43, #44): the prompt's attachments, upload and download, history, outbox, the disk cache.
@Suite struct AttachmentProtocolTests {
    @Test func promptEncodesAttachmentsOnlyWhenThereAreSome() throws {
        let plain = try Wire.decode(JSONValue.self, from: Wire.encode(ClientMessage.prompt(clientMsgID: "c1", sessionID: "s1", text: "hi")))
        #expect(plain == .object(["type": .string("prompt"), "client_msg_id": .string("c1"), "session_id": .string("s1"), "text": .string("hi")]))
        let message = ClientMessage.prompt(clientMsgID: "c1", sessionID: "s1", text: "", attachments: [imageID, imageID2])
        let json = try Wire.decode(JSONValue.self, from: Wire.encode(message))
        #expect(json == .object([
            "type": .string("prompt"), "client_msg_id": .string("c1"), "session_id": .string("s1"), "text": .string(""),
            "attachments": .array([.string(imageID), .string(imageID2)]),
        ]))
        #expect(try Wire.decode(ClientMessage.self, from: Wire.encode(message)) == message)
    }

    @Test func promptAttachmentsAreOneToFourUniqueIDs() {
        for bad in ["[]", #"["a","b","c","d","e"]"#, #"["a","a"]"#] {
            let json = #"{"type":"prompt","client_msg_id":"c1","session_id":"s1","text":"","attachments":\#(bad)}"#
            #expect(throws: (any Error).self) { try Wire.decode(ClientMessage.self, from: Data(json.utf8)) }
        }
    }

    @Test func historyUserMessagesCarryAttachments() {
        let h = history(#"""
        [{"id":1,"role":"user","content":"Look\n\n[screenshot]","attachments":[{"id":"\#(imageID)","mime":"image/png","width":1280,"height":800},{"id":7}]},
         {"id":2,"role":"assistant","content":"A cat."}]
        """#)
        #expect(h[0].attachments == [imageRef])
        #expect(h[1].attachments.isEmpty)
    }
}

@Suite struct UserMessageTests {
    @Test func screenshotLinesHideOnlyWithAttachments() {
        #expect(ChatTimeline.userMessage("Look\n\n[screenshot]", attachments: [imageRef]) == ("Look", [.attachment(imageRef)]))
        #expect(ChatTimeline.userMessage("[screenshot]\n[screenshot]", attachments: [imageRef]) == ("", [.attachment(imageRef)]))
        #expect(ChatTimeline.userMessage("Look\n\n[screenshot]", attachments: []) == ("Look\n\n[screenshot]", []))
        // Only trailing ones: one quoted in the middle stays.
        #expect(ChatTimeline.userMessage("[screenshot] is\nthe note\n[screenshot]", attachments: [imageRef]).text == "[screenshot] is\nthe note")
    }

    @Test func telegramImageNotesBecomeImages() {
        let content = "What is this?\n\n[Image attached at: /home/muramasa/.hermes/cache/images/img_86942c9e70d7.jpg]\n[screenshot]"
        #expect(ChatTimeline.userMessage(content, attachments: []) == (
            "What is this?", [.media(path: "/home/muramasa/.hermes/cache/images/img_86942c9e70d7.jpg")]))
        #expect(ChatTimeline.userMessage("[Image attached at: relative.jpg]", attachments: []) == ("[Image attached at: relative.jpg]", []))
    }

    @Test func timelineShowsTheImages() {
        var s = SessionState(id: "s1")
        s.applyHistory(history(#"""
        [{"id":1,"role":"user","content":"Look\n\n[screenshot]","timestamp":1792801000,"attachments":[{"id":"\#(imageID)","mime":"image/png","width":1280,"height":800}]}]
        """#))
        #expect(ChatTimeline.items(s, compact: true) == [
            .user(id: "h-1", text: "Look", time: Date(timeIntervalSince1970: 1_792_801_000), images: [.attachment(imageRef)]),
        ])
    }
}

/// #44: Hermes' `MEDIA:` lines in an answer.
@Suite struct MediaBlockTests {
    @Test func mediaLinesBecomeImageBlocks() {
        #expect(MarkdownBlocks.parse("Here it is:\nMEDIA:/home/m/chart.png\nDone.") == [
            .prose("Here it is:"), .image(path: "/home/m/chart.png"), .prose("Done."),
        ])
        #expect(MarkdownBlocks.parse("`MEDIA:/tmp/a b.jpg`") == [.image(path: "/tmp/a b.jpg")])
        #expect(MarkdownBlocks.parse("  MEDIA:/tmp/x.gif  ") == [.image(path: "/tmp/x.gif")])
    }

    @Test func otherMediaMentionsStayText() {
        for text in ["See MEDIA:/tmp/x.png here", "MEDIA:relative.png", "MEDIA:", "`MEDIA:/tmp/x.png` and more"] {
            #expect(MarkdownBlocks.parse(text) == [.prose(text)])
        }
        #expect(MarkdownBlocks.parse("```\nMEDIA:/tmp/x.png\n```") == [.code(language: nil, text: "MEDIA:/tmp/x.png")])
    }
}

@Suite struct AttachmentRESTTests {
    func rest(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (RelayREST, FakeHTTP) {
        let http = FakeHTTP(respond)
        return (RelayREST(baseURL: relayURL, token: fakeToken, http: http), http)
    }

    @Test func upload() async throws {
        let (api, http) = rest { _ in (201, #"{"id":"\#(imageID)","mime":"image/png","width":1280,"height":800,"bytes":4}"#) }
        #expect(try await api.uploadAttachment(Data([1, 2, 3, 4]), mime: "image/png") == imageRef)
        let r = try #require(http.requests.current.first)
        #expect(r.httpMethod == "POST" && r.url?.path == "/api/attachments")
        #expect(r.value(forHTTPHeaderField: "Content-Type") == "image/png" && r.httpBody == Data([1, 2, 3, 4]))
        #expect(r.value(forHTTPHeaderField: "Authorization") == "Bearer \(fakeToken)")
    }

    @Test func uploadErrors() async {
        let (big, _) = rest { _ in (413, #"{"error":{"code":"too_large","message":"at most 8 MiB"}}"#) }
        await #expect(throws: RelayAPIError(status: 413, code: .tooLarge, message: "at most 8 MiB")) {
            try await big.uploadAttachment(Data([1]), mime: "image/png")
        }
        let (viewer, _) = rest { _ in (403, #"{"error":{"code":"forbidden","message":"viewer"}}"#) }
        await #expect(throws: RelayAPIError(status: 403, code: .forbidden, message: DeviceRole.viewerNotice)) {
            try await viewer.uploadAttachment(Data([1]), mime: "image/png")
        }
    }

    @Test func downloadAndMedia() async throws {
        let (api, http) = rest { _ in (200, "PNG") }
        #expect(try await api.attachment(imageID) == Data("PNG".utf8))
        #expect(try await api.sessionMedia("api_1", path: "/home/m/a b+c.png") == Data("PNG".utf8))
        let urls = http.requests.current.map { $0.url?.absoluteString }
        #expect(urls == ["https://relay.invalid/api/attachments/\(imageID)", "https://relay.invalid/api/sessions/api_1/media?path=/home/m/a%20b%2Bc.png"])
    }

    @Test func badIDsAndRelativePathsNeverLeaveTheApp() async {
        let (api, http) = rest { _ in (200, "") }
        await #expect(throws: RelayAPIError.self) { try await api.attachment("../me") }
        await #expect(throws: RelayAPIError.self) { try await api.attachment(imageID.uppercased()) }
        await #expect(throws: RelayAPIError.self) { try await api.sessionMedia("api_1", path: "a.png") }
        await #expect(throws: RelayAPIError.self) { try await api.sessionMedia("../x", path: "/a.png") }
        #expect(http.requests.current.isEmpty)
    }
}

@Suite struct ImageFilesTests {
    /// Starts at the real time: the cache dates files by the file system's clock.
    final class Clock: @unchecked Sendable {
        var now = Date()
    }

    func files(_ respond: @escaping @Sendable (URLRequest) -> (Int, String)) -> (ImageFiles, FakeHTTP, Clock, URL) {
        let http = FakeHTTP(respond)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("images-\(UUID().uuidString)")
        let clock = Clock()
        return (ImageFiles(directory: dir, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http), now: { clock.now }), http, clock, dir)
    }

    @Test func attachmentsDownloadOnceAndStay() async throws {
        let (files, http, clock, dir) = files { _ in (200, "PNG") }
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try #require(await files.attachment(imageRef))
        #expect(url.lastPathComponent == "a-\(imageID).png" && (try? Data(contentsOf: url)) == Data("PNG".utf8))
        clock.now += 365 * 86400 // immutable
        #expect(await files.attachment(imageRef) == url)
        #expect(http.requests.current.count == 1)
    }

    @Test func storedUploadsNeedNoDownload() async {
        let (files, http, _, dir) = files { _ in (500, "") }
        defer { try? FileManager.default.removeItem(at: dir) }
        await files.store(Data("PNG".utf8), for: imageRef)
        #expect(await files.attachment(imageRef) != nil)
        #expect(http.requests.current.isEmpty)
    }

    @Test func mediaKeepsAnHourAndFailuresAreRemembered() async throws {
        let status = Watched(200)
        let (files, http, clock, dir) = files { _ in (status.current, status.current == 200 ? "JPG" : #"{"error":{"code":"not_found","message":"not found"}}"#) }
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try #require(await files.media(session: "s1", path: "/home/m/x.JPG"))
        #expect(url.pathExtension == "jpg")
        #expect(await files.media(session: "s2", path: "/home/m/x.JPG") != url) // keyed by session too
        #expect(http.requests.current.count == 2)
        clock.now += ImageFiles.mediaMaxAge - 60
        #expect(await files.media(session: "s1", path: "/home/m/x.JPG") == url)
        #expect(http.requests.current.count == 2)
        clock.now += 120
        status.mutate { $0 = 404 }
        #expect(await files.media(session: "s1", path: "/home/m/x.JPG") == nil)
        #expect(await files.media(session: "s1", path: "/home/m/x.JPG") == nil)
        #expect(http.requests.current.count == 3) // the 404 isn't asked again
        await files.forgetFailures()
        _ = await files.media(session: "s1", path: "/home/m/x.JPG")
        #expect(http.requests.current.count == 4)
    }

    @Test func keyIsStable() {
        #expect(ImageFiles.key("".utf8) == "cbf29ce484222325")
        #expect(ImageFiles.key("a".utf8) == "af63dc4c8601ec8c")
    }
}

/// The outbox with images: upload, then `prompt` with the ids; a failed send keeps the bytes for a retry.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct AttachmentStoreTests {
    let transport = FakeTransport()
    let uploads = Watched<Int>(0)
    let failUploads = Watched(false)
    let http: FakeHTTP
    let store: SessionStore

    init() {
        let (uploads, failUploads) = (uploads, failUploads)
        http = FakeHTTP { r in
            switch (r.httpMethod ?? "", r.url?.path ?? "") {
            case ("POST", "/api/attachments"):
                if failUploads.current { return (413, #"{"error":{"code":"too_large","message":"at most 8 MiB"}}"#) }
                let id = uploads.mutate { $0 += 1; return $0 } == 1 ? imageID : imageID2
                return (201, #"{"id":"\#(id)","mime":"image/png","width":2,"height":1,"bytes":3}"#)
            case ("GET", "/api/sessions/s1/messages"):
                return (200, #"{"data":[]}"#)
            default:
                return (404, #"{"error":{"code":"not_found","message":"not found"}}"#)
            }
        }
        let clock = TestClock()
        let client = RelayClient(relayURL: relayURL, token: fakeToken, transport: transport, sleep: { try await clock.sleep(for: $0) })
        store = SessionStore(client: client, rest: RelayREST(baseURL: relayURL, token: fakeToken, http: http))
    }

    func connect() async -> FakeConnection {
        await store.open("s1")
        store.start()
        let c = await transport.connection(0)
        _ = await c.sent(1)
        c.push(.ready(device: "macbook", serverVersion: "0.1.0"))
        _ = await c.sent(2)
        return c
    }

    let images = [ImageUpload(data: Data("one".utf8), mime: "image/png", width: 2, height: 1),
                  ImageUpload(data: Data("two".utf8), mime: "image/jpeg", width: 2, height: 1)]

    @Test func uploadsThenPrompts() async {
        let c = await connect()
        let id = await store.sendPrompt("", images: images, to: "s1")
        #expect(await c.sent(3).last == .prompt(clientMsgID: id, sessionID: "s1", text: "", attachments: [imageID, imageID2]))
        let posts = http.requests.current.filter { $0.httpMethod == "POST" }
        #expect(posts.map { $0.value(forHTTPHeaderField: "Content-Type") } == ["image/png", "image/jpeg"])
        #expect(store.sessions["s1"]?.outbox.first?.images.map(\.attachmentID) == [imageID, imageID2])
        await store.stop()
    }

    @Test func failedUploadIsRetriedWithTheBytes() async {
        let c = await connect()
        failUploads.mutate { $0 = true }
        let first = await store.sendPrompt("look", images: images, to: "s1")
        #expect(store.sessions["s1"]?.outbox.map(\.status) == [.failed(code: .tooLarge, message: "at most 8 MiB")])
        #expect(store.sessions["s1"]?.outbox.first?.images.map(\.data) == images.map(\.data))
        failUploads.mutate { $0 = false }
        let second = await store.retryPrompt(first, in: "s1")
        #expect(second != nil && second != first)
        #expect(store.sessions["s1"]?.outbox.map(\.id) == [second!])
        #expect(await c.sent(3).last == .prompt(clientMsgID: second!, sessionID: "s1", text: "look", attachments: [imageID, imageID2]))
        #expect(await store.retryPrompt(second!, in: "s1") == nil) // not failed
        await store.stop()
    }

    /// The relay deleted an unused upload (an hour): the retry uploads again instead of reusing the id.
    @Test func retryUploadsAgainWhenTheIDIsGone() async {
        let c = await connect()
        let first = await store.sendPrompt("look", images: [images[0]], to: "s1")
        _ = await c.sent(3)
        await store.handle(.message(.error(code: .badRequest, message: "unknown attachment", ref: first)))
        #expect(uploads.current == 1)
        let second = await store.retryPrompt(first, in: "s1")
        #expect(await c.sent(4).last == .prompt(clientMsgID: second!, sessionID: "s1", text: "look", attachments: [imageID2]))
        #expect(uploads.current == 2)
        await store.stop()
    }
}

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Mac only: ImageIO.
@Suite struct ImagePreparationTests {
    func image(_ width: Int, _ height: Int, alpha: Bool, noise: Bool = false) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if noise, let p = context.data?.assumingMemoryBound(to: UInt32.self) {
            var x: UInt32 = 1
            for i in 0..<(context.bytesPerRow / 4 * height) {
                x = x &* 1_664_525 &+ 1_013_904_223
                p[i] = x | 0xFF00_0000
            }
        }
        return context.makeImage()!
    }

    func encode(_ image: CGImage, _ type: UTType, _ props: [CFString: Any] = [:]) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func properties(_ data: Data) -> [CFString: Any] {
        let source = CGImageSourceCreateWithData(data as CFData, nil)!
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    }

    @Test func bigPNGIsResizedAndStaysPNG() throws {
        let out = try ImagePreparation.prepare(encode(image(4096, 1024, alpha: true), .png))
        #expect(out.mime == "image/png" && out.width == 2048 && out.height == 512)
    }

    @Test func pngOverTwoMiBBecomesJPEG() throws {
        let out = try ImagePreparation.prepare(encode(image(2000, 1500, alpha: false, noise: true), .png))
        #expect(out.mime == "image/jpeg" && out.width == 2000)
    }

    @Test func tiffBecomesJPEGOrPNGWithAlpha() throws {
        #expect(try ImagePreparation.prepare(encode(image(300, 200, alpha: false), .tiff)).mime == "image/jpeg")
        #expect(try ImagePreparation.prepare(encode(image(300, 200, alpha: true), .tiff)).mime == "image/png")
        #expect(try ImagePreparation.prepare(encode(image(300, 200, alpha: false), .bmp)).mime == "image/jpeg")
    }

    @Test func smallGIFIsSentAsIs() throws {
        let gif = encode(image(40, 30, alpha: false), .gif)
        let out = try ImagePreparation.prepare(gif)
        #expect(out.data == gif && out.mime == "image/gif" && out.width == 40 && out.height == 30)
    }

    @Test func gpsAndExifAreDropped() throws {
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 48.85, kCGImagePropertyGPSLongitude: 2.35]
        let exif: [CFString: Any] = [kCGImagePropertyExifUserComment: "secret"]
        let jpeg = encode(image(100, 80, alpha: false), .jpeg, [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyExifDictionary: exif])
        #expect(properties(jpeg)[kCGImagePropertyGPSDictionary] != nil)
        let out = try ImagePreparation.prepare(jpeg)
        #expect(out.mime == "image/jpeg")
        #expect(properties(out.data)[kCGImagePropertyGPSDictionary] == nil)
        #expect((properties(out.data)[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
    }

    @Test func orientationIsApplied() throws {
        let jpeg = encode(image(100, 50, alpha: false), .jpeg, [kCGImagePropertyOrientation: 6]) // rotated 90°
        let out = try ImagePreparation.prepare(jpeg)
        #expect(out.width == 50 && out.height == 100)
    }

    @Test func notAnImage() {
        #expect(throws: ImagePreparation.Failure.notAnImage) { try ImagePreparation.prepare(Data("%PDF-1.7".utf8)) }
        #expect(throws: ImagePreparation.Failure.notAnImage) { try ImagePreparation.prepare(Data()) }
    }
}
#endif
