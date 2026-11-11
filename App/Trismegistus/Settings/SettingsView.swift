import ServiceManagement
import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// Settings (06): connection, launch at login, notification toggles.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var login = LaunchAtLogin()
    @State private var confirmingUnpair = false
    /// Set by the window's device row (Unpair…): Settings opens and asks at once.
    @AppStorage("settings.confirmUnpair") private var confirmUnpair = false
    @State private var unpairError: String?
    /// Shown after unpairing: the relay still lists the device until this runs on the server.
    @State private var revokeCommand: String?
    // Optional: an absent key reads as its default in NotificationSettings (failed follows finished, the old approval
    // sound switch's off is None).
    @AppStorage(NotificationSettings.Event.approval.bannerKey) private var approvalBanner: Bool?
    @AppStorage(NotificationSettings.Event.finished.bannerKey) private var finishedBanner: Bool?
    @AppStorage(NotificationSettings.Event.failed.bannerKey) private var failedBanner: Bool?
    @AppStorage(NotificationSettings.Event.approval.soundKey) private var approvalSound: String?
    @AppStorage(NotificationSettings.Event.finished.soundKey) private var finishedSound: String?
    @AppStorage(NotificationSettings.Event.failed.soundKey) private var failedSound: String?

    private var deviceName: String { model.deviceName ?? "macbook" }
    private var serverCommand: String { "trismegistus-relay devices revoke \(deviceName)" }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                TitleRule("Settings")
                Text(verbatim: "trismegistus-mac \(version)").typeRole(.caption).foregroundStyle(Ink.text.secondary)
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
            field("Relay", model.relayURL.absoluteString)
            field("Device name", model.deviceName ?? "—")
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
        .onChange(of: confirmUnpair, initial: true) { _, ask in
            if ask { confirmingUnpair = true; confirmUnpair = false }
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
            // The only way to quit while no window is open (a menu bar app has no Dock icon or app menu then).
            EndfieldButton("Quit Trismegistus", symbol: "power", shortcut: KeyboardShortcut("q")) { NSApp.terminate(nil) }
        }
    }

    // MARK: Notifications

    /// #66, design 12 #settings: Banner, Sound and ▶ per event.
    private var notifications: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            section("Notifications")
            NotificationTable(rows: [
                row(.approval, banner: $approvalBanner, sound: $approvalSound),
                row(.finished, banner: $finishedBanner, sound: $finishedSound),
                row(.failed, banner: $failedBanner, sound: $failedSound),
            ], onPlay: NotificationSettings.preview)
        }
    }

    private func row(_ event: NotificationSettings.Event, banner: Binding<Bool?>, sound: Binding<String?>) -> NotificationTable.Row {
        NotificationTable.Row(
            id: event.rawValue, title: event.title,
            banner: Binding(get: { NotificationSettings.banner(event, stored: banner.wrappedValue) }, set: { banner.wrappedValue = $0 }),
            sound: Binding(get: { NotificationSettings.sound(event, stored: sound.wrappedValue) }, set: { name in
                sound.wrappedValue = name
                _ = NotificationSettings.notificationSound(name)  // copied into Library/Sounds now, not at the first run
            }))
    }

    // MARK: Pieces

    private func section(_ title: String) -> some View {
        SettingsSlab(title).padding(.top, Space.xs)
    }

    /// Inter, like everything in Settings since #66 (the draft has no mono).
    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeRole(.callout).foregroundStyle(Ink.text.secondary)
            Text(value)
                .typeRole(.body)
                .foregroundStyle(Ink.text.primary)
                .lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, Space.m)
                .frame(maxWidth: .infinity, minHeight: Size.control, alignment: .leading)
                .background(Ink.surface.sunken)
                .textSelection(.enabled)
        }
    }
}
