import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Five sections (#41, #57: Chat, GitHub, Agents, Jobs, Commands), each with its own sidebar list and detail; the
/// terminal pane follows Chat's conversation. The sidebar is our own column (`SidebarSplit`, #32), not the system's
/// floating glass panel; the toolbar's toggle, the View menu and ⌃⌘S show and hide it, with the section bar at its
/// bottom. Each section keeps its own selection.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @AppStorage("window.section") private var section = WindowSection.chat
    @AppStorage(WindowSection.chat.selectionKey) private var selectedSession = ""
    @AppStorage(WindowSection.github.selectionKey) private var selectedIssue = ""
    @AppStorage(WindowSection.agents.selectionKey) private var selectedAgent = ""
    @AppStorage(WindowSection.jobs.selectionKey) private var selectedJob = ""
    /// `""`: all conversations.
    @AppStorage(WindowSection.commands.selectionKey) private var commandsConversation = ""
    /// Chat's tab (APP, TELEGRAM, TERMINAL or a MORE entry), shared with the popover.
    @AppStorage("chat.kind") private var chatKind = ConversationKind.app
    @AppStorage("window.terminalShown") private var terminalShown = true
    @AppStorage("window.terminalWidth") private var terminalWidth = Double(Size.terminal.default)
    @AppStorage("window.sidebarShown") private var sidebarShown = true
    @AppStorage("window.sidebarWidth") private var sidebarWidth = Double(Size.sidebar.default)
    @State private var commandsSearch = ""
    /// The session list the Commands log fetched last, for its sidebar's titles.
    @State private var commandSessions: [SessionInfo]?
    @FocusState private var filterFocused: Bool

    /// A stored selection as the lists take it: `""` is none.
    private func optional(_ value: Binding<String>) -> Binding<String?> {
        Binding(get: { value.wrappedValue.isEmpty ? nil : value.wrappedValue }, set: { value.wrappedValue = $0 ?? "" })
    }

    private var chatSelection: Binding<String?> { optional($selectedSession) }

    /// Commands' "All conversations" row is tagged `""`.
    private var commandsSelection: Binding<String?> {
        Binding(get: { commandsConversation }, set: { commandsConversation = $0 ?? "" })
    }

    /// A notification's chat, or a conversation opened from Jobs, GitHub, Agents or Commands.
    private var opening: Binding<String?> {
        Binding(get: { chatSelection.wrappedValue }, set: { $0.map(open) })
    }

    private func open(_ id: String) {
        section = .chat
        selectedSession = id
        // The tab of the thread's newest part (the row shown); All stays All, and an unlisted id leaves the tab alone.
        let tip = model.store?.threadTip(of: id) ?? id
        if chatKind != .all, let info = model.sessions.first(where: { $0.id == tip }) { chatKind = ConversationKind(source: info.source) }
    }

    var body: some View {
        SidebarSplit(isShown: $sidebarShown, width: $sidebarWidth) {
            VStack(spacing: 0) {
                sidebar
                footer
                SectionBar(selection: $section)
            }
        } detail: {
            TrailingSplit(isShown: $terminalShown, width: $terminalWidth) {
                detail
                    // The detail's own grounds (Commands, Jobs, the empty state) reach up under the toolbar and
                    // covered the strip there; this draws it back above them.
                    .topBarColumn(.window)
            } pane: {
                TerminalPane(sessionID: section == .chat ? chatSelection.wrappedValue : nil)
            }
        }
        .endfieldPaper()
        .topBar()
        .providesCommandLog(model)
        .selectsChatFromNotifications(model.notifications, selection: opening)
        .toolbar { toolbar }
        .toolbar(removing: .title)
        .focusedSceneValue(\.sidebar, SidebarActions(isShown: sidebarShown, toggle: toggleSidebar, find: findInSidebar,
                                                     section: section, select: { section = $0 }))
        .frame(minWidth: Size.windowMin.width, minHeight: Size.windowMin.height)
        .background(WindowFrameMemory(name: "TrismegistusMainWindow"))
        .onAppear {
            // Before sections the side views were selections in Chat's key (`trismegistus.jobs`, …).
            if let old = WindowSection.allCases.first(where: { selectedSession == "trismegistus.\($0.rawValue)" }) {
                section = old
                selectedSession = ""
            }
        }
    }

    @ViewBuilder private var sidebar: some View {
        switch section {
        case .chat: ConversationSidebar(selection: chatSelection, filterFocus: $filterFocused)
        case .github: GitHubSidebar(selection: optional($selectedIssue), filterFocus: $filterFocused)
        case .agents: AgentsSidebar(selection: optional($selectedAgent), filterFocus: $filterFocused)
        case .jobs: JobsSidebar(selection: optional($selectedJob), filterFocus: $filterFocused)
        case .commands:
            CommandsSidebar(selection: commandsSelection, search: $commandsSearch, sessions: commandSessions,
                            filterFocus: $filterFocused)
        }
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .chat:
            if let id = chatSelection.wrappedValue {
                VStack(spacing: 0) {
                    ConversationHeader(sessionID: id)
                    ChatView(sessionID: id, compact: false, onShowTerminal: { withAnimation(Motion.panel) { terminalShown = true } })
                }
            } else {
                Text("No conversation selected").typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .padding(Space.s).background(Ink.surface.window)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(EndfieldBackdrop())
            }
        case .github: GitHubView(selection: optional($selectedIssue).wrappedValue, onOpen: open)
        case .agents: AgentsView(selection: optional($selectedAgent), onOpen: open)
        case .jobs: JobsView(selection: optional($selectedJob), onOpen: open)
        case .commands:
            CommandsView(conversation: commandsConversation, search: commandsSearch, sessions: $commandSessions, onOpen: open)
        }
    }

    /// The paired device, above the section bar.
    private var footer: some View {
        Text(model.deviceName.map { "\($0) · paired" } ?? "not paired")
            .typeRole(.monoSmall).foregroundStyle(Ink.text.onSidebarSecondary)
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Ink.line.onSidebar).frame(height: Stroke.hairline) }
    }

    private func toggleSidebar() {
        withAnimation(Motion.panel) { sidebarShown.toggle() }
    }

    /// ⌘K: the current section's filter field, showing the sidebar first if it is hidden.
    private func findInSidebar() {
        guard !sidebarShown else { filterFocused = true; return }
        withAnimation(Motion.panel) { sidebarShown = true }
        // The field is only in the hierarchy once the sidebar is back.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            filterFocused = true
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left").typeRole(.button).foregroundStyle(Ink.text.onDark)
                    .padding(Space.s).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sidebarShown ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)")
            .accessibilityLabel(sidebarShown ? "Hide sidebar" : "Show sidebar")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .navigation) {
            HStack(spacing: Space.s) {
                Image(nsImage: MenuBarGlyph.image(glyph)).renderingMode(.template).accessibilityHidden(true)
                Text("Trismegistus").typeRole(.heading)
            }
            .foregroundStyle(Ink.text.onDark)
        }
        .sharedBackgroundVisibility(.hidden)
        // macOS 26 packs the trailing items right after the title without it (Martin's screenshot); with it they sit
        // at the window's right edge.
        ToolbarSpacer(.flexible)
        ToolbarItem(placement: .primaryAction) { TopBarStatus(state: link.state, detail: link.detail) }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) { TerminalToggle(isOn: $terminalShown) }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Image(systemName: "slider.horizontal.3").typeRole(.button).foregroundStyle(Ink.text.onDark)
                    .padding(Space.s).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var glyph: GlyphState {
        switch model.store?.activity {
        case .idle: .idle
        case .running: .running
        case .approvalWaiting: .approval
        case .disconnected, nil: .disconnected
        }
    }

    private var link: (state: LinkState, detail: String) {
        let host = model.relayURL.host() ?? ""
        switch model.connection {
        case .connected: return (.linked, host)
        case .connecting, .reconnecting: return (.reconnecting, host)
        case .disconnected: return (.offline, "not connected")
        case .authFailed: return (.offline, "token refused")
        }
    }
}

