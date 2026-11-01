import SwiftUI

/// The window's sidebar as our own column (#32): macOS 26 draws a `NavigationSplitView` sidebar as a floating glass
/// panel with a white list; the draft has one flat `sunken` column from under the toolbar to the bottom, a 1 pt rule,
/// then the detail. The toolbar's steel strip runs above both from the window's left edge. Showing and hiding follows
/// the caller's animation (the column slides out to the left; the detail's width animates, so its content wants
/// `settledWidth`). Dragging the rule sets `width`, kept within 220-340 pt.
public struct SidebarSplit<Sidebar: View, Detail: View>: View {
    @Binding var isShown: Bool
    @Binding var width: Double
    let sidebar: Sidebar
    let detail: Detail
    @State private var dragStart: Double?

    static var widths: ClosedRange<Double> { 220...340 }

    public init(
        isShown: Binding<Bool>, width: Binding<Double>, @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self._isShown = isShown
        self._width = width
        self.sidebar = sidebar()
        self.detail = detail()
    }

    public var body: some View {
        HStack(spacing: 0) {
            if isShown {
                HStack(spacing: 0) {
                    sidebar
                        .environment(\.sunkenRows, true)
                        .frame(width: min(max(width, Self.widths.lowerBound), Self.widths.upperBound))
                        // Not into the top safe area: the toolbar's strip stays steel above the column.
                        .background(Theme.sunken, ignoresSafeAreaEdges: [])
                    divider
                }
                .transition(.move(edge: .leading))
                // The divider's grip reaches over the detail's edge.
                .zIndex(1)
            }
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.rule).frame(width: 1)
            .overlay {
                Color.clear.frame(width: 7).contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        // Global: the divider moves under the pointer, so a local translation would feed back.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = dragStart ?? width
                                dragStart = start
                                width = min(max(start + drag.translation.width, Self.widths.lowerBound), Self.widths.upperBound)
                            }
                            .onEnded { _ in dragStart = nil })
            }
            .accessibilityHidden(true)
    }
}
