import ServiceManagement
import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Settings (06): connection, launch at login, notification toggles.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var login = LaunchAtLogin()
    @State private var confirmingUnpair = false
    @State private var unpairError: String?
    /// Shown after unpairing: the relay still lists the device until this runs on the server.
    @State private var revokeCommand: String?
    @AppStorage(NotificationSettings.approvals) private var approvals = true
    @AppStorage(NotificationSettings.runFinished) private var runFinished = true
    @AppStorage(NotificationSettings.approvalSound) private var approvalSound = true
    @AppStorage(NewsSettings.readerURL) private var newsReaderURL = NewsSettings.defaultReaderURL

    private var deviceName: String { model.deviceName ?? "macbook" }
    private var serverCommand: String { "trismegistus-relay devices revoke \(deviceName)" }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                TitleRule("Settings")
                Text(verbatim: "trismegistus-mac \(version)").typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.l)
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    connection
                    general
                    notifications
                }
                .padding(.horizontal, Space.l).padding(.bottom, Space.l)
            }
            KeyHintStrip([("esc", "close"), ("⌘Q", "quit")])
        }
        .frame(width: Size.settings.width, height: Size.settings.height)
        .background(Ink.surface.window)
        .onAppear { login.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            login.refresh()  // the user may have approved or removed the login item in System Settings
        }
    }

    // MARK: Connection

    private var linkState: (LinkState, String) {
        switch model.connection {
        case .connected: (.linked, model.relayURL.host() ?? "")
        case .connecting, .reconnecting: (.reconnecting, "connecting")
        case .authFailed: (.offline, "token refused")
        case .disconnected: (.offline, "not paired")
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            section("Connection")
            StatusReadout(linkState.0, detail: linkState.1)
            field("Relay", model.relayURL.absoluteString, mono: true)
            field("Device name", model.deviceName ?? "—", mono: false)
            HStack(spacing: Space.m) {
                EndfieldButton("Unpair", symbol: Symbol.unpair, kind: .danger) { confirmingUnpair = true }
                    .disabled(model.store == nil)
                Text("removes the token from this Mac").typeRole(.caption).foregroundStyle(Ink.text.muted)
            }
            if let unpairError { Text(unpairError).typeRole(.caption).foregroundStyle(Ink.text.error) }
            if let revokeCommand {
                Text("The relay still lists this device. To revoke it, run on the server:")
                    .typeRole(.caption).foregroundStyle(Ink.text.secondary)
                CodeBlockView(language: "bash", code: revokeCommand)
            }
        }
        .confirmationDialog("Unpair this Mac?", isPresented: $confirmingUnpair) {
            Button("Unpair", role: .destructive) { Task { await unpair() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
                This removes the token from the Keychain and disconnects. It does not revoke the device on the relay. \
                To do that, run on the server: \(serverCommand)
                """)
        }
    }

    private func unpair() async {
        let command = serverCommand  // the device name is forgotten by unpair()
        do {
            try await model.unpair()
            unpairError = nil
            revokeCommand = command
        } catch {
            unpairError = "Can't remove the token from the Keychain."
        }
    }

    // MARK: General

    private var general: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            section("General")
            Toggle("Launch at login", isOn: Binding(get: { login.isOn }, set: { login.set($0) }))
                .endfieldSwitch().typeRole(.body)
            switch login.status {
            case .requiresApproval:
                HStack(spacing: Space.m) {
                    Text("Waiting for your approval in System Settings.").typeRole(.caption).foregroundStyle(Ink.text.secondary)
                    EndfieldButton("Login Items", symbol: "gearshape") { login.openLoginItems() }
                }
            case .notFound:
                Text("macOS can't find this app as a login item.").typeRole(.caption).foregroundStyle(Ink.text.secondary)
            default:
                EmptyView()
            }
            if let error = login.error { Text(error).typeRole(.caption).foregroundStyle(Ink.text.error) }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("News reader").typeRole(.callout).foregroundStyle(Ink.text.secondary)
                EndfieldTextField(NewsSettings.defaultReaderURL, text: $newsReaderURL)
                Text("empty: News reads the feed runs instead").typeRole(.caption).foregroundStyle(Ink.text.muted)
            }
            // The only way to quit while no window is open (a menu bar app has no Dock icon or app menu then).
            EndfieldButton("Quit Trismegistus", symbol: "power", shortcut: KeyboardShortcut("q")) { NSApp.terminate(nil) }
        }
    }

    // MARK: Notifications

    private var notifications: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            section("Notifications")
            Toggle("Approval requests", isOn: $approvals)
            Toggle("Run finished while closed", isOn: $runFinished)
            Toggle("Sound for approvals", isOn: $approvalSound)
        }
        .endfieldSwitch().typeRole(.body)
    }

    // MARK: Pieces

    private func section(_ title: String) -> some View {
        HStack(spacing: Space.s) {
            Text(title).typeRole(.label).foregroundStyle(Ink.text.secondary)
            Rectangle().fill(Ink.line.rule).frame(height: 1)
        }
        .padding(.top, Space.xs)
        .accessibilityAddTraits(.isHeader)
    }

    private func field(_ label: String, _ value: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeRole(.callout).foregroundStyle(Ink.text.secondary)
            Text(value)
                .typeRole(mono ? .mono : .body)
                .foregroundStyle(mono ? Ink.text.muted : Ink.text.primary)
                .lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, Space.m)
                .frame(maxWidth: .infinity, minHeight: Size.control, alignment: .leading)
                .background(Ink.surface.sunken)
                .textSelection(.enabled)
        }
    }
}
