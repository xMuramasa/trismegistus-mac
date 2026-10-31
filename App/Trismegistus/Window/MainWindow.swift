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
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            Group {
                if let id = selection.wrappedValue {
                    ChatView(sessionID: id, compact: false, onShowTerminal: { terminalShown = true })
                } else {
                    Text("No conversation selected").typeRole(.caption).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.paper)
                }
            }
            .inspector(isPresented: $terminalShown) {
                TerminalPane(sessionID: selection.wrappedValue)
                    .inspectorColumnWidth(min: 280, ideal: 360, max: 560)
            }
        }
        .selectsChatFromNotifications(model.notifications, selection: selection)
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
            .foregroundStyle(Theme.ink)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) { StatusReadout(link.state, detail: link.detail) }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) { TerminalToggle(isOn: $terminalShown) }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            SettingsLink { Text("Settings") }
                .buttonStyle(EndfieldButtonStyle(.quiet, title: "Settings", symbol: "slider.horizontal.3", iconOnly: true))
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

/// Icon-only terminal button; inverted (ink with yellow) while the pane is shown, like EndfieldButton pressed.
private struct TerminalToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: Symbol.terminal)
                .typeRole(.button)
                .foregroundStyle(isOn ? Theme.yellow : Theme.ink)
                .padding(.vertical, 6).padding(.horizontal, 6)
                .background(isOn ? Theme.ink : Theme.raised)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1))
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
