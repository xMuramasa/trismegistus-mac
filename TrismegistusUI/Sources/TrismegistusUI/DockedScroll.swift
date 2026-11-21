import AppKit
import SwiftUI

/// A chat's scroll view, bottom-anchored, with a dock (the composer block) laid over its bottom edge (#52) and what
/// sits above the messages (the find bar, an approval banner) laid over its top edge. The messages start `top`'s height
/// lower and end `dock`'s height higher.
///
/// Both go over the scroll view, not beside it: anything that changes the scroll view's own height (a composer growing
/// a line at a time under it, a banner appearing above it) makes the `LazyVStack` re-estimate its height, and the
/// bottom anchor lands where no rows are laid out (a blank chat until a scroll) or falls behind, further with each new
/// message. Here the scroll view's frame never changes; a dock or top height change is a content-size change, which
/// the bottom anchor follows, and `BottomPin` holds the bottom where SwiftUI's anchor lets go. The rows go in a
/// `TailStack`. `ChatScrollTests` holds all of it.
///
/// `reveal` (#76, ⌘F's current match): the row with that id scrolls to the middle each time it changes.
public struct DockedScroll<Content: View, Top: View, Dock: View>: View {
    let content: Content
    let top: Top
    let dock: Dock
    let reveal: String?
    @State private var topHeight: CGFloat = 0
    @State private var dockHeight: CGFloat = 0

    public init(
        reveal: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder top: () -> Top,
        @ViewBuilder dock: () -> Dock
    ) {
        self.reveal = reveal
        self.content = content()
        self.top = top()
        self.dock = dock()
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content.padding(.top, topHeight).padding(.bottom, dockHeight)
                    .background(BottomPin())
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .onChange(of: reveal, initial: true) { _, id in
                // shortcut: the row comes to the middle, not the match within it: a match deep in a long answer may sit
                // past the fold. Upgrade to the match's own frame if that bothers.
                if let id { withAnimation(Motion.panel) { proxy.scrollTo(id, anchor: .center) } }
            }
        }
        .settledWidth()
        .overlay(alignment: .top) {
            // In a stack at its own height: an empty `top` measures 0, not the overlay's whole height.
            VStack(spacing: 0) { top }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topHeight = $0 }
        }
        .overlay(alignment: .bottom) {
            dock.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dockHeight = $0 }
        }
    }
}

extension DockedScroll where Top == EmptyView {
    public init(reveal: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder dock: () -> Dock) {
        self.init(reveal: reveal, content: content, top: { EmptyView() }, dock: dock)
    }
}

/// Where a chat's rows split between `TailStack`'s lazy head and its tail laid out in full.
public enum ChatTail {
    /// At least this many newest rows are in the tail: more than a window shows even when they are one-line chips.
    public static let minimum = 40

    /// The first row of the tail.
    public static func split(_ count: Int) -> Int { max(0, count - minimum) }
}

/// A chat's rows: the newest (from `ChatTail.split`) laid out in full under a lazy stack of the older ones.
///
/// All lazy, a conversation whose rows differ a lot in height (one-line tool chips, then a long code answer or an
/// image) got an estimated height far off the real one, and the bottom anchor landed in the estimate, where no rows
/// were laid out: the chat went blank, with a long empty scroll, after a switch or as its history arrived, until a
/// scroll (Martin, 2026-11-21). The tail's rows are always laid out at their real height, so the bottom shows them;
/// only scrolling up into the older rows meets the lazy stack's estimates. `ChatScrollTests` holds it.
public struct TailStack<Head: View, Tail: View>: View {
    let spacing: CGFloat
    let head: Head
    let tail: Tail
    @State private var hasHead = false

    public init(spacing: CGFloat, @ViewBuilder head: () -> Head, @ViewBuilder tail: () -> Tail) {
        self.spacing = spacing
        self.head = head()
        self.tail = tail()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: spacing) { head }
                .onGeometryChange(for: Bool.self) { $0.size.height > 0 } action: { hasHead = $0 }
            // The gap between the head's last row and the tail's first, as the one stack had.
            VStack(alignment: .leading, spacing: spacing) { tail }
                .padding(.top, hasHead ? spacing : 0)
        }
    }
}

/// Keeps a scroll view that was at the bottom at the bottom when its document's height changes. SwiftUI's bottom
/// anchor (`defaultScrollAnchor(.bottom, for: .sizeChanges)`) sometimes keeps the offset instead when a lazy stack
/// re-estimates its height in the same pass as another change (a composer line, a new message): the chat then sat
/// thousands of points above the bottom, further with each message. Measured from AppKit after layout, so it holds
/// whatever SwiftUI did. Scrolled up (by the user, or ⌘F revealing a match), it leaves the position alone.
struct BottomPin: NSViewRepresentable {
    func makeNSView(context: Context) -> PinView { PinView() }
    func updateNSView(_ view: PinView, context: Context) {}

    final class PinView: NSView {
        private var observers: [NSObjectProtocol] = []
        private weak var scroll: NSScrollView?
        private var atBottom = true
        private var pinning = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard window != nil, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            self.scroll = scroll
            scroll.contentView.postsBoundsChangedNotifications = true
            document.postsFrameChangedNotifications = true
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scrolled() }
            })
            observers.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: document, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resized() }
            })
            atBottom = Self.isAtBottom(scroll)
        }

        override func removeFromSuperview() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            super.removeFromSuperview()
        }

        static func isAtBottom(_ scroll: NSScrollView) -> Bool {
            guard let document = scroll.documentView else { return true }
            return scroll.documentVisibleRect.maxY >= document.frame.height - 2
        }

        private func scrolled() {
            guard !pinning, let scroll else { return }
            atBottom = Self.isAtBottom(scroll)
        }

        private func resized() {
            guard atBottom, let scroll, let document = scroll.documentView, !Self.isAtBottom(scroll) else { return }
            pinning = true
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, document.frame.height - clip.bounds.height)))
            scroll.reflectScrolledClipView(clip)
            pinning = false
        }
    }
}
