import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The conversation's effort as its own pill right of the model's (#74, design 16d): `∴ High ⌄`, `∴ Default` while
/// nothing is chosen. Only app conversations whose model can think have one; the choice applies from the next message.
/// Hermes' calls (flip here): the window header only, the popover keeps its model text; a handoff doesn't copy it.
struct EffortMenu: View {
    let info: SessionInfo
    /// The window header's narrow-window rule: only the glyph from stage 3 (#74).
    var fit = HeaderFit()

    @Environment(AppModel.self) private var model
    @Environment(\.onSteel) private var onSteel
    @State private var error: String?

    var body: some View {
        if let store = model.store, let catalog = store.models, !info.isReadOnly, let current = store.model(for: info.id),
            catalog.reasons(current)
        {
            let effort = store.sessionEfforts[info.id]
            let label = effort?.label ?? "Default"
            HStack(spacing: Space.s) {
                if let error { Text(error).typeRole(.caption).foregroundStyle(onSteel ? Ink.status.warn : Ink.text.error).lineLimit(1) }
                Menu {
                    Section("Effort") {
                        option(nil, effort, note: "Hermes' setting", store: store)
                        ForEach(Effort.allCases, id: \.self) { option($0, effort, note: $0 == .none ? "no thinking" : nil, store: store) }
                    }
                    Divider()
                    Button("Applies from the next message.") {}.disabled(true)
                } label: {
                    PillLabel(fit.effortShort ? "" : label, glyph: "∴", placeholder: effort == nil)
                }
                // As ModelMenu: `.button` + `.plain` draws the pill as it is.
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .fixedSize()
                .help("Effort: \(label) · applies from the next message")
                .accessibilityLabel("Effort \(label)")
            }
        }
    }

    /// A checkable item; the note shows under its name (a native menu has no trailing text but a shortcut's).
    private func option(_ value: Effort?, _ current: Effort?, note: String?, store: SessionStore) -> some View {
        Toggle(isOn: Binding(get: { value == current }, set: { if $0 { pick(value, store: store) } })) {
            Text(value?.label ?? "Default")
            if let note { Text(note) }
        }
    }

    private func pick(_ value: Effort?, store: SessionStore) {
        error = nil
        Task {
            do { try await store.setEffort(info.id, value) } catch { self.error = SessionStore.message(for: error) }
        }
    }
}
