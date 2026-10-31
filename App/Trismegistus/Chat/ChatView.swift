import SwiftUI

/// Placeholder: one conversation. compact is the popover layout; onShowTerminal focuses the window's terminal pane.
struct ChatView: View {
    let sessionID: String
    var compact: Bool = true
    var onShowTerminal: (() -> Void)? = nil

    var body: some View {
        Text(sessionID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
