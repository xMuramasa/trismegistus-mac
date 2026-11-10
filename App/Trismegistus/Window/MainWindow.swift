import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The window in three columns (#68, design 13 #a2): the floating section panel (the five sections, the Chats group
/// with the kinds, the paired device), the list column of the current section, and its detail; in Chat the terminal
/// drawer sits under the detail (#64). There is no top bar: the window's buttons sit in the panel, the device row holds
/// the link, each detail header the terminal and Settings buttons. The panel's toggle, the View menu and ⌃⌘S hide and
/// show it. Each section keeps its own selection.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @AppStorage("window.section") private var section = WindowSection.chat
    @AppStorage(WindowSection.chat.selectionKey) private var selectedSession = ""
    @AppStorage(WindowSection.github.selectionKey) private var selectedIssue = ""
    @AppStorage(WindowSection.agents.selectionKey) private var selectedAgent = ""
    @AppStorage(WindowSection.jobs.selectionKey) private var selectedJob = ""
    /// `""`: all conversations.
    @AppStorage(WindowSection.commands.selectionKey) private var commandsConversation = ""
    /// Chat's kind (App, Telegram, Terminal, One-shots, Cron, a source, All), shared with the popover.
    @AppStorage("chat.kind") private var chatKind = ConversationKind.app
    @AppStorage("window.sidebarShown") private var panelShown = true
    @AppStorage("window.listWidth") private var listWidth = Double(Size.listColumn.default)
    @AppStorage("window.chatsOpen") private var chatsOpen = true
    /// Read by Settings: open its Unpair confirmation (the device row's Unpair).
    @AppStorage("settings.confirmUnpair") private var confirmUnpair = false
    @State private var commandsSearch = ""
    private let terminal = TerminalSession.shared
    /// The session list the Commands log fetched last, for its list's titles.
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
        // The kind of the thread's newest part (the row shown); All stays All, and an unlisted id leaves the kind alone.
        let tip = model.store?.threadTip(of: id) ?? id
        if chatKind != .all, let info = model.sessions.first(where: { $0.id == tip }) { chatKind = ConversationKind(source: info.source) }
    }

    /// The chip's "Show in Commands": this conversation's calls, whatever the search was.
    private func showCommands(_ id: String) {
        commandsSearch = ""
        commandsConversation = id
        section = .commands
    }

    var body: some View {
        WindowColumns(isPanelShown: $panelShown, listWidth: $listWidth) {
            panel
        } list: {
            list.environment(\.revealPanel, panelShown ? nil : PanelReveal(togglePanel))
        } detail: {
            detail
        }
        .ignoresSafeArea()
        .endfieldPaper()
        .background(TrafficLights(origin: lights))
        .providesCommandLog(model)
        .selectsChatFromNotifications(model.notifications, selection: opening)
        .focusedSceneValue(\.sidebar, SidebarActions(isShown: panelShown, toggle: togglePanel, find: { filterFocused = true },
                                                     section: section, select: { section = $0 }, toggleTerminal: toggleTerminal))
        .frame(minWidth: Size.windowMin.width, minHeight: Size.windowMin.height)
        .background(WindowFrameMemory(name: "TrismegistusMainWindow"))
        .onAppear {
            terminal.attach(model)
            // Before sections the side views were selections in Chat's key (`trismegistus.jobs`, …).
            if let old = WindowSection.allCases.first(where: { selectedSession == "trismegistus.\($0.rawValue)" }) {
                section = old
                selectedSession = ""
            }
        }
    }

    /// The window's buttons: centred in the panel's top row, 12 pt in from its edge; with the panel hidden, in the list
    /// header's leading corner.
    private var lights: CGPoint {
        panelShown
            ? CGPoint(x: Space.s + Space.s + Space.m, y: Space.s + Space.s + Size.sectionPanel.row / 2)
            : CGPoint(x: Space.l, y: Size.sidebarHead / 2)
    }

    private var panel: some View {
        let summary = ConversationSidebar.summary(ConversationSidebar.listing(model))
        let kind = summary.resolving(chatKind)
        return SectionPanel(
            section: $section, badges: badges(summary), kinds: (ConversationKind.tabs + summary.more).map { ChatKindTabs.chip($0, summary: summary) },
            kind: kind.rawValue,
            onKind: { id in
                if let picked = ConversationKind(rawValue: id) { chatKind = picked }
                section = .chat
            },
            chatsOpen: $chatsOpen, device: device, onToggle: togglePanel
        ) {
            SettingsLink { Text("Settings…") }
            Button("Unpair…") {
                confirmUnpair = true
                openSettings()
            }
        }
    }

    /// Chat: the strongest state among its conversations; GitHub: Needs check; Agents: running; Jobs: a failed last run.
    private func badges(_ summary: ConversationKind.Summary) -> [WindowSection: PanelBadge] {
        var badges: [WindowSection: PanelBadge] = [:]
        if let attention = summary.total.attention { badges[.chat] = .mark(ChatKindTabs.mark(attention)) }
        if let n = model.github?.board?.needsCheckCount, n > 0 { badges[.github] = .count(n) }
        if let n = model.agents?.runningCount, n > 0 { badges[.agents] = .count(n) }
        if model.jobs?.anyFailed == true { badges[.jobs] = .mark(.failed) }
        return badges
    }

    private var device: DeviceStatus {
        let host = model.relayURL.host() ?? ""
        let (state, detail): (LinkState, String) = switch model.connection {
        case .connected: (.linked, host)
        case .connecting, .reconnecting: (.reconnecting, host)
        case .disconnected: (.offline, "not connected")
        case .authFailed: (.offline, "token refused")
        }
        return DeviceStatus(name: model.deviceName ?? "not paired", state: state, detail: detail)
    }

    @ViewBuilder private var list: some View {
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
            VStack(spacing: 0) {
                if let id = chatSelection.wrappedValue {
                    ConversationHeader(sessionID: id)
                    ChatView(sessionID: id, compact: false, onShowCommands: showCommands)
                } else {
                    Text("No conversation selected").typeRole(.caption).foregroundStyle(Ink.text.muted)
                        .padding(Space.s).background(Ink.surface.window)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(EndfieldBackdrop())
                }
                if terminal.isShown { TerminalDrawer(screen: terminal.screen) }
            }
        case .github: GitHubView(selection: optional($selectedIssue).wrappedValue, onOpen: open)
        case .agents: AgentsView(selection: optional($selectedAgent), onOpen: open)
        case .jobs: JobsView(selection: optional($selectedJob), onOpen: open)
        case .commands:
            CommandsView(conversation: commandsConversation, search: commandsSearch, sessions: $commandSessions, onOpen: open)
        }
    }

    private func togglePanel() {
        withAnimation(Motion.panel) { panelShown.toggle() }
    }

    private func toggleTerminal() {
        guard section == .chat else { return }
        withAnimation(Motion.panel) { terminal.toggle() }
    }
}

