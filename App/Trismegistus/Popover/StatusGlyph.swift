import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The menu bar label: the template glyph for the store's global activity.
/// In `App.swift` the `MenuBarExtra` label is `StatusGlyph(activity: model.store?.activity ?? .disconnected)`.
struct StatusGlyph: View {
    let activity: SessionStore.Activity

    private var state: GlyphState {
        switch activity {
        case .disconnected: .disconnected
        case .idle: .idle
        case .running: .running
        case .approvalWaiting: .approval
        }
    }

    var body: some View {
        Image(nsImage: MenuBarGlyph.image(state))
            .renderingMode(.template)
            .accessibilityLabel("Trismegistus")
    }
}
