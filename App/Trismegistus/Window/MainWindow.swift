import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Conversations | chat | terminal pane (inspector). The sidebar is our own column (`SidebarSplit`, #32), not the
/// system's floating glass panel; the toolbar's toggle, the View menu and ⌃⌘S show and hide it.
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @AppStorage("window.selectedSession") private var selectedSession = ""
    @AppStorage("window.terminalShown") private var terminalShown = true
    @AppStorage("window.sidebarShown") private var sidebarShown = true
    @AppStorage("window.sidebarWidth") private var sidebarWidth = 260.0
    @FocusState private var filterFocused: Bool

    private var selection: Binding<String?> {
        Binding(get: { selectedSession.isEmpty ? nil : selectedSession }, set: { selectedSession = $0 ?? "" })
    }

    var body: some View {
        SidebarSplit(isShown: $sidebarShown, width: $sidebarWidth) {
            ConversationSidebar(selection: selection, filterFocus: $filterFocused)
        } detail: {
            Group {
                if selection.wrappedValue == NewsRowView.id {
                    NewsView()
                } else if selection.wrappedValue == CommandsView.id {
                    CommandsView(onOpen: { selection.wrappedValue = $0 })
                } else if let id = selection.wrappedValue {
                    VStack(spacing: 0) {
                        ConversationHeader(sessionID: id)
                        ChatView(sessionID: id, compact: false, onShowTerminal: { terminalShown = true })
                    }
                } else {
                    Text("No conversation selected").typeRole(.caption).foregroundStyle(Theme.muted)
                        .padding(8).background(Theme.paper)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(EndfieldBackdrop())
                }
            }
            // The detail's own grounds (Commands, News, the empty state) reach up under the toolbar and covered the
            // strip there; this draws it back above them. A conversation's header continues it below.
            .topBarColumn(.window)
            .inspector(isPresented: $terminalShown) {
                TerminalPane(sessionID: [NewsRowView.id, CommandsView.id].contains(selectedSession) ? nil : selection.wrappedValue)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
            }
        }
        .endfieldPaper()
        .topBar()
        .providesCommandLog(model)
        .selectsChatFromNotifications(model.notifications, selection: selection)
        .refreshesNews(model)
        .toolbar { toolbar }
        .toolbar(removing: .title)
        .focusedSceneValue(\.sidebar, SidebarActions(isShown: sidebarShown, toggle: toggleSidebar, find: findConversation))
        .frame(minWidth: 1100, minHeight: 640)
        .background(WindowFrameMemory(name: "TrismegistusMainWindow"))
    }

    private func toggleSidebar() {
        withAnimation(SidebarMotion.animation) { sidebarShown.toggle() }
    }

    /// ⌘K: the sidebar's Filter field, showing the sidebar first if it is hidden.
    private func findConversation() {
        guard !sidebarShown else { filterFocused = true; return }
        withAnimation(SidebarMotion.animation) { sidebarShown = true }
        // The field is only in the hierarchy once the sidebar is back.
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            filterFocused = true
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left").typeRole(.button).foregroundStyle(Theme.onSteel)
                    .padding(6).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(sidebarShown ? "Hide sidebar (⌃⌘S)" : "Show sidebar (⌃⌘S)")
            .accessibilityLabel(sidebarShown ? "Hide sidebar" : "Show sidebar")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                Image(nsImage: MenuBarGlyph.image(glyph)).renderingMode(.template).accessibilityHidden(true)
                Text("Trismegistus").typeRole(.heading)
            }
            .foregroundStyle(Theme.onSteel)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) { TopBarStatus(state: link.state, detail: link.detail) }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) { TerminalToggle(isOn: $terminalShown) }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            SettingsLink {
                Image(systemName: "slider.horizontal.3").typeRole(.button).foregroundStyle(Theme.onSteel)
                    .padding(6).contentShape(Rectangle())
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
        case .connecting: return (.reconnecting, host)
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
        case .linked: (Theme.green, "Linked")
        case .reconnecting: (Theme.yellow, "Reconnecting")
        case .offline: (.clear, "Offline")
        }
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7).overlay(Circle().strokeBorder(Theme.onSteel, lineWidth: 1))
            Text(label).typeRole(.label)
            Text(detail).typeRole(.monoSmall).opacity(0.7)
        }
        .foregroundStyle(Theme.onSteel)
        .accessibilityElement(children: .combine)
    }
}

/// Icon-only terminal button on the steel strip; inverted (ink with yellow) while the pane is shown, like
/// EndfieldButton pressed.
private struct TerminalToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: Symbol.terminal)
                .typeRole(.button)
                .foregroundStyle(isOn ? Theme.yellow : Theme.onSteel)
                .padding(.vertical, 6).padding(.horizontal, 6)
                .background(isOn ? Theme.ink : .clear)
                .overlay(Rectangle().strokeBorder(isOn ? Theme.ink : Theme.onSteel, lineWidth: 1))
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
}

extension FocusedValues {
    @Entry var sidebar: SidebarActions?
}

/// View menu: show or hide the sidebar (⌃⌘S, the system's key for it) and ⌘K for the conversations filter. Disabled
/// unless the main window is key.
struct SidebarMenuCommands: Commands {
    @FocusedValue(\.sidebar) private var sidebar

    var body: some Commands {
        CommandGroup(before: .sidebar) {
            Button(sidebar?.isShown == false ? "Show Sidebar" : "Hide Sidebar") { sidebar?.toggle() }
                .keyboardShortcut("s", modifiers: [.control, .command])
                .disabled(sidebar == nil)
            Button("Find Conversation") { sidebar?.find() }
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
