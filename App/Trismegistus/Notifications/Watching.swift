import AppKit
import SwiftUI

extension View {
    /// Tells the model which conversation this place shows (nil: none) and in which window, for the run alerts (#66):
    /// what is in view gets no mark and no run sound, and its mark goes.
    func shows(_ session: String?, in place: AppModel.Viewer) -> some View {
        modifier(ShowsConversation(session: session, place: place))
    }
}

private struct ShowsConversation: ViewModifier {
    let session: String?
    let place: AppModel.Viewer
    @Environment(AppModel.self) private var model
    @State private var window = WindowBox()

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window.window = $0; report() })
            .onChange(of: session, initial: true) { report() }
            .onDisappear { model.show(nil, in: place, window: nil) }
    }

    private func report() {
        model.show(session, in: place, window: window.window)
    }
}

/// Weak, so the state doesn't keep a closed window.
private final class WindowBox {
    weak var window: NSWindow?
}

/// Reports the window its view lands in.
private struct WindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView { Reader(onWindow: onWindow) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Reader: NSView {
        let onWindow: (NSWindow?) -> Void

        init(onWindow: @escaping (NSWindow?) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow(window)
        }
    }
}
