import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The Chat section's list column (#68): `…` (Rename, Tags, Hand off for the open conversation), `APP // 10`, the yellow
/// `+`; the filter (⌘K) and tag chips; In progress (a waiting approval or a live run), Pinned and Conversations groups
/// (#72, design 15b) over one mission card per conversation of the kind picked in the section panel's Chats group (#48).
struct ConversationSidebar: View {
    typealias Groups = (inProgress: [SessionOverview], pinned: [SessionOverview], rest: [SessionOverview])

    @Binding var selection: String?
    /// The Filter field's focus (⌘K).
    var filterFocus: FocusState<Bool>.Binding

    @Environment(AppModel.self) private var model
    /// The tab, shared with the popover.
    @AppStorage("chat.kind") private var storedKind = ConversationKind.app
    @State private var filter = ""
    /// A tag, lowercased (`TagRules.key`).
    @State private var tagFilter: String?
    @State private var createFailed = false
    @State private var actions = ConversationActions()

    private var tags: [String: [String]] { model.store?.tags ?? [:] }
    /// One per thread: its newest part (title, tags and pin come from it).
    private var threads: [SessionInfo] { SessionListing.threads(model.sessions, id: \.id, links: model.store?.links ?? [:]) }
    /// Tags of the listed conversations with how many carry each; tag ids the app doesn't list are ignored.
    private var tagCounts: [(tag: String, count: Int)] { SessionListing.tagCounts(ids: threads.map(\.id), tags: tags) }

    /// In progress, pinned, then the rest, each most recent first. Every kind, unfiltered.
    private var listing: Groups { Self.listing(model) }

    /// The model's conversations, one per thread: those waiting for an approval and then those running, then the pinned,
    /// then the rest, each most recent first (the panel's Chats group counts them).
    @MainActor static func listing(_ model: AppModel) -> Groups {
        guard let store = model.store else { return ([], [], []) }
        let threads = SessionListing.threads(model.sessions, id: \.id, links: store.links)
        let overviews = threads
            .compactMap { store.overview[$0.id] }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        return SessionListing.groups(overviews, attention: attention) { $0.info?.isPinned == true }
    }

    private static func attention(_ overview: SessionOverview) -> ConversationKind.Attention? {
        ConversationKind.Attention(isWaitingForApproval: overview.isWaitingForApproval, isRunning: overview.run != nil)
    }

    private static func all(_ groups: Groups) -> [SessionOverview] { groups.inProgress + groups.pinned + groups.rest }

    /// Counts and marks per kind.
    static func summary(_ listing: Groups) -> ConversationKind.Summary {
        ConversationKind.Summary(all(listing).map { (source: $0.source, attention: attention($0)) })
    }

    /// The listing in the tab, after the filter field and the tag filter; `elsewhere` when the filter finds nothing in
    /// the tab but something in another. A pinned conversation is only in its own tab.
    private func shown(_ listing: Groups, kind: ConversationKind) -> (groups: Groups, elsewhere: (kind: ConversationKind, count: Int)?) {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        func matches(_ overview: SessionOverview) -> Bool {
            if let tagFilter, !SessionListing.hasTag(tagFilter, in: tags[overview.id] ?? []) { return false }
            return needle.isEmpty || (overview.info.map(Self.title) ?? "").localizedCaseInsensitiveContains(needle)
        }
        func inTab(_ overview: SessionOverview) -> Bool { matches(overview) && kind.includes(overview.source) }
        let groups = (inProgress: listing.inProgress.filter(inTab), pinned: listing.pinned.filter(inTab), rest: listing.rest.filter(inTab))
        let elsewhere = Self.all(groups).isEmpty
            ? ConversationKind.elsewhere(Self.all(listing).filter(matches).map(\.source), current: kind) : nil
        return (groups, elsewhere)
    }

    private struct Entry: Equatable {
        let id: String
        let source: String?
    }

    /// Every conversation of every kind in the order shown, for moving the selection when one goes (a tab switch keeps
    /// the open conversation, so this doesn't change with the tab).
    private var ordered: [Entry] {
        Self.all(listing).map { Entry(id: $0.id, source: $0.source) }
    }

