import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The images on a pasteboard (a drag or the clipboard): image files, and image data on items with no file (a browser's
/// image, a screenshot's thumbnail). Files that are not images (a PDF, a folder) are only counted.
public struct PasteboardImages {
    public let files: [URL]
    /// Files that are not images.
    public let others: Int
    /// Items with image data and no file, with the type to read.
    private let items: [(NSPasteboardItem, NSPasteboard.PasteboardType)]

    public var count: Int { files.count + items.count }

    public init(_ board: NSPasteboard) {
        // Read as NSURL: that also takes the sandbox's grant for dragged files.
        let all = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        files = board.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL] ?? []
        others = all.count - files.count
        items = (board.pasteboardItems ?? []).compactMap { item in
            guard !item.types.contains(.fileURL),
                let type = item.types.first(where: { UTType($0.rawValue)?.conforms(to: .image) == true })
            else { return nil }
            return (item, type)
        }
    }

    /// The bytes of the image data items; read a drag's before its drop returns.
    public func data() -> [Data] { items.compactMap { $0.0.data(forType: $0.1) } }

    /// What a drop target registers: files and image data, never text (a dragged string still reaches the text field).
    static let dragTypes: [NSPasteboard.PasteboardType] =
        [.fileURL] + NSImage.imageTypes.filter { UTType($0)?.conforms(to: .image) == true }.map { .init($0) }
}

/// What the chat shows while a drag is over it.
public struct ImageDropFeedback: Equatable, Sendable {
    /// Why the chat takes no images at all.
    public enum Refusal: Sendable { case viewer, readOnly }

    public let accepts: Bool
    /// On the chip: DROP TO ATTACH, or why not.
    public let title: String
    /// Mono lines under it: how many fit, what is skipped, when they go.
    public let lines: [String]

    /// `room`: free places in the tray, of `limit`; `later`: a run is active, the images wait for the next message.
    public static func judge(images: Int, others: Int, room: Int, limit: Int, refusal: Refusal?, later: Bool) -> Self {
        func reject(_ title: String) -> Self { Self(accepts: false, title: title, lines: []) }
        switch refusal {
        case .viewer: return reject("THIS DEVICE CAN ONLY VIEW")
        case .readOnly: return reject("READ-ONLY CONVERSATION")
        case nil: break
        }
        guard images > 0 else { return reject("IMAGES ONLY") }
        guard room > 0 else { return reject("UP TO \(limit) PER MESSAGE") }
        var lines = [images <= room ? "\(images) \(images == 1 ? "IMAGE" : "IMAGES")" : "\(room) OF \(images) FIT // UP TO \(limit)"]
        if others > 0 { lines.append("\(others) OTHER \(others == 1 ? "FILE" : "FILES") SKIPPED") }
        if later { lines.append("GOES WITH YOUR NEXT MESSAGE") }
        return Self(accepts: true, title: "DROP TO ATTACH", lines: lines)
    }
}

extension View {
    /// Takes images dropped anywhere on this view and shows what a drop would do while they are dragged over it (#45).
    /// `perform` gets the image files and the image data of a drop (more than `room` is left to the caller).
    public func imageDrop(
        room: Int, limit: Int, refusal: ImageDropFeedback.Refusal?, later: Bool,
        perform: @escaping @MainActor (_ files: [URL], _ data: [Data]) -> Void
    ) -> some View {
        modifier(ImageDropModifier(room: room, limit: limit, refusal: refusal, later: later, perform: perform))
    }
}

struct ImageDropModifier: ViewModifier {
    let room: Int
    let limit: Int
    let refusal: ImageDropFeedback.Refusal?
    let later: Bool
    let perform: @MainActor ([URL], [Data]) -> Void
    @State private var feedback: ImageDropFeedback?

    func body(content: Content) -> some View {
        content
            .overlay {
                ImageDropTarget(feedback: $feedback) {
                    .judge(images: $0.count, others: $0.others, room: room, limit: limit, refusal: refusal, later: later)
                } perform: { perform($0.files, $0.data()) }
            }
            .overlay {
                ZStack {
                    if let feedback { ImageDropOverlay(feedback).transition(.opacity) }
                }
                .animation(feedback == nil ? Motion.dropOut : Motion.dropIn, value: feedback)
            }
    }
}

