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
    /// The conversation the handoff sheet is open for.
    var handingOff: SessionInfo?
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
        run(store) { try await $0.deleteThread(info.id) }
    }

    private func run(_ store: SessionStore?, _ call: @escaping @MainActor (SessionStore) async throws -> Void) {
        error = nil
        guard let store else { return }
        Task {
            do { try await call(store) } catch { self.error = SessionStore.message(for: error) }
        }
    }
}

// MARK: Menu

/// Pin/Unpin, Rename, Tags, Hand off and Delete, as the relay allows them for the conversation's source.
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
        if capabilities.canHandOff {
            Button("Hand off", systemImage: Symbol.handoff) { actions.handingOff = info }
        }
        if capabilities.canDelete {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { actions.deleting = info }
        }
    }
}

/// The row's `…` button.
struct ConversationMenuButton: View {
    let info: SessionInfo
    let actions: ConversationActions
    let store: SessionStore?

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        Menu {
            ConversationMenuItems(info: info, actions: actions, store: store)
        } label: {
            Image(systemName: "ellipsis")
                .typeRole(.button).foregroundStyle(onSidebar ? Ink.text.onSidebar : Ink.text.primary)
                .frame(width: Size.menuButton, height: Size.menuButton)
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
    /// Asks before deleting, naming the conversation and every part of its thread; presents the handoff sheet.
    func confirmsDelete(_ actions: ConversationActions, store: SessionStore?) -> some View {
        alert("Delete conversation?", isPresented: Binding(get: { actions.deleting != nil }, set: { if !$0 { actions.deleting = nil } }),
              presenting: actions.deleting) { info in
            Button("Delete", role: .destructive) { actions.delete(info, store: store) }
            Button("Cancel", role: .cancel) {}
        } message: { info in
            Text(Self.deleteMessage(info, store: store))
        }
        .handoffSheet(Binding(get: { actions.handingOff }, set: { actions.handingOff = $0 }))
    }

    @MainActor private static func deleteMessage(_ info: SessionInfo, store: SessionStore?) -> String {
        guard let store, !store.olderParts(of: info.id).isEmpty else {
            return "“\(PopoverFormat.title(info))” is deleted on the relay. This can't be undone."
        }
        func name(_ id: String) -> String {
            store.sessionList.first { $0.id == id }.map { "“\(PopoverFormat.title($0))”" } ?? "an earlier part (\(id))"
        }
        let parts = store.deletableParts(of: info.id)
        let kept = store.olderParts(of: info.id).filter { !parts.contains($0) }
        var text = "Every part of this thread the relay can delete goes, newest first: " + parts.map(name).joined(separator: ", ") + "."
        if !kept.isEmpty { text += " Kept (from \(kept.count == 1 ? "a source" : "sources") the Mac can't delete): " + kept.map(name).joined(separator: ", ") + "." }
        return text + " This can't be undone."
    }
}

// MARK: Rows

/// `…` button (under the pointer and on the selected row only), pin glyph, tag chips, right-click menu with the same
/// items and the inline rename, laid over a `SessionRowView`; light on the window sidebar's grey unless the row is the
/// selected white card.
private struct ConversationChrome: ViewModifier {
    let info: SessionInfo
    let tags: [String]
    let isSelected: Bool
    let actions: ConversationActions
    let store: SessionStore?

    @Environment(\.onSidebar) private var onSidebar
    @State private var isHovered = false

    func body(content: Content) -> some View {
        let onGrey = onSidebar && !isSelected
        let showsMenu = isHovered || isSelected
        content
            .overlay(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: Space.xxs) {
                    // Hidden, not removed: the pointer leaves the row for the open menu, and removing the button would close it.
                    ConversationMenuButton(info: info, actions: actions, store: store)
                        .opacity(showsMenu ? 1 : 0).allowsHitTesting(showsMenu)
                    if info.isPinned {
                        // On the title's line: the centred run timer starts below it.
                        Image(systemName: "pin.fill").font(.system(size: Icon.s))
                            .foregroundStyle(RowInk(onSidebar: onSidebar, isSelected: isSelected).meta)
                            .padding(.top, Space.xxs)
                            .accessibilityLabel("Pinned")
                    }
                }
                .padding(.top, Space.xs).padding(.trailing, Space.s)
                .environment(\.onSidebar, onGrey)
            }
            .overlay(alignment: .bottomTrailing) {
                TagChips(tags: tags).padding(.bottom, Space.s).padding(.trailing, Space.m)
                    .environment(\.onSidebar, onGrey)
            }
            .overlay {
                if actions.renaming == info.id { RenameField(info: info, actions: actions, store: store) }
            }
            .onHover { isHovered = $0 }
            .contextMenu { ConversationMenuItems(info: info, actions: actions, store: store) }
    }
}

