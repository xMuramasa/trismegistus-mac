import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Continues a conversation that got too large in a new one: shows the digest's size and the model for the
/// continuation (the old one's by default), then runs `SessionStore.handOff`. The lists follow the thread to the new
/// part, so the window stays on it.
struct HandoffSheet: View {
    let old: SessionInfo
    let onClose: @MainActor () -> Void

    @Environment(AppModel.self) private var model
    @State private var digest: String?
    @State private var loadError: String?
    @State private var choice: ModelChoice?
    @State private var working = false
    /// What went wrong; after a handoff that made the new conversation, the sheet only offers Done.
    @State private var problems: [String] = []
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            TitleRule("Hand off")
            Text(verbatim: "Continue “\(PopoverFormat.title(old))” in a new conversation that starts from a digest of this one: your messages, the replies and one line per tool call. Both show as one thread.")
                .typeRole(.callout).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.s) {
                Text("Digest").typeRole(.label).foregroundStyle(Ink.text.secondary)
                if let digest {
                    Text(size(digest)).typeRole(.monoSmall).foregroundStyle(Ink.text.primary)
                } else if let loadError {
                    Text(loadError).typeRole(.caption).foregroundStyle(Ink.text.error).lineLimit(2)
                    EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { Task { await load() } }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            if let catalog = model.store?.models {
                HStack(spacing: Space.s) {
                    Text("Model").typeRole(.label).foregroundStyle(Ink.text.secondary)
                    Menu {
                        ModelMenuItems(catalog: catalog, selected: choice) { choice = $0 }
                    } label: {
                        ModelLabel(choice: choice)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .help(choice.map { catalog.providerName($0.provider) } ?? "Model")
                }
            }
            ForEach(problems, id: \.self) { Text($0).typeRole(.caption).foregroundStyle(Ink.text.error) }
            HStack(spacing: Space.s) {
                Spacer()
                if finished {
                    EndfieldButton("Done", symbol: Symbol.check, kind: .primary, action: onClose)
                } else {
                    EndfieldButton("Cancel", symbol: Symbol.close, kind: .quiet, shortcut: .cancelAction, action: onClose)
                    EndfieldButton("Hand off", symbol: Symbol.handoff, kind: .primary) { Task { await handOff() } }
                        .disabled(digest == nil || working)
                }
            }
        }
        .padding(Space.xl)
        .frame(width: Size.handoffSheet.width)
        .background(Ink.surface.window)
        .task { await load() }
    }

    private func size(_ digest: String) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(digest.utf8.count), countStyle: .file)
        var parts = [bytes, "\(old.messageCount ?? 0) messages"]
        if digest.contains("cut to fit") { parts.append("older part cut") }
        return parts.joined(separator: " · ")
    }

    private func load() async {
        guard let store = model.store else { return }
        loadError = nil
        let mine = old.isReadOnly ? old.model.flatMap { store.models?.choice(model: $0) } : store.model(for: old.id)
        if choice == nil { choice = mine ?? store.models?.current }
        do {
            let history = try await store.rest.messages(old.id)
            let name = old.isReadOnly ? old.model : mine.map { "\($0.provider)/\($0.model)" }
            digest = HandoffDigest.make(history: history, info: old, model: name)
        } catch {
            loadError = SessionStore.message(for: error)
        }
    }

    private func handOff() async {
        guard let store = model.store, let digest else { return }
        working = true
        defer { working = false }
        problems = []
        do {
            let result = try await store.handOff(old, model: choice, prompt: HandoffDigest.prompt(digest: digest))
            if result.problems.isEmpty { return onClose() }
            problems = result.problems
            finished = true
        } catch let error as HandoffError {
            problems = [error.message]
            finished = true
        } catch {
            // Nothing was made: Hand off can be tried again.
            problems = [SessionStore.message(for: error)]
        }
    }
}

extension Symbol {
    static let handoff = "arrow.right.square"
}

extension View {
    /// Presents the handoff sheet while `old` is set.
    func handoffSheet(_ old: Binding<SessionInfo?>) -> some View {
        sheet(item: old) { info in HandoffSheet(old: info) { old.wrappedValue = nil } }
    }
}
