import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Window sidebar: `CONVERSATIONS // n`, icon-only new, filter field, the Commands row, one row per session, the
/// paired device below. On `SidebarSplit`'s sunken ground: no row separators, rows without their own fill.
struct ConversationSidebar: View {
    @Binding var selection: String?
    /// The Filter field's focus (⌘K).
    var filterFocus: FocusState<Bool>.Binding

    @Environment(AppModel.self) private var model
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

    /// Pinned first, then most recent first with the daily feed runs folded into one News row. Unfiltered.
    private var listing: (pinned: [SessionOverview], rest: [ConversationListRow<SessionOverview>]) {
        guard let store = model.store else { return ([], []) }
        let overviews = threads
            .compactMap { store.overview[$0.id] }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        return ConversationListRow.listing(overviews, news: model.news?.sessionIDs ?? [], isPinned: { $0.info?.isPinned == true })
    }

    /// The listing after the filter field and the tag filter.
    private var shown: (pinned: [SessionOverview], rest: [ConversationListRow<SessionOverview>]) {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let news = model.news
        func matches(_ overview: SessionOverview) -> Bool {
            if let tagFilter, !SessionListing.hasTag(tagFilter, in: tags[overview.id] ?? []) { return false }
            return needle.isEmpty || (overview.info.map(Self.title) ?? "").localizedCaseInsensitiveContains(needle)
        }
        let listing = self.listing
        return (listing.pinned.filter(matches), listing.rest.filter { row in
            switch row {
            case .item(let overview): return matches(overview)
            case .news:
                return tagFilter == nil && (needle.isEmpty
                    || ["News", news?.items.first?.edition.title ?? ""].contains { $0.localizedCaseInsensitiveContains(needle) })
            }
        })
    }

    /// Every conversation in the order shown, for moving the selection when one goes.
    private var orderedIDs: [String] {
        let listing = self.listing
        return listing.pinned.map(\.id) + listing.rest.map(\.id)
    }

    var body: some View {
        let shown = self.shown
        VStack(spacing: 0) {
            header(count: shown.pinned.count + shown.rest.count)
            // Every row sets `listRowBackground`: it replaces the row view's ground, where macOS draws its selection
            // highlight (a thin blue line still showed past the rows' sunken backing in a key window).
            List(selection: $selection) {
                CommandsRowView(isSelected: selection == CommandsView.id)
                    .tag(CommandsView.id)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden).listRowBackground(Theme.sunken)
                if !shown.pinned.isEmpty {
                    SectionLabel(title: "Pinned").listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Theme.sunken)
                    ForEach(shown.pinned) { conversation($0) }
                    if !shown.rest.isEmpty {
                        SectionLabel(title: "Conversations").listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Theme.sunken)
                    }
                }
                ForEach(shown.rest) { row in
                    switch row {
                    case .item(let overview): conversation(overview)
                    case .news:
                        newsRow
                            .tag(row.id)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden).listRowBackground(Theme.sunken)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            footer
        }
        .confirmsDelete(actions, store: model.store)
        .onChange(of: orderedIDs) { old, new in
            // A handed-off conversation leaves the list for the part that continues it: the window stays on the thread.
            if let selection, let tip = model.store?.threadTip(of: selection), tip != selection {
                self.selection = tip
            } else {
                selection = SessionListing.selection(selection, from: old, to: new)
            }
        }
        .onChange(of: tagCounts.map(\.tag)) { _, tags in
            if let tagFilter, !tags.contains(where: { TagRules.key($0) == tagFilter }) { self.tagFilter = nil }
        }
    }

    /// A conversation's row, with its tag editor under it while that is open.
    private func conversation(_ overview: SessionOverview) -> some View {
        VStack(spacing: 0) {
            ConversationRow(overview: overview, isSelected: selection == overview.id,
                            tags: tags[overview.id] ?? [], actions: actions, store: model.store)
            if actions.tagging == overview.id, let store = model.store {
                TagEditor(
                    tags: tags[overview.id] ?? [], known: tagCounts.map(\.tag),
                    onChange: { actions.setTags(overview.id, $0, store: store) }, onDone: { actions.tagging = nil })
                    .padding(8)
            }
        }
        .tag(overview.id)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden).listRowBackground(Theme.sunken)
    }

    private func header(count: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Conversations // \(count)").typeRole(.label).foregroundStyle(Theme.secondary)
                Spacer()
                EndfieldButton("New conversation", symbol: Symbol.plus, kind: .quiet, iconOnly: true) { create() }
            }
            EndfieldTextField("Filter", text: $filter, ground: Theme.paper, focus: filterFocus)
            if !tagCounts.isEmpty { tagFilterBar }
            if createFailed {
                Text("Could not create a conversation. Try again.").typeRole(.caption).foregroundStyle(Theme.red)
            }
            ActionError(message: actions.error)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// One chip per tag with its count; a second click clears it.
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
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

    @ViewBuilder private var newsRow: some View {
        if let news = model.news {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                NewsRowView(feed: news, isSelected: selection == NewsRowView.id, now: context.date)
            }
        }
    }

    private var footer: some View {
        Text(model.deviceName.map { "\($0) · paired" } ?? "not paired")
            .typeRole(.monoSmall).foregroundStyle(Theme.secondary)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private func create() {
        Task {
            do {
                selection = try await model.store?.createSession().id
                createFailed = false
            } catch {
                createFailed = true
            }
        }
    }

    static func title(_ info: SessionInfo) -> String { info.title ?? info.preview ?? "New conversation" }
}

private struct ConversationRow: View {
    let overview: SessionOverview
    let isSelected: Bool
    let tags: [String]
    let actions: ConversationActions
    let store: SessionStore?

    var body: some View {
        // Ticks every second only while a run's clock shows; the "2 min" age is fine at half a minute.
        TimelineView(.periodic(from: .now, by: overview.run == nil ? 30 : 1)) { context in
            let row = SessionRowView(
                name: overview.info.map(ConversationSidebar.title) ?? "New conversation",
                source: source, activity: Self.age(overview.lastActivity, now: context.date), isSelected: isSelected,
                isReadOnly: overview.isReadOnly,
                runElapsed: overview.run.map { Self.clock(context.date.timeIntervalSince($0.startedAt)) },
                needsApproval: overview.isWaitingForApproval)
            if let info = overview.info {
                row.conversationChrome(info, tags: tags, actions: actions, store: store)
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
