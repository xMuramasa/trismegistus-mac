import AppKit
import Observation
import SwiftUI

/// Launch glue that only AppKit knows about: who opened the app, opening it again while it runs, and keeping a
/// menu bar app alive with no windows.
@MainActor @Observable
final class AppLaunch: NSObject, NSApplicationDelegate {
    /// Set when Martin opens the app himself (Finder, Spotlight, the Dock, or again while it runs); the menu bar
    /// label opens the main window and clears it. A launch at login leaves it unset: the app starts quietly in the
    /// menu bar.
    var wantsMainWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // With no window open, macOS treats the app as idle after a few seconds: it drops it from the app switcher
        // and may quit it quietly (automatic termination). A menu bar app has no window most of the time.
        ProcessInfo.processInfo.disableAutomaticTermination("Trismegistus lives in the menu bar")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !Self.launchedAsLoginItem { wantsMainWindow = true }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        wantsMainWindow = true
        return false
    }

    /// macOS marks the open-application event with `keyAELaunchedAsLogInItem` when it starts the app at login.
    /// Only valid while that event is handled, i.e. in `applicationDidFinishLaunching`.
    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication)
        else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}

extension View {
    /// For the menu bar label, the one view that is always there: opens the main window when `AppLaunch` asks.
    func opensMainWindow(on launch: AppLaunch) -> some View {
        modifier(OpenMainWindow(launch: launch))
    }
}

private struct OpenMainWindow: ViewModifier {
    let launch: AppLaunch
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear(perform: take)  // the launch request may come before the label exists
            .onChange(of: launch.wantsMainWindow) { take() }
    }

    private func take() {
        guard launch.wantsMainWindow else { return }
        launch.wantsMainWindow = false
        openWindow(id: "main")
        NSApp.activate()
    }
}
