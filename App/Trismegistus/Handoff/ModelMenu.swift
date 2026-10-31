import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The conversation's model. App conversations get a menu of the connected models by provider (the choice applies
/// from the next message); others show the model Hermes ran them on, read-only. Nothing from a relay without models.
struct ModelMenu: View {
    let info: SessionInfo

    @Environment(AppModel.self) private var model
    @State private var error: String?

    var body: some View {
        if let store = model.store, let catalog = store.models {
            HStack(spacing: 6) {
                if let error { Text(error).typeRole(.caption).foregroundStyle(Theme.red).lineLimit(1) }
                if info.isReadOnly {
                    if let id = info.model {
                        Text(ModelChoice.label(id)).typeRole(.monoSmall).foregroundStyle(Theme.secondary).lineLimit(1)
                            .help("Model (set in \(PopoverFormat.sourceName(info.source)))")
                    }
                } else if let current = store.model(for: info.id) {
                    Menu {
                        ModelMenuItems(catalog: catalog, selected: current) { choice in
                            error = nil
                            Task {
                                do { try await store.setModel(info.id, choice) } catch { self.error = SessionStore.message(for: error) }
                            }
                        }
                    } label: {
                        ModelLabel(choice: current)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Model: \(catalog.providerName(current.provider)) · applies from the next message")
                    .accessibilityLabel("Model \(current.label)")
                }
            }
        }
    }
}

/// The model's id and a chevron, as the menus show it.
struct ModelLabel: View {
    let choice: ModelChoice?

    var body: some View {
        HStack(spacing: 4) {
            Text(choice?.label ?? "Model").typeRole(.monoSmall).lineLimit(1)
            Image(systemName: Symbol.chevronDown).font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// One section per connected provider, the selected model checked.
struct ModelMenuItems: View {
    let catalog: ModelCatalog
    let selected: ModelChoice?
    let onPick: @MainActor (ModelChoice) -> Void

    var body: some View {
        ForEach(catalog.providers) { provider in
            Section(provider.name) {
                ForEach(provider.models) { m in
                    let choice = ModelChoice(provider: provider.slug, model: m.id)
                    Toggle(choice.label, isOn: Binding(get: { choice == selected }, set: { if $0 { onPick(choice) } }))
                }
            }
        }
    }
}
