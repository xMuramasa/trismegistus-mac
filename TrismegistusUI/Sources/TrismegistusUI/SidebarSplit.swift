import SwiftUI

/// The window's sidebar as our own column (#32): macOS 26 draws a `NavigationSplitView` sidebar as a floating glass
/// panel with a white list; the draft has one flat column (`surface.sidebar`, grey since #41) from under the toolbar to the bottom, a 1 pt rule,
/// then the detail. The toolbar's steel strip runs above both from the window's left edge. Showing and hiding follows
/// the caller's animation (the column slides out to the left; the detail's width animates, so its content wants
/// `settledWidth`). Dragging the rule sets `width`, kept within 220-340 pt.
/// How the sidebar shows and hides (Martin: ease in and out): `Motion.panel`, under its old name for App/.
public enum SidebarMotion {
    public static let animation = Motion.panel
}

public struct SidebarSplit<Sidebar: View, Detail: View>: View {
    @Binding var isShown: Bool
    @Binding var width: Double
    let sidebar: Sidebar
    let detail: Detail
    @State private var dragStart: Double?

    static var widths: ClosedRange<Double> { Size.sidebar.min...Size.sidebar.max }

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
                    let column = min(max(width, Self.widths.lowerBound), Self.widths.upperBound)
                    sidebar
                        .environment(\.onSidebar, true)
                        .environment(\.sidebarNarrow, column < Size.sidebar.default)
                        .frame(width: column)
                        // Not into the top safe area: the toolbar's strip stays steel above the column.
                        .background(Ink.surface.sidebar, ignoresSafeAreaEdges: [])
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
        Rectangle().fill(Ink.line.rule).frame(width: 1)
            .overlay {
                Color.clear.frame(width: Size.grip).contentShape(Rectangle())
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

/// The terminal as our own trailing column (Martin, 2026-11-01): with the system `.inspector` macOS ends the
/// toolbar's trailing items before the inspector, mid-window; with our own column they sit at the window's right edge.
/// `content`, a 1 pt rule with a drag grip, then `pane` at `width` (kept within 280-560 pt). Showing and hiding
/// follows the caller's animation (`SidebarMotion.animation`): the pane slides in from the right. Unlike the system
/// inspector it renders offscreen, so window tests see it.
public struct TrailingSplit<Content: View, Pane: View>: View {
    @Binding var isShown: Bool
    @Binding var width: Double
    let content: Content
    let pane: Pane
    @State private var dragStart: Double?

    static var widths: ClosedRange<Double> { Size.terminal.min...Size.terminal.max }

    public init(
        isShown: Binding<Bool>, width: Binding<Double>, @ViewBuilder content: () -> Content,
        @ViewBuilder pane: () -> Pane
    ) {
        self._isShown = isShown
        self._width = width
        self.content = content()
        self.pane = pane()
    }

    public var body: some View {
        HStack(spacing: 0) {
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            if isShown {
                HStack(spacing: 0) {
                    divider
                    pane.frame(width: min(max(width, Self.widths.lowerBound), Self.widths.upperBound))
                }
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(Ink.line.rule).frame(width: 1)
            .overlay {
                Color.clear.frame(width: Size.grip).contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        // Dragging left widens the pane. Global: the divider moves under the pointer.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = dragStart ?? width
                                dragStart = start
                                width = min(max(start - drag.translation.width, Self.widths.lowerBound), Self.widths.upperBound)
                            }
                            .onEnded { _ in dragStart = nil })
            }
            .accessibilityHidden(true)
    }
}