    var body: some View {
        let listing = self.listing
        let kind = Self.summary(listing).resolving(storedKind)
        let shown = self.shown(listing, kind: kind)
        let groups = shown.groups
        let count = Self.all(groups).count
        VStack(spacing: 0) {
            header(kind: kind, count: count)
            if count == 0 { empty(kind: kind, elsewhere: shown.elsewhere) }
            List(selection: $selection) {
                if !groups.inProgress.isEmpty {
                    InProgressHead().sidebarRow()
                    ForEach(groups.inProgress) { conversation($0) }
                }
                if !groups.pinned.isEmpty {
                    MissionGroupHead(title: "Pinned", count: groups.pinned.count, symbol: Symbol.pinOutline, isFirst: groups.inProgress.isEmpty)
                        .sidebarRow()
                    ForEach(groups.pinned) { conversation($0) }
                }
                if !groups.rest.isEmpty {
                    MissionGroupHead(title: "Conversations", count: groups.rest.count, symbol: Symbol.kindOther,
                                     isFirst: groups.inProgress.isEmpty && groups.pinned.isEmpty)
                        .sidebarRow()
                    ForEach(groups.rest) { conversation($0) }
                }
            }
            .sidebarList()
        }
        .confirmsDelete(actions, store: model.store)
        .onChange(of: ordered) { old, new in
            // A handed-off conversation leaves the list for the part that continues it: the window stays on the thread.
            if let selection, let tip = model.store?.threadTip(of: selection), tip != selection {
                self.selection = tip
            } else {
                // The next conversation of the current tab takes the place of the one that went (none if the tab is empty);
                // the open one itself counts wherever it is, so one from another tab keeps its place in the order.
                let kind = ConversationKind.Summary(new.map { (source: $0.source, attention: nil) }).resolving(storedKind)
                let open = selection
                func inTab(_ entries: [Entry]) -> [String] {
                    entries.filter { kind.includes($0.source) || $0.id == open }.map(\.id)
                }
                selection = SessionListing.selection(open, from: inTab(old), to: inTab(new))
            }
        }
        .onChange(of: tagCounts.map(\.tag)) { _, tags in
            if let tagFilter, !tags.contains(where: { TagRules.key($0) == tagFilter }) { self.tagFilter = nil }
        }
    }

