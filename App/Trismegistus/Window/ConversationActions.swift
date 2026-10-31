import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// What one surface (the popover list, the window sidebar, the conversation header) is doing with its conversations:
/// the rename in progress, the tag editor that is open, the delete waiting for a yes, and the last refusal as one
/// line. The calls go through SessionStore, which updates at once and reverts when the relay refuses.
@MainActor @Observable
final class ConversationActions {
    var renaming: String?
    var renameText = ""
    var tagging: String?
    var deleting: SessionInfo?
    /// One line; cleared by the next action.
    var error: String?

    func togglePin(_ info: SessionInfo, store: SessionStore?) {
        run(store) { try await $0.setPinned(info.id, !info.isPinned) }
    }

    func beginRename(_ info: SessionInfo) {
        renameText = info.title ?? ""
        renaming = info.id
    }

    /// An empty or unchanged title cancels.
    func commitRename(_ info: SessionInfo, store: SessionStore?) {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !title.isEmpty, title != info.title else { return }
        run(store) { try await $0.renameSession(info.id, to: title) }
    }

    func setTags(_ id: String, _ tags: [String], store: SessionStore?) {
        run(store) { try await $0.setTags(id, tags) }
    }

    func delete(_ info: SessionInfo, store: SessionStore?) {
        deleting = nil
        run(store) { try await $0.deleteSession(info.id) }
    }

    private func run(_ store: SessionStore?, _ call: @escaping @MainActor (SessionStore) async throws -> Void) {
        error = nil
        guard let store else { return }
        Task {
            do { try await call(store) } catch { self.error = SessionStore.message(for: error) }
        }
    }
}

extension ConversationListRow {
    /// Pinned items first; the rest folded as usual, so the News row stays where the first feed run was among the
    /// unpinned ones (a pinned feed run is just a pinned conversation).
    static func listing(_ items: [Item], news: Set<String>, isPinned: (Item) -> Bool) -> (pinned: [Item], rest: [Self]) {
        let pinned = items.filter { isPinned($0) && !news.contains($0.id) }
        let rest = items.filter { !(isPinned($0) && !news.contains($0.id)) }
        return (pinned, folding(rest, news: news))
    }
}

// MARK: Menu

/// Pin/Unpin, Rename, Tags and Delete, as the relay allows them for the conversation's source.
struct ConversationMenuItems: View {
    let info: SessionInfo
    let actions: ConversationActions
    let store: SessionStore?

    var body: some View {
        let capabilities = SessionCapabilities(info)
        if capabilities.canPin {
            Button(info.isPinned ? "Unpin" : "Pin", systemImage: info.isPinned ? "pin.slash" : "pin") {
                actions.togglePin(info, store: store)
            }
        }
        if capabilities.canRename {
            Button("Rename", systemImage: "pencil") { actions.beginRename(info) }
        }
        if capabilities.canTag {
            Button("Tags", systemImage: "tag") { actions.tagging = actions.tagging == info.id ? nil : info.id }
        }
        if capabilities.canDelete {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { actions.deleting = info }
        }
    }
}

/// The trailing `…` button.
struct ConversationMenuButton: View {
    let info: SessionInfo
    let actions: ConversationActions
    let store: SessionStore?

    var body: some View {
        Menu {
            ConversationMenuItems(info: info, actions: actions, store: store)
        } label: {
            Image(systemName: "ellipsis")
                .typeRole(.button).foregroundStyle(Theme.ink)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions")
        .accessibilityLabel("Actions")
    }
}

extension View {
    /// Asks before deleting, naming the conversation.
    func confirmsDelete(_ actions: ConversationActions, store: SessionStore?) -> some View {
        alert("Delete conversation?", isPresented: Binding(get: { actions.deleting != nil }, set: { if !$0 { actions.deleting = nil } }),
              presenting: actions.deleting) { info in
            Button("Delete", role: .destructive) { actions.delete(info, store: store) }
            Button("Cancel", role: .cancel) {}
        } message: { info in
            Text("“\(PopoverFormat.title(info))” is deleted on the relay. This can't be undone.")
        }
    }
}

// MARK: Rows

/// Pin glyph, `…` button, tag chips, right-click menu and the inline rename, laid over a `SessionRowView`.
private struct ConversationChrome: ViewModifier {
    let info: SessionInfo
    let tags: [String]
    let actions: ConversationActions
    let store: SessionStore?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 2) {
                    if info.isPinned {
                        Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(Theme.secondary)
                            .accessibilityLabel("Pinned")
                    }
                    ConversationMenuButton(info: info, actions: actions, store: store)
                }
                .padding(.top, 3).padding(.trailing, 6)
            }
            .overlay(alignment: .bottomTrailing) {
                TagChips(tags: tags).padding(.bottom, 5).padding(.trailing, 12)
            }
            .overlay {
                if actions.renaming == info.id { RenameField(info: info, actions: actions, store: store) }
            }
            .contextMenu { ConversationMenuItems(info: info, actions: actions, store: store) }
    }
}

