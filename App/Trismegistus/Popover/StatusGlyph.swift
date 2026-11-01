import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The menu bar label: the template glyph for the store's global activity.
/// In `App.swift` the `MenuBarExtra` label is `StatusGlyph(activity: ..., agentsRunning: ...)`.
struct StatusGlyph: View {
    let activity: SessionStore.Activity
    /// Background agents are alive (the Agents row's board): a small dot on the glyph.
    var agentsRunning = false

    private var state: GlyphState {
        switch activity {
        case .disconnected: .disconnected
        case .idle: .idle
        case .running: .running
        case .approvalWaiting: .approval
        }
    }

    var body: some View {
        Image(nsImage: MenuBarGlyph.image(state, agents: agentsRunning))
            .renderingMode(.template)
            .accessibilityLabel("Trismegistus")
    }
}
