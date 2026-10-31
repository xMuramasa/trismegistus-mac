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
            Image(systemName: statusSymbol)
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

    /// Placeholder status glyph: approval waiting, a run in progress, connected, disconnected.
    private var statusSymbol: String {
        if !model.pendingApprovals.isEmpty { return "exclamationmark.circle.fill" }
        if model.isWorking { return "circle.dotted.circle" }
        if case .connected = model.connection { return "circle.fill" }
        return "circle.dashed"
    }
}