/// `StatusReadout` in light on the steel strip.
private struct TopBarStatus: View {
    let state: LinkState
    let detail: String

    var body: some View {
        let (dot, label): (Color, String) = switch state {
        case .linked: (Ink.status.online, "Linked")
        case .reconnecting: (Ink.selection, "Reconnecting")
        case .offline: (.clear, "Offline")
        }
        HStack(spacing: Space.s) {
            Circle().fill(dot).frame(width: Size.dot, height: Size.dot).overlay(Circle().strokeBorder(Ink.text.onDark, lineWidth: Stroke.hairline))
            Text(label).typeRole(.label)
            Text(detail).typeRole(.monoSmall).opacity(Opacity.secondaryOnDark)
        }
        .foregroundStyle(Ink.text.onDark)
        .accessibilityElement(children: .combine)
    }
}

/// Icon-only terminal button on the steel strip; inverted (ink with yellow) while the pane is shown, like
/// EndfieldButton pressed.
private struct TerminalToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { withAnimation(Motion.panel) { isOn.toggle() } } label: {
            Image(systemName: Symbol.terminal)
                .typeRole(.button)
                .foregroundStyle(isOn ? Ink.selection : Ink.text.onDark)
                .padding(.vertical, Space.s).padding(.horizontal, Space.s)
                .background(isOn ? Ink.surface.inverse : .clear)
                .overlay(Rectangle().strokeBorder(isOn ? Ink.line.strong : Ink.text.onDark, lineWidth: Stroke.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut("t", modifiers: [.command, .option])
        .help("Terminal (⌥⌘T)")
        .accessibilityLabel("Terminal")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// What the window's View menu items act on, from the key main window.
struct SidebarActions {
    let isShown: Bool
    let toggle: @MainActor () -> Void
    let find: @MainActor () -> Void
    let section: WindowSection
    let select: @MainActor (WindowSection) -> Void
}

extension FocusedValues {
    @Entry var sidebar: SidebarActions?
}

/// View menu: the five sections (⌘1…⌘5), show or hide the sidebar (⌃⌘S, the system's key for it) and ⌘K for the
/// current section's filter. Disabled unless the main window is key.
struct SidebarMenuCommands: Commands {
    @FocusedValue(\.sidebar) private var sidebar

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            ForEach(WindowSection.allCases) { section in
                Toggle(section.title, isOn: Binding(get: { sidebar?.section == section }, set: { _ in sidebar?.select(section) }))
                    .keyboardShortcut(section.key)
                    .disabled(sidebar == nil)
            }
            Divider()
            Button(sidebar?.isShown == false ? "Show Sidebar" : "Hide Sidebar") { sidebar?.toggle() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(sidebar == nil)
            Button("Find in Sidebar") { sidebar?.find() }
                .keyboardShortcut("k")
                .disabled(sidebar == nil)
        }
    }
}

/// Saves and restores the window's frame under `name` (the SwiftUI `Window` scene doesn't promise to).
private struct WindowFrameMemory: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor [weak view] in
            guard let window = view?.window else { return }
            window.setFrameUsingName(name)
            window.setFrameAutosaveName(name)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
