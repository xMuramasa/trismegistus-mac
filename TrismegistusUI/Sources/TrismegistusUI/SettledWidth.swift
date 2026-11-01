import SwiftUI

public extension View {
    /// Lays the content out at the last width that held for 150 ms, clipped or left short in between: while a pane or
    /// the sidebar animates, the column's width changes every frame, and re-wrapping every visible `Text` each frame
    /// is what made the toggles stutter (#28). The content re-wraps once, when the width settles. The first width
    /// counts at once; below `minimum` the content is laid out at `minimum` and clipped.
    ///
    /// The width is read from a `GeometryReader`, which takes the space it is offered whatever the content does. An
    /// earlier version measured its own frame, which depended on the width it set: a feedback loop that re-laid out
    /// the window every 150 ms while idle.
    func settledWidth(minimum: CGFloat = 0) -> some View { modifier(SettledWidth(minimum: minimum)) }
}

struct SettledWidth: ViewModifier {
    /// How many times any settled width changed (tests: a layout must stop changing once it settles).
    nonisolated(unsafe) static var settleCount = 0

    let minimum: CGFloat
    @State private var offered: CGFloat?
    @State private var settled: CGFloat?

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            let live = proxy.size.width
            content
                .frame(width: max(settled ?? live, minimum), height: proxy.size.height, alignment: .topLeading)
                .frame(width: live, height: proxy.size.height, alignment: .topLeading)
                .clipped()
                .onChange(of: live, initial: true) { _, width in
                    offered = width
                    if settled == nil { settle(width) }
                }
        }
        .task(id: offered) {
            guard let offered, offered != settled else { return }
            try? await Task.sleep(for: Motion.settle)
            if !Task.isCancelled { settle(offered) }
        }
    }

    private func settle(_ width: CGFloat) {
        settled = width
        Self.settleCount += 1
    }
}
