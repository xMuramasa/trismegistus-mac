import AppKit
import QuickLook
import SwiftUI
import TrismegistusKit
import TrismegistusUI
import UniformTypeIdentifiers

/// The composer's images per conversation, before they are sent: added by drop, the 📎 panel or ⌘V, prepared off the
/// main actor (`ImagePreparation`), at most `ImageUpload.maxPerMessage` and `maxMessageBytes` together.
@MainActor @Observable
final class ImageTray {
    struct Item: Identifiable {
        let id = UUID()
        var thumbnail: NSImage?
        var upload: ImageUpload?
        var error: String?
    }

    private(set) var items: [String: [Item]] = [:]
    /// Set when an image didn't fit (more than four); cleared by the next change.
    private(set) var notice: String?

    func uploads(_ session: String) -> [ImageUpload] { items[session, default: []].compactMap(\.upload) }
    func isPreparing(_ session: String) -> Bool { items[session, default: []].contains { $0.upload == nil && $0.error == nil } }

    /// Empties the tray and hands over what is ready to send.
    func take(_ session: String) -> [ImageUpload] {
        defer { items[session] = nil; notice = nil }
        return uploads(session)
    }

    func remove(_ id: UUID, from session: String) {
        items[session]?.removeAll { $0.id == id }
        notice = nil
    }

    /// nil data: the item was not an image file at all.
    func add(_ data: Data?, to session: String) {
        guard items[session, default: []].count < ImageUpload.maxPerMessage else {
            notice = "Up to \(ImageUpload.maxPerMessage) images per message."
            return
        }
        notice = nil
        let item = Item()
        items[session, default: []].append(item)
        guard let data else { return update(item.id, in: session) { $0.error = ImagePreparation.Failure.notAnImage.message } }
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ImageUpload, ImagePreparation.Failure> in
                do { return .success(try ImagePreparation.prepare(data)) } catch { return .failure(error as? ImagePreparation.Failure ?? .notAnImage) }
            }.value
            let others = uploads(session).reduce(0) { $0 + $1.data.count }
            update(item.id, in: session) { item in
                switch result {
                case .success(let upload):
                    if others + upload.data.count > ImageUpload.maxMessageBytes {
                        item.error = ImagePreparation.Failure.tooLarge.message
                    } else {
                        item.upload = upload
                        item.thumbnail = NSImage(data: upload.data)
                    }
                case .failure(let failure):
                    item.error = failure.message
                }
            }
        }
    }

    /// Image files (from Finder, the 📎 panel) and image data (a browser's image, a screenshot), in that order.
    func add(_ files: [URL], _ data: [Data] = [], to session: String) {
        for url in files { add(try? Data(contentsOf: url), to: session) }
        for data in data { add(data, to: session) }
    }

    /// ⌘V: image files copied in Finder, or image data with no text beside it (a screenshot, a browser's Copy Image).
    /// False leaves the paste to the text field.
    func paste(to session: String) -> Bool {
        let board = NSPasteboard.general
        let images = PasteboardImages(board)
        if !images.files.isEmpty {
            add(images.files, to: session)
            return true
        }
        guard images.count > 0, board.string(forType: .string) == nil else { return false }
        add([], images.data(), to: session)
        return true
    }

    /// The 📎 button.
    func choose(for session: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Up to \(ImageUpload.maxPerMessage) images"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        add(panel.urls, to: session)
    }

    private func update(_ id: UUID, in session: String, _ change: (inout Item) -> Void) {
        guard let i = items[session]?.firstIndex(where: { $0.id == id }) else { return }
        change(&items[session]![i])
    }
}

/// ⌘V in the view's own window while `onPaste` takes the clipboard (it answers false to leave it to the text field).
/// A local key monitor: a text field's own paste ignores images, so SwiftUI's paste command never sees them.
struct PasteCatcher: NSViewRepresentable {
    let onPaste: @MainActor () -> Bool

    func makeNSView(context: Context) -> CatcherView { CatcherView() }

    func updateNSView(_ view: CatcherView, context: Context) { view.onPaste = onPaste }

    final class CatcherView: NSView {
        var onPaste: @MainActor () -> Bool = { false }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let consumed = MainActor.assumeIsolated {
                    guard let self, event.window === self.window,
                        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                        event.charactersIgnoringModifiers == "v"
                    else { return false }
                    return self.onPaste()
                }
                return consumed ? nil : event
            }
        }
    }
}

/// What a message's image comes from.
enum MessageImage: Hashable {
    case chat(ChatImage)
    /// The outbox's own bytes.
    case upload(ImageUpload)
}

/// A message's images (`ChatImageGrid`), loaded from the disk cache or the relay; a click opens the file in Quick Look.
struct MessageImages: View {
    let sessionID: String
    let images: [MessageImage]

    @Environment(AppModel.self) private var model
    @State private var files: [MessageImage: URL] = [:]
    @State private var pictures: [MessageImage: NSImage] = [:]
    @State private var failed: Set<MessageImage> = []
    @State private var preview: URL?

    var body: some View {
        ChatImageGrid(cells: images.enumerated().map { i, image in
            ChatImageGrid.Cell(id: String(i), image: pictures[image], pixelSize: pixelSize(image), caption: failed.contains(image) ? caption(image) : nil)
        }) { id in
            guard let i = Int(id), i < images.count else { return }
            Task { preview = await file(images[i]) }
        }
        .task(id: images) {
            for image in images where pictures[image] == nil {
                if case .upload(let upload) = image {
                    pictures[image] = NSImage(data: upload.data)
                } else if let url = await file(image), let picture = NSImage(contentsOf: url) {
                    pictures[image] = picture
                } else {
                    failed.insert(image)
                }
            }
        }
        .quickLookPreview($preview)
    }

    private func file(_ image: MessageImage) async -> URL? {
        if let url = files[image] { return url }
        guard let cache = model.store?.images else { return nil }
        let url: URL? = switch image {
        case .chat(.attachment(let ref)): await cache.attachment(ref)
        case .chat(.media(let path)): await cache.media(session: sessionID, path: path)
        case .upload(let upload): await cache.scratch(upload.data, mime: upload.mime)
        }
        files[image] = url
        return url
    }

    private func pixelSize(_ image: MessageImage) -> CGSize? {
        switch image {
        case .chat(.attachment(let ref)): CGSize(width: ref.width, height: ref.height)
        case .upload(let upload): CGSize(width: upload.width, height: upload.height)
        case .chat(.media): nil
        }
    }

    private func caption(_ image: MessageImage) -> String {
        if case .chat(.media(let path)) = image { return (path as NSString).lastPathComponent }
        return "Image unavailable"
    }
}
