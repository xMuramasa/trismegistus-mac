import AppKit
import SwiftUI
import UniformTypeIdentifiers
import XCTest

@testable import TrismegistusUI

/// The chat's drop target (#45): what a drag carries, what a drop would do, and that AppKit offers it every drag over
/// a chat-like column while clicks still reach the views below.
@MainActor
final class ImageDropTests: XCTestCase {
    private var board: NSPasteboard!
    private var folder: URL!

    override func setUp() async throws {
        board = NSPasteboard(name: .init("trismegistus-test-\(UUID().uuidString)"))
        board.clearContents()
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ImageDropTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        board.releaseGlobally()
        try? FileManager.default.removeItem(at: folder)
    }

    private var png: Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: pasteboard

    func testImageFilesAndOtherFiles() throws {
        let a = try file("a.png", png), b = try file("b.jpg", png)
        let pdf = try file("c.pdf", Data("%PDF-1.4".utf8))
        board.writeObjects([a, pdf, b, folder.appendingPathComponent("folder")] as [NSURL])
        let images = PasteboardImages(board)
        XCTAssertEqual(images.files.map(\.lastPathComponent), ["a.png", "b.jpg"])
        XCTAssertEqual(images.others, 2)
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images.data(), [])
    }

    func testImageDataWithoutAFile() {
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString("https://example.com/cat.png", forType: .URL)
        board.writeObjects([item])
        let images = PasteboardImages(board)
        XCTAssertEqual(images.files, [])
        XCTAssertEqual(images.others, 0)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.data(), [png])
    }

    func testNothingButTextOrAPDF() throws {
        board.setString("hello", forType: .string)
        XCTAssertEqual(PasteboardImages(board).count, 0)
        board.clearContents()
        board.writeObjects([try file("only.pdf", Data("%PDF-1.4".utf8))] as [NSURL])
        let images = PasteboardImages(board)
        XCTAssertEqual(images.count, 0)
        XCTAssertEqual(images.others, 1)
    }

    /// A promise of a file, as Photos writes it. Receiving one needs a real drag.
    private final class Promise: NSObject, NSFilePromiseProviderDelegate {
        func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String { "promised" }
        func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping @Sendable ((any Error)?) -> Void) {
            completionHandler(CocoaError(.fileNoSuchFile))
        }
    }
    private let promise = Promise()

    private func provider(_ type: UTType) -> NSFilePromiseProvider { NSFilePromiseProvider(fileType: type.identifier, delegate: promise) }

    func testPromisesCountByTheirType() {
        board.writeObjects([provider(.png), provider(.jpeg), provider(.pdf)])
        let images = PasteboardImages(board)
        XCTAssertEqual(images.count, 2)
        XCTAssertEqual(images.others, 1)
        XCTAssertEqual(images.files, [])
        XCTAssertEqual(judge(images.count, others: images.others).lines, ["2 IMAGES", "1 OTHER FILE SKIPPED"])
    }

    func testAPromiseOfAPDFIsNotAnImage() {
        board.writeObjects([provider(.pdf)])
        let images = PasteboardImages(board)
        XCTAssertEqual(images.count, 0)
        XCTAssertEqual(images.others, 1)
        XCTAssertEqual(judge(images.count, others: images.others).title, "IMAGES ONLY")
    }

    func testAFileOrImageDataBeatsAPromise() throws {
        board.writeObjects([try file("a.png", png) as NSURL, provider(.png)])
        var images = PasteboardImages(board)
        XCTAssertEqual(images.files.map(\.lastPathComponent), ["a.png"])
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.others, 0)

        board.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        board.writeObjects([item, provider(.png)])
        images = PasteboardImages(board)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images.data(), [png])
    }

    func testDeliveringWithoutPromisesIsImmediate() throws {
        board.writeObjects([try file("a.png", png) as NSURL])
        var got: ([URL], [Data])?
        PasteboardImages(board).deliver { got = ($0, $1) }
        XCTAssertEqual(got?.0.map(\.lastPathComponent), ["a.png"])
        XCTAssertEqual(got?.1, [])
    }

    /// A promise whose drag isn't real fails or is never kept; either way the tray gets a file to show an error for.
    func testAPromiseThatIsNotKeptEndsInAnErrorCellNotAHang() async throws {
        board.writeObjects([provider(.png)])
        let done = expectation(description: "delivered")
        var got: [URL] = []
        PasteboardImages(board).deliver(timeout: 0.5) { files, _ in
            got = files
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(got.count, 1)
        XCTAssertFalse(got.contains { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testRegisteredTypesTakeFilesAndImagesNeverText() {
        let types = PasteboardImages.dragTypes
        XCTAssertTrue(types.contains(.fileURL))
        for type in NSFilePromiseReceiver.readableDraggedTypes { XCTAssertTrue(types.contains(.init(type)), type) }
        XCTAssertTrue(types.contains(.png))
        XCTAssertTrue(types.contains(.tiff))
        XCTAssertFalse(types.contains(.string))
        XCTAssertFalse(types.contains(.init(UTType.pdf.identifier)))
    }

    // MARK: rules

    private func judge(_ images: Int, others: Int = 0, room: Int = 4, refusal: ImageDropFeedback.Refusal? = nil, later: Bool = false) -> ImageDropFeedback {
        .judge(images: images, others: others, room: room, limit: 4, refusal: refusal, later: later)
    }

    func testAccepting() {
        XCTAssertEqual(judge(3), ImageDropFeedback(accepts: true, title: "DROP TO ATTACH", lines: ["3 IMAGES"]))
        XCTAssertEqual(judge(1).lines, ["1 IMAGE"])
        XCTAssertEqual(judge(3, room: 2).lines, ["2 OF 3 FIT // UP TO 4"])
        XCTAssertEqual(judge(2, others: 1).lines, ["2 IMAGES", "1 OTHER FILE SKIPPED"])
        XCTAssertEqual(judge(1, later: true).lines, ["1 IMAGE", "GOES WITH YOUR NEXT MESSAGE"])
    }

    func testRejecting() {
        XCTAssertEqual(judge(0, others: 1), ImageDropFeedback(accepts: false, title: "IMAGES ONLY", lines: []))
        XCTAssertEqual(judge(5, room: 0).title, "UP TO 4 PER MESSAGE")
        XCTAssertFalse(judge(5, room: 0).accepts)
        // The device and the conversation come first: no drop can change them.
        XCTAssertEqual(judge(0, refusal: .viewer).title, "THIS DEVICE CAN ONLY VIEW")
        XCTAssertEqual(judge(2, refusal: .readOnly).title, "READ-ONLY CONVERSATION")
        XCTAssertFalse(judge(2, refusal: .readOnly).accepts)
    }

    // MARK: AppKit's drag lookup

    final class Taps { var count = 0 }

    /// Like the chat: a scroll view with selectable text, a SwiftUI button, a text field.
    struct Column: View {
        let drop: Bool
        let taps: Taps
        @State private var text = ""

        var body: some View {
            let column = VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("selectable message text that is long enough").textSelection(.enabled).frame(height: 40)
                        Spacer(minLength: 120)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
                Button { taps.count += 1 } label: { Color.gray.frame(width: 400, height: 40) }.buttonStyle(.plain)
                TextField("Message", text: $text).padding(8).frame(height: 60)
            }
            .frame(width: 400, height: 300)
            if drop {
                column.imageDrop(room: 4, limit: 4, refusal: nil, later: false) { _, _ in }
            } else {
                column
            }
        }
    }

    private func window(drop: Bool, taps: Taps = Taps()) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Column(drop: drop, taps: taps))
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return window
    }

    /// In window coordinates (origin bottom left): the scroll view's margin, its text, its blank area, the field.
    private let points: [(String, NSPoint)] = [
        ("margin", NSPoint(x: 5, y: 260)), ("selectable text", NSPoint(x: 100, y: 260)),
        ("blank scroll area", NSPoint(x: 200, y: 140)), ("text field", NSPoint(x: 200, y: 30)),
    ]

    /// `-[NSView _hitTest:dragTypes:]`, AppKit's own lookup of a drag's destination (private: tests only).
    private func dragDestination(_ window: NSWindow, at point: NSPoint) throws -> NSView? {
        let frame = try XCTUnwrap(window.contentView?.superview)
        let selector = NSSelectorFromString("_hitTest:dragTypes:")
        guard frame.responds(to: selector) else { throw XCTSkip("AppKit no longer has _hitTest:dragTypes:") }
        typealias Lookup = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSPoint>, AnyObject) -> AnyObject?
        let lookup = unsafeBitCast(frame.method(for: selector), to: Lookup.self)
        var p = point
        return lookup(frame, selector, &p, NSSet(array: [NSPasteboard.PasteboardType.fileURL.rawValue])) as? NSView
    }

    func testDragsReachTheDropTargetEverywhere() throws {
        let plain = window(drop: false)
        // The cause (#45): without the target nothing in the column takes a file drag.
        for (name, p) in points { XCTAssertNil(try dragDestination(plain, at: p), name) }

        let window = window(drop: true)
        let frame = try XCTUnwrap(window.contentView?.superview)
        for (name, p) in points {
            XCTAssertTrue(try dragDestination(window, at: p) is ImageDropTarget.DropView, name)
            let hit = frame.hitTest(p)
            XCTAssertNotNil(hit, name)
            XCTAssertFalse(hit is ImageDropTarget.DropView, "clicks go to the views below: \(name)")
        }
    }

    func testClicksStillReachSwiftUIButtons() throws {
        func click(drop: Bool) -> Int {
            let taps = Taps()
            let window = window(drop: drop, taps: taps)
            // On screen and key, far off the visible area and without activating the app (no focus taken from the
            // user's): a window that isn't key takes a first click as activation.
            window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            window.orderFrontRegardless()
            window.makeKey()
            defer { window.orderOut(nil) }
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: 200, y: 80), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                window.sendEvent(event)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            return taps.count
        }
        guard click(drop: false) == 1 else { throw XCTSkip("synthetic clicks don't reach SwiftUI in this session") }
        XCTAssertEqual(click(drop: true), 1)
    }
}
