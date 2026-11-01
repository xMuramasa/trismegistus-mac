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

/// The strip's left-to-right gradient as it falls under this view. The gradient is window-wide and placed at minus the
/// view's global origin (like `EndfieldBackdrop`), so a part below the toolbar continues the toolbar's part whatever
/// the sidebar width; while panes move only the offset changes (#28).
public struct TopBarBackdrop: View {
    @Environment(\.topBarWidth) private var width

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [Theme.steel, Theme.steelDeep, Theme.steelEnd], startPoint: .leading, endPoint: .trailing)
                .frame(width: max(width, proxy.size.width), height: proxy.size.height)
                .offset(x: -proxy.frame(in: .global).minX)
        }
        .clipped()
    }
}
