import SwiftUI

/// Placeholder: conversations | chat | terminal.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            List(model.sessions, selection: $selection) { Text($0.title ?? $0.id) }
        } detail: {
            if let selection {
                ChatView(sessionID: selection, compact: false)
            } else {
                Text("No conversation selected")
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
