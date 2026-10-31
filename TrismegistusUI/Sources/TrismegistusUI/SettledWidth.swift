import SwiftUI

public extension View {
    /// Lays the content out at the last width that held for 150 ms, clipped or left short in between: while a pane or
    /// the sidebar animates, the column's width changes every frame, and re-wrapping every visible `Text` each frame
    /// is what made the toggles stutter (#28). The content re-wraps once, when the width settles. The first width
    /// counts at once; below `minimum` the content is laid out at `minimum` and clipped.
    func settledWidth(minimum: CGFloat = 0) -> some View { modifier(SettledWidth(minimum: minimum)) }
}

private struct SettledWidth: ViewModifier {
    let minimum: CGFloat
    @State private var width: CGFloat?
    @State private var settled: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(width: (settled ?? width).map { max($0, minimum) })
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { new in
                width = new
                if settled == nil { settled = new }
            }
            .task(id: width) {
                guard width != settled else { return }
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { settled = width }
            }
    }
}
