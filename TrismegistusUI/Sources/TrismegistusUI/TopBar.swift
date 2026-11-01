import AppKit
import SwiftUI

public extension EnvironmentValues {
    /// True on the window's top bar: content there draws light on steel (`Theme.onSteel`).
    @Entry var onSteel = false
}

extension EnvironmentValues {
    /// The window's width, for `TopBarBackdrop`.
    @Entry var topBarWidth: CGFloat = 0
}

public extension View {
    /// The window's top bar, on the window's root: hides the toolbar's own background (glass and scroll edge on macOS
    /// 26) and draws the steel strip behind the toolbar instead, with a 1 pt rule under it. A `TopBarBackdrop` right
    /// below the toolbar (the conversation header) continues the strip and covers the rule with its own.
    func topBar() -> some View { modifier(TopBar()) }
}

struct TopBar: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                // Inside the safe area, the reader's top inset is the toolbar's height.
                GeometryReader { proxy in
                    TopBarBackdrop()
                        .frame(height: proxy.safeAreaInsets.top)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.steelRule).frame(height: 1) }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()
                        .onChange(of: proxy.size.width, initial: true) { _, w in width = w }
                }
                .background(TransparentTitlebar())
            }
            .environment(\.topBarWidth, width)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}

/// On macOS 26 `toolbarBackgroundVisibility(.hidden)` leaves each column's hard scroll pocket (an opaque material and a
/// hairline) under the toolbar, which hides the strip (seen in `TopBarTests`); a transparent titlebar drops them.
private struct TransparentTitlebar: NSViewRepresentable {
    final class Probe: NSView {
        override func viewDidMoveToWindow() { window?.titlebarAppearsTransparent = true }
    }

    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) {}
}

public extension View {
    /// Continues the top bar across a column that draws its own top over the window's strip (the floating sidebar
    /// panel, the inspector): the strip and its rule in the column's top safe area, over the column's background and
    /// under the toolbar's items. It takes no clicks, so the toolbar and window dragging work as before.
    func topBarColumn(_ anchor: TopBarBackdrop.Anchor) -> some View { topBarColumn(anchor) { EmptyView() } }

    /// The same, with a label on the strip at the column's leading edge, in `onSteel` (the terminal pane's title).
    func topBarColumn<Label: View>(_ anchor: TopBarBackdrop.Anchor, @ViewBuilder label: () -> Label) -> some View {
        let label = label()
        return overlay(alignment: .top) {
            GeometryReader { proxy in
                TopBarBackdrop(anchor)
                    .frame(height: proxy.safeAreaInsets.top)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.steelRule).frame(height: 1) }
                    .overlay(alignment: .leading) {
                        label.foregroundStyle(Theme.onSteel).environment(\.onSteel, true).padding(.horizontal, 16)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
            .allowsHitTesting(false)
        }
    }
}

/// The strip's left-to-right gradient as it falls under this view. The gradient is window-wide; while panes move only
/// its offset changes (#28).
public struct TopBarBackdrop: View {
    /// Where the window-wide gradient is pinned.
    public enum Anchor: Sendable {
        /// At minus the view's global origin (like `EndfieldBackdrop`), for views in the detail column: a part below the
        /// toolbar continues the toolbar's part whatever the sidebar width.
        case window
        /// The gradient's left end at the view's left edge: a column on the window's left (the sidebar).
        case leadingEdge
        /// The gradient's right end at the view's right edge: a column on the window's right (the inspector). Each
        /// column may be hosted in its own view, so its global origin can't be trusted there.
        case trailingEdge
    }

    @Environment(\.topBarWidth) private var width
    private let anchor: Anchor

    public init(_ anchor: Anchor = .window) { self.anchor = anchor }

    public var body: some View {
        GeometryReader { proxy in
            let full = max(width, proxy.size.width)
            LinearGradient(colors: [Theme.steel, Theme.steelDeep, Theme.steelEnd], startPoint: .leading, endPoint: .trailing)
                .frame(width: full, height: proxy.size.height)
                .offset(x: offset(proxy, full))
        }
        .clipped()
    }

    private func offset(_ proxy: GeometryProxy, _ full: CGFloat) -> CGFloat {
        switch anchor {
        case .window: -proxy.frame(in: .global).minX
        case .leadingEdge: 0
        case .trailingEdge: proxy.size.width - full
        }
    }
}
