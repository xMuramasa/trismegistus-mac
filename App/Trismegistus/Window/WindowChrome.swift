import AppKit
import SwiftUI
import TrismegistusUI

/// Puts the window's close, minimise and zoom buttons where the design has them (#68): inside the section panel's top
/// row, or over the list header's leading corner while the panel is hidden. The window has a hidden, transparent title
/// bar (`App.swift`); AppKit keeps the buttons in its title bar view and lays that out again on a resize, a key change
/// or full screen, so they are placed again after each.
/// shortcut: moves AppKit's own buttons and grows their bar; if a macOS update fights it (the buttons jump back to the
/// corner), the fallback is the system position with the panel's top row moved under it.
struct TrafficLights: NSViewRepresentable {
    /// The close button's leading edge and the buttons' vertical centre, from the window's top-left corner.
    let origin: CGPoint

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) { view.origin = origin }

    final class Probe: NSView {
        var origin: CGPoint = .zero {
            didSet { if origin != oldValue { place() } }
        }
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification,
                NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            ]
            for name in names {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.place() }
                })
            }
            place()
        }

        func place() {
            guard let window, !window.styleMask.contains(.fullScreen), let close = window.standardWindowButton(.closeButton),
                  let bar = close.superview, let container = bar.superview else { return }
            // The bar must hold the buttons, or they draw outside it and take no clicks.
            let height = origin.y + close.frame.height / 2 + Space.s
            if container.frame.height != height {
                container.frame = NSRect(x: container.frame.minX, y: window.frame.height - height, width: container.frame.width, height: height)
                bar.frame = container.bounds
            }
            let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
            let gap = buttons.count > 1 ? buttons[1].frame.minX - buttons[0].frame.maxX : 0
            var x = origin.x
            for button in buttons {
                let y = bar.isFlipped ? origin.y - button.frame.height / 2 : bar.bounds.height - origin.y - button.frame.height / 2
                button.setFrameOrigin(NSPoint(x: x, y: y))
                x += button.frame.width + gap
            }
        }
    }
}
