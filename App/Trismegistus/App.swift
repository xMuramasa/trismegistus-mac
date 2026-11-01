import SwiftUI

@main
struct TrismegistusApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var launch: AppLaunch

    init() {
        // Light mode only (SPEC "Design"): the Endfield palette is paper and ink. Without this, text and toolbars that
        // follow the system appearance turn white or dark on the paper background when macOS is in dark mode.
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        MenuBarExtra {
            Group {
                if model.needsPairing { PairingSheet() } else { PopoverRoot() }
            }
            .environment(model)
        } label: {
            StatusGlyph(activity: model.store?.activity ?? .disconnected, agentsRunning: model.agents?.anyRunning ?? false)
                // The label is the one view that is always alive: it opens the window for a clicked notification.
                .opensChatFromNotifications(model.notifications)
                .opensMainWindow(on: launch)  // when Martin opens the app himself, not at login
        }
        .menuBarExtraStyle(.window)

        Window("Trismegistus", id: "main") {
            MainWindow()
                .environment(model)
                // A menu bar app gets a Dock icon and the app switcher only while its window is open.
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                }
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }
        .defaultLaunchBehavior(.suppressed)
        .commands { SidebarMenuCommands() }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