extension View {
    func conversationChrome(_ info: SessionInfo, tags: [String], isSelected: Bool = false, actions: ConversationActions,
                            store: SessionStore?) -> some View {
        modifier(ConversationChrome(info: info, tags: tags, isSelected: isSelected, actions: actions, store: store))
    }
}

/// Takes the row's place while renaming: ↩ saves, esc cancels, leaving the field saves nothing.
struct RenameField: View {
    let info: SessionInfo
    @Bindable var actions: ConversationActions
    let store: SessionStore?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Space.s) {
            TextField("Title", text: $actions.renameText)
                .textFieldStyle(.plain).typeRole(.headline).foregroundStyle(Ink.text.primary)
                .focused($focused)
                .onSubmit { actions.commitRename(info, store: store) }
                .onExitCommand { actions.renaming = nil }
            Text("↩ save · esc cancel").typeRole(.monoSmall).foregroundStyle(Ink.text.muted).fixedSize()
        }
        .padding(.horizontal, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
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
            .foregroundStyle(isOn ? Ink.selection : Ink.text.secondary)
            .padding(.horizontal, Space.s).padding(.vertical, 1)
            .background(isOn ? Ink.surface.inverse : Ink.surface.sunken)
            .overlay(Rectangle().strokeBorder(isOn ? Ink.line.strong : Ink.line.rule, lineWidth: Stroke.hairline))
    }
}

/// Up to two chips, then `+N`.
struct TagChips: View {
    let tags: [String]
    var limit = 2

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(tags.prefix(limit), id: \.self) { TagChip(tag: $0) }
                if tags.count > limit {
                    Text(verbatim: "+\(tags.count - limit)").typeRole(.monoSmall)
                        .foregroundStyle(onSidebar ? Ink.text.onSidebarSecondary : Ink.text.secondary)
                }
            }
            .frame(maxWidth: Size.tagsMax, alignment: .trailing)
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
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(verbatim: "Tags // \(tags.count)/\(TagRules.maxTags)").typeRole(.label).foregroundStyle(Ink.text.secondary)
                Spacer()
                EndfieldButton("Done", symbol: Symbol.check, kind: .quiet, iconOnly: true, action: onDone)
            }
            if !options.isEmpty {
                FlowLayout(spacing: Space.xs) {
                    ForEach(options, id: \.self) { tag in
                        let on = SessionListing.hasTag(tag, in: tags)
                        Button { toggle(tag, on: on) } label: { TagChip(tag: tag, isOn: on) }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: Space.s) {
                EndfieldTextField("New tag", text: $newTag, isError: problem != nil).onSubmit(add)
                EndfieldButton("Add tag", symbol: Symbol.plus, kind: .quiet, iconOnly: true, action: add)
            }
            if let problem { Text(problem).typeRole(.caption).foregroundStyle(Ink.text.error) }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
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
    var spacing: CGFloat = Space.xs

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

/// A one-line refusal under a list or header (light on the window sidebar's grey, where red doesn't read).
struct ActionError: View {
    let message: String?

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        if let message {
            Text(message).typeRole(.caption).foregroundStyle(onSidebar ? Ink.text.onSidebar : Ink.text.error)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// `PINNED` / `CONVERSATIONS` label above a group of rows.
struct SectionLabel: View {
    let title: String

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        Text(title).typeRole(.label).foregroundStyle(onSidebar ? Ink.text.onSidebarSecondary : Ink.text.secondary)
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
