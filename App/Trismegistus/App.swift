import SwiftUI

@main
struct TrismegistusApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Group {
                if model.needsPairing { PairingSheet() } else { PopoverRoot() }
            }
            .environment(model)
        } label: {
            StatusGlyph(activity: model.store?.activity ?? .disconnected)
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

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
