import SwiftUI

/// Placeholder: the popover (session list → chat).
struct PopoverRoot: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading) {
            Text(String(describing: model.connection))
            List(model.sessions) { Text($0.title ?? $0.id) }
            HStack {
                Button("Open window", systemImage: "macwindow") {
                    openWindow(id: "main")
                    NSApp.activate() // the window may already be open behind other apps
                }
                SettingsLink { Label("Settings", systemImage: "gearshape") }
            }
        }
        .padding()
        .frame(width: 320, height: 420)
    }
}