extension View {
    func conversationChrome(_ info: SessionInfo, tags: [String], actions: ConversationActions, store: SessionStore?) -> some View {
        modifier(ConversationChrome(info: info, tags: tags, actions: actions, store: store))
    }
}

/// Takes the row's place while renaming: ↩ saves, esc cancels, leaving the field saves nothing.
struct RenameField: View {
    let info: SessionInfo
    @Bindable var actions: ConversationActions
    let store: SessionStore?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Title", text: $actions.renameText)
                .textFieldStyle(.plain).typeRole(.headline).foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit { actions.commitRename(info, store: store) }
                .onExitCommand { actions.renaming = nil }
            Text("↩ save · esc cancel").typeRole(.monoSmall).foregroundStyle(Theme.muted).fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.raised)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .onAppear { focused = true }
        .onChange(of: focused) { _, now in
            if !now, actions.renaming == info.id { actions.renaming = nil }
        }
    }
}

// MARK: Tags

struct TagChip: View {
    let tag: String
    var isOn = false

    var body: some View {
        Text(tag).typeRole(.monoSmall).lineLimit(1)
            .foregroundStyle(isOn ? Theme.yellow : Theme.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(isOn ? Theme.ink : Theme.sunken)
            .overlay(Rectangle().strokeBorder(isOn ? Theme.ink : Theme.rule, lineWidth: 1))
    }
}

/// Up to two chips, then `+N`.
struct TagChips: View {
    let tags: [String]
    var limit = 2

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 4) {
                ForEach(tags.prefix(limit), id: \.self) { TagChip(tag: $0) }
                if tags.count > limit {
                    Text("+\(tags.count - limit)").typeRole(.monoSmall).foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: 220, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }
    }
}

/// The existing tags as toggles plus a field for a new one; every change goes to the relay at once.
struct TagEditor: View {
    let tags: [String]
    /// Every tag in use, whatever the conversation.
    let known: [String]
    let onChange: @MainActor ([String]) -> Void
    let onDone: @MainActor () -> Void

    @State private var newTag = ""
    @State private var problem: String?

    private var options: [String] {
        tags + known.filter { !SessionListing.hasTag($0, in: tags) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tags // \(tags.count)/\(TagRules.maxTags)").typeRole(.label).foregroundStyle(Theme.secondary)
                Spacer()
                EndfieldButton("Done", symbol: Symbol.check, kind: .quiet, iconOnly: true, action: onDone)
            }
            if !options.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(options, id: \.self) { tag in
                        let on = SessionListing.hasTag(tag, in: tags)
                        Button { toggle(tag, on: on) } label: { TagChip(tag: tag, isOn: on) }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: 6) {
                EndfieldTextField("New tag", text: $newTag, isError: problem != nil).onSubmit(add)
                EndfieldButton("Add tag", symbol: Symbol.plus, kind: .quiet, iconOnly: true, action: add)
            }
            if let problem { Text(problem).typeRole(.caption).foregroundStyle(Theme.red) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
        .onExitCommand(perform: onDone)
    }

    private func toggle(_ tag: String, on: Bool) {
        do {
            let next = try on ? TagRules.removing(tag, from: tags) : TagRules.adding(tag, to: tags)
            onChange(next)
            problem = nil
        } catch {
            problem = error.message
        }
    }

    private func add() {
        guard !newTag.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            onChange(try TagRules.adding(newTag, to: tags))
            newTag = ""
            problem = nil
        } catch {
            problem = error.message
        }
    }
}

/// Left to right, wrapping.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(subviews, width: bounds.width)
        for (subview, origin) in zip(subviews, placed.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, CGSize(width: widest, height: y + rowHeight))
    }
}

/// A one-line refusal under a list or header.
struct ActionError: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message).typeRole(.caption).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `PINNED` / `CONVERSATIONS` label above a group of rows.
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title).typeRole(.label).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
