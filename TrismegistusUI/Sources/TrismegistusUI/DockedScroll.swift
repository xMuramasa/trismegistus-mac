import SwiftUI

/// A chat's scroll view, bottom-anchored, with a dock (the composer block) laid over its bottom edge (#52).
/// The messages end `dock`'s height higher, so the last one sits just above it.
///
/// The dock goes over the scroll view, not under it: a composer that grew a line at a time under the scroll view shrank
/// it each time, the `LazyVStack` re-estimated its height, and the bottom anchor landed where no rows were laid out (a
/// blank chat until a scroll) or fell behind. Here the scroll view's frame never changes; a dock height change is a
/// content-size change at the end, the path a new message takes. `ChatScrollTests` holds it.
///
/// `reveal` (#76, ⌘F's current match): the row with that id scrolls to the middle each time it changes.
public struct DockedScroll<Content: View, Dock: View>: View {
    let content: Content
    let dock: Dock
    let reveal: String?
    @State private var dockHeight: CGFloat = 0

    public init(reveal: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder dock: () -> Dock) {
        self.reveal = reveal
        self.content = content()
        self.dock = dock()
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content.padding(.bottom, dockHeight)
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
        .overlay(alignment: .bottom) {
            dock.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dockHeight = $0 }
        }
    }
}
