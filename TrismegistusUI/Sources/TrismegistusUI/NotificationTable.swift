import SwiftUI

/// Settings' Notifications (#66, design 12 #settings and #settings-menu): one row per event with its Banner switch, its
/// Sound (a native pop-up: the checked sound opens over the button) and ▶ to hear it; BANNER and SOUND over a head band,
/// a dark foot bar, then the two caption lines.
public struct NotificationTable: View {
    public struct Row: Identifiable {
        public let id: String
        public let title: String
        public let banner: Binding<Bool>
        public let sound: Binding<String>

        public init(id: String, title: String, banner: Binding<Bool>, sound: Binding<String>) {
            self.id = id
            self.title = title
            self.banner = banner
            self.sound = sound
        }
    }

    /// No sound: the event posts none.
    public nonisolated static let none = "None"
    /// The system's notification sound.
    public nonisolated static let standard = "Default"
    /// The built-in macOS sounds (`/System/Library/Sounds`), after None and Default in the menu.
    public nonisolated static let systemSounds = ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop",
                                                  "Purr", "Sosumi", "Submarine", "Tink"]

    let rows: [Row]
    let onPlay: (String) -> Void

    /// `onPlay` gets the row's sound (the button is off for None).
    public init(rows: [Row], onPlay: @escaping (String) -> Void) {
        self.rows = rows
        self.onPlay = onPlay
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(spacing: 0) {
                line(Color.clear, Text("Banner").typeRole(.label), Text("Sound").typeRole(.label), Color.clear)
                .foregroundStyle(Ink.text.primary)
                .frame(height: Size.settings.head)
                .background(Ink.surface.sunken)
                .accessibilityHidden(true)
                ForEach(rows) { row in
                    Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline)
                    line(
                        Text(row.title).typeRole(.body).foregroundStyle(Ink.text.primary).lineLimit(1),
                        Toggle(row.title + " banner", isOn: row.banner).labelsHidden().endfieldSwitch().controlSize(.mini),
                        Picker(row.title + " sound", selection: row.sound) {
                            Text(Self.none).tag(Self.none)
                            Text(Self.standard).tag(Self.standard)
                            Divider()
                            ForEach(Self.systemSounds, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().pickerStyle(.menu).controlSize(.small),
                        Button { onPlay(row.sound.wrappedValue) } label: {
                            Image(systemName: "play.fill").font(.system(size: Icon.xxs, weight: .semibold))
                                .frame(width: Size.settings.play, height: Size.settings.play)
                                .overlay(Rectangle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(row.sound.wrappedValue == Self.none)
                        .help("Play")
                        .accessibilityLabel("Play \(row.title) sound")
                    )
                    .frame(height: Size.settings.row)
                }
                Rectangle().fill(Ink.surface.darkPanel).frame(height: Size.settings.foot)
            }
            .background(Ink.surface.raised)
            .overlay(Rectangle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
            Text("Run banners show only while Trismegistus isn't on screen; sounds play unless you're looking at that chat.")
                .typeRole(.caption).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Focus and System Settings › Notifications apply.")
                .typeRole(.caption).foregroundStyle(Ink.text.secondary)
        }
    }

    /// The table's columns: the event, BANNER, SOUND and ▶.
    private func line(_ event: some View, _ banner: some View, _ sound: some View, _ play: some View) -> some View {
        HStack(spacing: Space.s) {
            event.frame(maxWidth: .infinity, alignment: .leading)
            banner.frame(width: Size.settings.banner, alignment: .leading)
            sound.frame(width: Size.settings.sound, alignment: .leading)
            play.frame(width: Size.settings.play)
        }
        .padding(.horizontal, Space.s)
    }
}

/// A Settings section head (#66, design 12 #settings): an ink slab with the title in yellow tracked caps.
public struct SettingsSlab: View {
    let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title).typeRole(.label).foregroundStyle(Ink.selection)
            .padding(.leading, Space.s)
            .frame(maxWidth: .infinity, minHeight: Size.settings.slab, alignment: .leading)
            .background(Ink.surface.inverse)
            .accessibilityAddTraits(.isHeader)
    }
}