/// The detail header's terminal and Settings buttons, wired to the shared shell.
struct DetailTools: View {
    let section: WindowSection

    var body: some View {
        let terminal = TerminalSession.shared
        WindowTools(section: section, terminalOpen: terminal.isShown) {
            withAnimation(Motion.panel) { terminal.toggle() }
        }
    }
}

/// What the window's View menu items act on, from the key main window.
struct SidebarActions {
    let isShown: Bool
    let toggle: @MainActor () -> Void
    let find: @MainActor () -> Void
    let section: WindowSection
    let select: @MainActor (WindowSection) -> Void
    let toggleTerminal: @MainActor () -> Void
}

extension FocusedValues {
    @Entry var sidebar: SidebarActions?
}

/// View menu: the five sections (⌘1…⌘5), show or hide the section panel (⌃⌘S, the system's key for a sidebar), ⌘K for
/// the current section's filter and ⌘⌥T for the terminal drawer (Chat only). Disabled unless the main window is key.
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
            Button("Find in List") { sidebar?.find() }
                .keyboardShortcut("k")
                .disabled(sidebar == nil)
            Button("Toggle Terminal") { sidebar?.toggleTerminal() }
                .keyboardShortcut("t", modifiers: [.command, .option])
                .disabled(sidebar?.section != .chat)
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