/// An AppKit drop target over a SwiftUI view. SwiftUI's `onDrop` sits behind the platform views it wraps (the scroll
/// view, selectable text, the text field), and AppKit picks a drag's destination by geometry from the front, so it
/// never reached the chat (#45). This view lies on top, registered for files and image data, and lets every click
/// through (`hitTest` is nil).
struct ImageDropTarget: NSViewRepresentable {
    @Binding var feedback: ImageDropFeedback?
    let judge: @MainActor (PasteboardImages) -> ImageDropFeedback
    let perform: @MainActor (PasteboardImages) -> Void

    func makeNSView(context: Context) -> DropView { DropView() }

    func updateNSView(_ view: DropView, context: Context) { view.target = self }

    final class DropView: NSView {
        var target: ImageDropTarget?
        /// The drag over the view, classified once on entry.
        private var images: PasteboardImages?

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes(PasteboardImages.dragTypes)
        }

        required init?(coder: NSCoder) { return nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            images = PasteboardImages(sender.draggingPasteboard)
            return draggingUpdated(sender)
        }

        /// Judged again on each move: the tray or the run may change during a drag. No operation: no ＋ on the cursor.
        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard let target, let images else { return [] }
            let feedback = target.judge(images)
            if target.feedback != feedback { target.feedback = feedback }
            return feedback.accepts ? .copy : []
        }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            guard let target, let images, target.judge(images).accepts else { return false }
            target.perform(images)
            return true
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) { end() }
        override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) { end() }
        override func draggingEnded(_ sender: any NSDraggingInfo) { end() }

        private func end() {
            images = nil
            if target?.feedback != nil { target?.feedback = nil }
        }
    }
}

/// The chat while a drag is over it: the column under a paper veil, a frame inset `Space.s` whose corner brackets
/// slide out from the centre, and a card saying what a drop does, yellow when it attaches and red when it can't.
/// Reduce Motion: no slide or scale, only the fade. Takes no clicks.
public struct ImageDropOverlay: View {
    let feedback: ImageDropFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The frame open and the card at full size.
    @State private var open: Bool

    public init(_ feedback: ImageDropFeedback) { self.init(feedback, open: false) }

    /// `open`: start opened (snapshots, which don't run `onAppear`).
    init(_ feedback: ImageDropFeedback, open: Bool) {
        self.feedback = feedback
        _open = State(initialValue: open)
    }

    public var body: some View {
        let tint = feedback.accepts ? Ink.selection : Ink.status.error
        ZStack {
            Ink.surface.window.opacity(Opacity.dropVeil)
            DropFrame(progress: open ? 1 : 0).stroke(tint, lineWidth: Stroke.accent).padding(Space.s)
            DropFrame(progress: open ? 1 : 0, brackets: true).stroke(tint, lineWidth: Stroke.rule).padding(Space.s)
            card(tint)
                .scaleEffect(open ? 1 : 0.96)
                .opacity(open ? 1 : 0)
        }
        .allowsHitTesting(false)
        .onAppear {
            if reduceMotion { open = true } else { withAnimation(Motion.dropIn) { open = true } }
        }
    }

    private func card(_ tint: Color) -> some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: feedback.accepts ? Symbol.attach : Symbol.close)
                Text(feedback.title).typeRole(.label)
            }
            .foregroundStyle(feedback.accepts ? Ink.selection : Ink.text.onDark)
            .padding(.vertical, Space.s).padding(.horizontal, Space.m)
            .background(feedback.accepts ? Ink.surface.inverse : Ink.status.error)
            ForEach(feedback.lines, id: \.self) {
                Text($0).typeRole(.mono).foregroundStyle(Ink.text.primary)
            }
        }
        .padding(Space.l)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(tint, lineWidth: Stroke.hairline))
        .shadow(Shadow.panel)
        .accessibilityElement(children: .combine)
    }
}

/// The drop frame grown from the centre by `progress`: its rectangle, or only its corner brackets.
struct DropFrame: Shape {
    var progress: CGFloat
    var brackets = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: rect.width * (1 - progress) / 2, dy: rect.height * (1 - progress) / 2)
        guard brackets else { return Path(r) }
        let arm = min(Size.dropBracket, r.width / 2, r.height / 2)
        var path = Path()
        for (x, y, dx, dy) in [(r.minX, r.minY, arm, arm), (r.maxX, r.minY, -arm, arm), (r.minX, r.maxY, arm, -arm), (r.maxX, r.maxY, -arm, -arm)] {
            path.move(to: CGPoint(x: x + dx, y: y))
            path.addLine(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x, y: y + dy))
        }
        return path
    }
}
