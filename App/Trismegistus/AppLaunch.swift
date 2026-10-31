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

    /// A launch at login starts quietly. Two signs, either is enough:
    /// - the open-application event carries `keyAELaunchedAsLogInItem` (legacy login items; only valid while that
    ///   event is handled, i.e. in `applicationDidFinishLaunching`). `SMAppService` login items don't get it: seen on
    ///   macOS 26, where the window opened at login.
    /// - the app started within a minute of Finder, which starts with every login session. A Finder relaunch right
    ///   before opening the app by hand would also start it quietly; the menu bar icon is still there.
    ///   Start times come from the kernel (`kinfo_proc`): `NSRunningApplication.launchDate` is nil for Finder, and
    ///   the sandbox can't read utmpx (both checked on macOS 26).
    private static var launchedAsLoginItem: Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent, event.eventID == AEEventID(kAEOpenApplication),
           event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return true
        }
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
              let finderStart = startTime(of: finder.processIdentifier),
              let ourStart = startTime(of: getpid())
        else { return false }
        return abs(ourStart.timeIntervalSince(finderStart)) < 60
    }

    private static func startTime(of pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        guard tv.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec) + TimeInterval(tv.tv_usec) / 1_000_000)
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
