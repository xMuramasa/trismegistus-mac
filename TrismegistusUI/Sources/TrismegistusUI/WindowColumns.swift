import SwiftUI

/// The window's three columns (#68, design 13 #a2): the floating section panel, 8 pt in from the window's top, left and
/// bottom (and 8 pt from the list); the list column on paper with a 1 pt rule at its right; the detail. Hiding the panel
/// follows the caller's animation (it slides out to the left) and leaves list + detail. Dragging the rule sets
/// `listWidth`, kept within `Size.listColumn`; the list gives way to keep the detail `detailMin` wide, so at a 1180 pt
/// window it is 380. The list sees `onSidebar` (its rows are the B2 cards).
public struct WindowColumns<Panel: View, List: View, Detail: View>: View {
    @Binding var isPanelShown: Bool
    @Binding var listWidth: Double
    let panel: Panel
    let list: List
    let detail: Detail
    @State private var dragStart: Double?

    public init(
        isPanelShown: Binding<Bool>, listWidth: Binding<Double>, @ViewBuilder panel: () -> Panel,
        @ViewBuilder list: () -> List, @ViewBuilder detail: () -> Detail
    ) {
        self._isPanelShown = isPanelShown
        self._listWidth = listWidth
        self.panel = panel()
        self.list = list()
        self.detail = detail()
    }

    /// The list's width with `available` for list and detail: the stored width within its range, less what the detail
    /// needs, never under the minimum.
    static func listWidth(_ stored: Double, available: Double) -> Double {
        let kept = min(max(stored, Size.listColumn.min), Size.listColumn.max)
        return max(Size.listColumn.min, min(kept, available - Size.listColumn.detailMin))
    }

    public var body: some View {
        HStack(spacing: 0) {
            if isPanelShown {
                panel
                    .frame(width: Size.sectionPanel.width)
                    .frame(maxHeight: .infinity)
                    .padding(Space.s)
                    .transition(.move(edge: .leading))
                    // Its shadow lies over the list.
                    .zIndex(1)
            }
            GeometryReader { proxy in
                let width = Self.listWidth(listWidth, available: proxy.size.width)
                HStack(spacing: 0) {
                    list
                        .environment(\.onSidebar, true)
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .trailing) { divider(width) }
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private func divider(_ shown: Double) -> some View {
        Rectangle().fill(Ink.line.rule).frame(width: Stroke.hairline)
            .overlay {
                Color.clear.frame(width: Size.grip).contentShape(Rectangle())
                    .pointerStyle(.columnResize)
                    .gesture(
                        // Global: the rule moves under the pointer, so a local translation would feed back.
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = dragStart ?? shown
                                dragStart = start
                                listWidth = min(max(start + drag.translation.width, Size.listColumn.min), Size.listColumn.max)
                            }
                            .onEnded { _ in dragStart = nil })
            }
            .accessibilityHidden(true)
    }
}