    /// The empty tab's line, or the row that goes to the tab holding the filter's matches.
    @ViewBuilder private func empty(kind: ConversationKind, elsewhere: (kind: ConversationKind, count: Int)?) -> some View {
        if let elsewhere {
            Button { storedKind = elsewhere.kind } label: {
                HStack(spacing: Space.s) {
                    Text(verbatim: "\(elsewhere.count) more in \(elsewhere.kind.name.uppercased())").typeRole(.caption)
                    Image(systemName: Symbol.chevronRight).font(.system(size: Icon.xxs, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Ink.text.onSidebar)
                .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            SidebarNote(text: filter.isEmpty && tagFilter == nil ? kind.emptyText : "No conversations match")
        }
    }

    /// A conversation's row, with its tag editor under it while that is open.
    private func conversation(_ overview: SessionOverview) -> some View {
        VStack(spacing: 0) {
            ConversationRow(overview: overview, isSelected: selection == overview.id, actions: actions, store: model.store)
            if actions.tagging == overview.id, let store = model.store {
                TagEditor(
                    tags: tags[overview.id] ?? [], known: tagCounts.map(\.tag),
                    onChange: { actions.setTags(overview.id, $0, store: store) }, onDone: { actions.tagging = nil })
                    // A white panel: its quiet buttons in ink.
                    .environment(\.onSidebar, false)
                    .padding(.top, Space.s)
            }
        }
        .missionCell(isSelected: selection == overview.id)
        .tag(overview.id)
        .sidebarRow()
    }

    /// The header line, then the filter field, the tag chips and any refusal. The `+` steps down from yellow while the
    /// open conversation runs: Steer is the yellow action then.
    private func header(kind: ConversationKind, count: Int) -> some View {
        let open = selection.flatMap { id in model.sessions.first { $0.id == (model.store?.threadTip(of: id) ?? id) } }
        return VStack(spacing: Space.s) {
            ListHeader(title: "\(kind.name) // \(count)") {
                Menu {
                    if let open { ConversationMenuItems(info: open, actions: actions, store: model.store, headerOnly: true) }
                } label: { IconCell(symbol: Symbol.ellipsis) }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    .disabled(open == nil)
                    .help("Actions for the open conversation")
                    .accessibilityLabel("Conversation actions")
            } trailing: {
                PlusButton("New conversation", isPrimary: open.flatMap { model.store?.overview[$0.id]?.run } == nil) { create() }
            }
            .padding(.horizontal, -Space.l)
            SidebarFilter("Filter", text: $filter, focus: filterFocus)
            if !tagCounts.isEmpty { tagFilterBar }
            ActionError(message: createFailed ? "Could not create a conversation. Try again." : nil)
            ActionError(message: actions.error)
        }
        .padding(.horizontal, Space.l).padding(.bottom, Space.m)
    }

    /// One chip per tag with its count; a second click clears it.
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.xs) {
                ForEach(tagCounts, id: \.tag) { entry in
                    let on = tagFilter == TagRules.key(entry.tag)
                    Button { tagFilter = on ? nil : TagRules.key(entry.tag) } label: {
                        TagChip(tag: "\(entry.tag) \(entry.count)", isOn: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(entry.tag), \(entry.count) conversations")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func create() {
        Task {
            do {
                selection = try await model.store?.createSession().id
                storedKind = .app // a new conversation is the app's
                createFailed = false
            } catch {
                createFailed = true
            }
        }
    }

    static func title(_ info: SessionInfo) -> String { info.title ?? info.preview ?? "New conversation" }
}

/// The kind tabs over a list's `summary`; the window's sidebar and the popover share them and the choice
/// (`@AppStorage("chat.kind")`).
struct ChatKindTabs: View {
    let summary: ConversationKind.Summary
    @Binding var kind: ConversationKind

    /// A kind as the tabs and the panel's Chats group show it.
    static func chip(_ kind: ConversationKind, summary: ConversationKind.Summary) -> KindChip {
        let entry = summary[kind]
        return KindChip(id: kind.rawValue, title: kind.name, symbol: Self.symbol(kind), count: entry.count, mark: entry.attention.map(Self.mark))
    }

    private static func symbol(_ kind: ConversationKind) -> String {
        switch kind {
        case .app: Symbol.kindApp
        case .telegram: Symbol.kindTelegram
        case .terminal: Symbol.kindTerminal
        case .oneShot: Symbol.kindOneShot
        case .cron: Symbol.clock
        case .all: Symbol.kindAll
        case .other: Symbol.kindOther
        }
    }

    static func mark(_ attention: ConversationKind.Attention) -> StickerState { attention == .approval ? .approval : .running }

    var body: some View {
        KindTabs(tabs: ConversationKind.tabs.map { Self.chip($0, summary: summary) }, more: summary.more.map { Self.chip($0, summary: summary) }, moreMark: summary.moreAttention.map(Self.mark),
                 selection: summary.resolving(kind).rawValue) { id in
            if let picked = ConversationKind(rawValue: id) { kind = picked }
        }
    }
}

private struct ConversationRow: View {
    let overview: SessionOverview
    let isSelected: Bool
    let actions: ConversationActions
    let store: SessionStore?

    var body: some View {
        // Ticks every second only while a run's clock shows; the "2 min" age is fine at half a minute.
        TimelineView(.periodic(from: .now, by: overview.run == nil ? 30 : 1)) { context in
            // The tags stay in the filter and the detail header (#72).
            let row = MissionCard(
                name: overview.info.map(ConversationSidebar.title) ?? "New conversation",
                source: source, activity: Self.age(overview.lastActivity, now: context.date),
                // The relay's preview as it is; with no title the preview is the title already.
                preview: overview.info?.title == nil ? nil : overview.info?.preview, isSelected: isSelected,
                isReadOnly: overview.isReadOnly, isPinned: overview.info?.isPinned == true,
                runElapsed: overview.run.map { Self.clock(context.date.timeIntervalSince($0.startedAt)) },
                needsApproval: overview.isWaitingForApproval)
            if let info = overview.info {
                row.conversationChrome(info, isSelected: isSelected, actions: actions, store: store)
            } else {
                row
            }
        }
    }

    private var source: SessionSource {
        switch overview.source {
        case "api_server": .trismegistus
        case "telegram": .telegram
        case "cron": .cron
        default: .cli
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60) min"
        case ..<86400: return "\(s / 3600) h"
        case ..<172_800: return "yesterday"
        default: return "\(s / 86400) d"
        }
    }
}
