import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Conversations | chat | terminal pane (inspector).
struct MainWindow: View {
    @Environment(AppModel.self) private var model
    @AppStorage("window.selectedSession") private var selectedSession = ""
    @AppStorage("window.terminalShown") private var terminalShown = true

    private var selection: Binding<String?> {
        Binding(get: { selectedSession.isEmpty ? nil : selectedSession }, set: { selectedSession = $0 ?? "" })
    }

    var body: some View {
        NavigationSplitView {
            ConversationSidebar(selection: selection)
                .topBarColumn(.leadingEdge)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
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
        .frame(minWidth: 1100, minHeight: 640)
        .background(WindowFrameMemory(name: "TrismegistusMainWindow"))
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
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
