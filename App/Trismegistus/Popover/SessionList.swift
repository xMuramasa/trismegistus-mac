import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// `SESSIONS // n` with the new-session button, then the rows (or the empty state, 02b). Rows are a `ScrollView` with
/// a selection of our own (↑↓ move, ↩ opens), not a `List`.
struct SessionList: View {
    /// The relay is unreachable: rows stay, dimmed, as the last known state (02c).
    let isStale: Bool
    @Binding var error: String?
    let onOpen: (String) -> Void
    let onNew: () -> Void

    @Environment(AppModel.self) private var model
    @AppStorage("chat.kind") private var storedKind = ConversationKind.app
    @State private var selection: String?
    @State private var actions = ConversationActions()
    @FocusState private var focused: Bool

    /// One row per thread: its newest part.
    private var sessions: [SessionInfo] { SessionListing.threads(model.sessions, id: \.id, links: model.store?.links ?? [:]) }
    /// The tab's counts and marks over every kind.
    private var summary: ConversationKind.Summary {
        ConversationKind.Summary(sessions.map { session in
            let overview = model.store?.overview[session.id]
            return (source: session.source,
                    attention: ConversationKind.Attention(isWaitingForApproval: overview?.isWaitingForApproval ?? false,
                                                          isRunning: overview?.run != nil))
        })
    }
    /// The window's tab (one choice for both).
    private var kind: ConversationKind { summary.resolving(storedKind) }
    /// The tab's rows, pinned conversations first.
    private var listing: (pinned: [SessionInfo], rest: [SessionInfo]) {
        let kind = self.kind
        return SessionListing.pinnedApart(sessions.filter { kind.includes($0.source) }, isPinned: \.isPinned)
    }
    private var rows: [SessionInfo] {
        let listing = self.listing
        return listing.pinned + listing.rest
    }
    private var isEmpty: Bool { sessions.isEmpty && !isStale }

    var body: some View {
        VStack(spacing: 0) {
            if isEmpty { empty } else { list }
        }
        .confirmsDelete(actions, store: model.store)
        .onChange(of: actions.error) { _, message in
            if let message { error = message }
        }
        .onChange(of: rows.map(\.id)) { old, new in
            // A handed-off conversation leaves the list for the part that continues it.
            if let selection, let tip = model.store?.threadTip(of: selection), tip != selection {
                self.selection = tip
            } else {
                selection = SessionListing.selection(selection, from: old, to: new)
            }
        }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: "\(kind.name) // \(rows.count)").typeRole(.label).foregroundStyle(Ink.text.secondary)
                Spacer()
                EndfieldButton("New session", symbol: Symbol.plus, kind: .quiet, iconOnly: true, shortcut: newShortcut) {
                    onNew()
                }
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            ChatKindTabs(summary: summary, kind: $storedKind)
                .padding(.horizontal, Space.l).padding(.bottom, Space.s)
            if rows.isEmpty {
                Text(kind.emptyText).typeRole(.caption).foregroundStyle(Ink.text.secondary)
                    .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let listing = self.listing
                        LazyVStack(spacing: 1) {
                            if !listing.pinned.isEmpty {
                                SectionLabel(title: "Pinned").background(Ink.surface.window)
                                ForEach(listing.pinned) { entry($0, now: context.date) }
                                SectionLabel(title: "Conversations").background(Ink.surface.window)
                            }
                            ForEach(listing.rest) { entry($0, now: context.date) }
                        }
                    }
                    .background(Ink.line.rule)
                    .opacity(isStale ? Opacity.track : 1)
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.return) { openSelected() }
                .onChange(of: selection) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
        .onAppear { focused = true }
    }

    /// A row, with the tag editor under it while it is open.
    private func entry(_ session: SessionInfo, now: Date) -> some View {
        VStack(spacing: 1) {
            row(session, now: now)
            if actions.tagging == session.id, let store = model.store {
                let tags = store.tags[session.id] ?? []
                TagEditor(
                    tags: tags, known: SessionListing.tagCounts(ids: sessions.map(\.id), tags: store.tags).map(\.tag),
                    onChange: { actions.setTags(session.id, $0, store: store) }, onDone: { actions.tagging = nil })
            }
        }
    }

    private func row(_ session: SessionInfo, now: Date) -> some View {
        let overview = model.store?.overview[session.id]
        let isSelected = session.id == (selection ?? rows.first?.id)
        return SessionRowView(
            name: PopoverFormat.title(session), source: PopoverFormat.source(session.source),
            activity: PopoverFormat.ago(overview?.lastActivity ?? session.lastActive.map(Date.init(timeIntervalSince1970:)), now: now),
            isSelected: isSelected, isReadOnly: session.isReadOnly,
            runElapsed: overview?.run.map { PopoverFormat.elapsed(since: $0.startedAt, now: now) },
            needsApproval: overview?.isWaitingForApproval ?? false
        )
        .id(session.id)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = session.id
            onOpen(session.id)
        }
        .conversationChrome(session, tags: model.store?.tags[session.id] ?? [], isSelected: isSelected, actions: actions, store: model.store)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let rows = self.rows
        guard !rows.isEmpty else { return .ignored }
        let current = rows.firstIndex { $0.id == selection } ?? 0
        selection = rows[min(max(current + delta, 0), rows.count - 1)].id
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        guard let id = selection ?? rows.first?.id else { return .ignored }
        onOpen(id)
        return .handled
    }

    // MARK: Empty (02b)

    private var empty: some View {
        VStack(spacing: Space.m) {
            Spacer()
            TMark().scaleEffect(3).frame(width: Size.emptyMark, height: Size.emptyMark).foregroundStyle(Ink.mark.empty)
            Text("No sessions yet").typeRole(.label).foregroundStyle(Ink.text.primary)
            Text("Start one here. Sessions from Telegram, cron or the CLI show up too, read-only.")
                .typeRole(.callout).foregroundStyle(Ink.text.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, Space.huge)
            EndfieldButton("New session", symbol: Symbol.plus, kind: .primary, shortcut: newShortcut) { onNew() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var newShortcut: KeyboardShortcut { KeyboardShortcut("n") }
}
