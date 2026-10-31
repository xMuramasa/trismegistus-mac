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
    @State private var selection: String?
    @State private var renaming: SessionInfo?
    @State private var renameText = ""
    @State private var deleting: SessionInfo?
    @FocusState private var focused: Bool

    private var sessions: [SessionInfo] { model.sessions }
    private var isEmpty: Bool { sessions.isEmpty && !isStale }

    var body: some View {
        VStack(spacing: 0) {
            if isEmpty { empty } else { list }
        }
        .alert("Rename session", isPresented: isPresenting($renaming), presenting: renaming) { session in
            TextField("Title", text: $renameText)
            Button("Rename") { rename(session) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete session?", isPresented: isPresenting($deleting), presenting: deleting) { session in
            Button("Delete", role: .destructive) { delete(session) }
            Button("Cancel", role: .cancel) {}
        } message: { session in
            Text("“\(PopoverFormat.title(session))” is deleted on the relay. This can't be undone.")
        }
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sessions // \(sessions.count)").typeRole(.label).foregroundStyle(Theme.secondary)
                Spacer()
                EndfieldButton("New session", symbol: Symbol.plus, kind: .quiet, iconOnly: true, shortcut: newShortcut) {
                    onNew()
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            ScrollViewReader { proxy in
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LazyVStack(spacing: 1) {
                            ForEach(sessions) { session in
                                row(session, now: context.date)
                            }
                        }
                    }
                    .background(Theme.rule)
                    .opacity(isStale ? 0.5 : 1)
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

    private func row(_ session: SessionInfo, now: Date) -> some View {
        let overview = model.store?.overview[session.id]
        return SessionRowView(
            name: PopoverFormat.title(session), source: PopoverFormat.source(session.source),
            activity: PopoverFormat.ago(overview?.lastActivity ?? session.lastActive.map(Date.init(timeIntervalSince1970:)), now: now),
            isSelected: session.id == (selection ?? sessions.first?.id), isReadOnly: session.isReadOnly,
            runElapsed: overview?.run.map { PopoverFormat.elapsed(since: $0.startedAt, now: now) },
            needsApproval: overview?.isWaitingForApproval ?? false
        )
        .id(session.id)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = session.id
            onOpen(session.id)
        }
        .contextMenu {
            // The relay only lets api_server sessions be renamed or deleted.
            if !session.isReadOnly {
                Button("Rename", systemImage: "pencil") {
                    renameText = session.title ?? ""
                    renaming = session
                }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = session }
            }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !sessions.isEmpty else { return .ignored }
        let current = sessions.firstIndex { $0.id == selection } ?? 0
        selection = sessions[min(max(current + delta, 0), sessions.count - 1)].id
        return .handled
    }

    private func openSelected() -> KeyPress.Result {
        guard let id = selection ?? sessions.first?.id else { return .ignored }
        onOpen(id)
        return .handled
    }

    // MARK: Empty (02b)

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            TMark().scaleEffect(3).frame(width: 42, height: 42).foregroundStyle(Theme.borderInactive)
            Text("No sessions yet").typeRole(.label).foregroundStyle(Theme.ink)
            Text("Start one here. Sessions from Telegram, cron or the CLI show up too, read-only.")
                .typeRole(.callout).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            EndfieldButton("New session", symbol: Symbol.plus, kind: .primary, shortcut: newShortcut) { onNew() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private var newShortcut: KeyboardShortcut { KeyboardShortcut("n") }

    private func rename(_ session: SessionInfo) {
        let title = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renaming = nil
        guard !title.isEmpty, let store = model.store else { return }
        Task {
            do { try await store.renameSession(session.id, to: title) } catch { self.error = message(error) }
        }
    }

    private func delete(_ session: SessionInfo) {
        deleting = nil
        guard let store = model.store else { return }
        Task {
            do { try await store.deleteSession(session.id) } catch { self.error = message(error) }
        }
    }

    private func message(_ error: any Error) -> String {
        (error as? RelayAPIError)?.message ?? "Can't reach the relay."
    }

    private func isPresenting<T>(_ item: Binding<T?>) -> Binding<Bool> {
        Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
    }
}
