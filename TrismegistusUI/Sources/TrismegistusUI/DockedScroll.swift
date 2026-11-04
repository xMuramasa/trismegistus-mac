import SwiftUI

/// A chat's scroll view, bottom-anchored, with a dock (the composer block) laid over its bottom edge (#52).
/// The messages end `dock`'s height higher, so the last one sits just above it.
///
/// The dock goes over the scroll view, not under it: a composer that grew a line at a time under the scroll view shrank
/// it each time, the `LazyVStack` re-estimated its height, and the bottom anchor landed where no rows were laid out (a
/// blank chat until a scroll) or fell behind. Here the scroll view's frame never changes; a dock height change is a
/// content-size change at the end, the path a new message takes. `ChatScrollTests` holds it.
public struct DockedScroll<Content: View, Dock: View>: View {
    let content: Content
    let dock: Dock
    @State private var dockHeight: CGFloat = 0

    public init(@ViewBuilder content: () -> Content, @ViewBuilder dock: () -> Dock) {
        self.content = content()
        self.dock = dock()
    }

    public var body: some View {
        ScrollView {
            content.padding(.bottom, dockHeight)
        }
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .settledWidth()
        .overlay(alignment: .bottom) {
            dock.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { dockHeight = $0 }
        }
    }
}
