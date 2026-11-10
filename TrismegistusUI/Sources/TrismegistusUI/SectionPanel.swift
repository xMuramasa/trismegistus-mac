import SwiftUI

/// What a section's row says at its right: a count (GitHub's Needs check, Agents' running) or a glyph-only sticker
/// (Chat's strongest state, Jobs' failed run).
public enum PanelBadge: Equatable, Sendable {
    case count(Int)
    case mark(StickerState)
}

/// The paired device as the panel's bottom row shows it.
public struct DeviceStatus: Equatable, Sendable {
    public let name: String
    public let state: LinkState
    /// The relay's host, or why there is no link.
    public let detail: String

    public init(name: String, state: LinkState, detail: String) {
        self.name = name
        self.state = state
        self.detail = detail
    }

    /// `linked · hermes.lab.x-muramasa.dev`, `connecting · …`, `offline · token refused`.
    public var line: String {
        let word = switch state {
        case .linked: "linked"
        case .reconnecting: "connecting"
        case .offline: "offline"
        }
        return detail.isEmpty ? word : "\(word) · \(detail)"
    }
}

/// The floating section panel (#68, design 13 #a2): ink with `xl` corners and the soft B2 shadow. At the top the window's
/// buttons (AppKit draws them there) and the sidebar toggle; then a tree (Martin, 2026-11-10): Chats with its kinds
/// indented under it (a chevron folds them), then GitHub, Agents, Jobs and Commands, all 40 pt rows. The yellow block is
/// on the deepest current row you can see: the current kind in Chat, Chats itself while folded, else the section. The
/// device row at the bottom.
public struct SectionPanel<DeviceMenu: View>: View {
    @Binding var section: WindowSection
    let badges: [WindowSection: PanelBadge]
    let kinds: [KindChip]
    /// The current kind's id; marked while Chat is the section.
    let kind: String
    let onKind: (String) -> Void
    @Binding var chatsOpen: Bool
    let device: DeviceStatus
    let onToggle: () -> Void
    let deviceMenu: DeviceMenu

    public init(
        section: Binding<WindowSection>, badges: [WindowSection: PanelBadge], kinds: [KindChip], kind: String,
        onKind: @escaping (String) -> Void, chatsOpen: Binding<Bool>, device: DeviceStatus, onToggle: @escaping () -> Void,
        @ViewBuilder deviceMenu: () -> DeviceMenu
    ) {
        self._section = section
        self.badges = badges
        self.kinds = kinds
        self.kind = kind
        self.onKind = onKind
        self._chatsOpen = chatsOpen
        self.device = device
        self.onToggle = onToggle
        self.deviceMenu = deviceMenu()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                IconButton("Hide sidebar (⌃⌘S)", symbol: Symbol.sidebar, onInk: true, action: onToggle)
            }
            .frame(height: Size.sectionPanel.row)
            .padding(.bottom, Space.s)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    chatsRow
                    if chatsOpen {
                        ForEach(kinds) { kindRow($0) }
                    }
                    ForEach(WindowSection.allCases.filter { $0 != .chat }) { row($0) }
                }
            }
            .scrollIndicators(.never)
            DeviceRow(device: device) { deviceMenu }
        }
        .padding(Space.s)
        .background {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(Ink.surface.panel).shadow(Shadow.block)
        }
        .environment(\.onSidebar, false)
    }

    private func row(_ entry: WindowSection) -> some View {
        let current = entry == section
        return Button { section = entry } label: {
            PanelRow(symbol: entry.symbol, title: entry.title, fill: current ? Ink.selection : nil, bold: current) {
                switch badges[entry] {
                case .count(let n)?:
                    Text(verbatim: "\(n)").typeRole(.body).monospacedDigit().foregroundStyle(current ? Ink.text.primary : Ink.text.muted)
                case .mark(let state)?:
                    Sticker(state, isBadge: true, edge: current ? Ink.line.strong : Ink.text.onDark)
                case nil:
                    EmptyView()
                }
            }
            .foregroundStyle(current ? Ink.text.primary : Ink.text.onPanel)
        }
        .buttonStyle(.plain)
        .help(entry.help)
        .accessibilityLabel(entry.title + (badges[entry].map { ", " + Self.spoken($0) } ?? ""))
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func kindRow(_ chip: KindChip) -> some View {
        let current = section == .chat && chip.id == kind
        return Button { onKind(chip.id) } label: {
            PanelRow(symbol: chip.symbol, title: chip.title, fill: current ? Ink.selection : nil, bold: current,
                     indent: Self.childIndent) {
                if let mark = chip.mark { Sticker(mark, isBadge: true, edge: current ? Ink.line.strong : Ink.text.onDark) }
                Text(verbatim: "\(chip.count)").typeRole(.body, weight: current ? .bold : nil).monospacedDigit()
                    .foregroundStyle(current ? Ink.text.primary : Ink.text.muted)
            }
            .foregroundStyle(current ? Ink.text.primary : Ink.text.onPanel)
        }
        .buttonStyle(.plain)
        .help(chip.described)
        .accessibilityLabel(chip.spoken)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    /// A kind's icon sits under the Chats label: the row's icon column and its gap.
    public static var childIndent: CGFloat { Icon.panel + Space.m }

    /// Chats, the tree's parent: picks Chat (its current kind); the chevron at the right folds the kinds. Chat's
    /// strongest state shows here only while folded (open, the kinds carry their own).
    private var chatsRow: some View {
        let inChat = section == .chat
        let filled = inChat && !chatsOpen
        return Button { section = .chat } label: {
            PanelRow(symbol: WindowSection.chat.symbol, title: "Chats", fill: filled ? Ink.selection : nil,
                     bold: inChat) {
                if !chatsOpen, case .mark(let state)? = badges[.chat] {
                    Sticker(state, isBadge: true, edge: filled ? Ink.line.strong : Ink.text.onDark)
                }
                Color.clear.frame(width: Icon.panel, height: Icon.panel) // the chevron's place (an overlay: its own button)
            }
            .foregroundStyle(filled ? Ink.text.primary : Ink.text.onPanel)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Button { withAnimation(Motion.panel) { chatsOpen.toggle() } } label: {
                Image(systemName: Symbol.chevronDown).font(.system(size: Icon.m, weight: .semibold))
                    .rotationEffect(.degrees(chatsOpen ? 0 : -90))
                    .frame(width: Icon.panel, height: Icon.panel)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(filled ? Ink.text.primary : Ink.text.onPanel)
            .padding(.trailing, Space.m)
            .help(chatsOpen ? "Hide the kinds" : "Show the kinds")
            .accessibilityLabel(chatsOpen ? "Hide the kinds" : "Show the kinds")
        }
        .help(WindowSection.chat.help)
        .accessibilityLabel("Chats" + (!chatsOpen ? badges[.chat].map { ", " + Self.spoken($0) } ?? "" : ""))
        .accessibilityValue(chatsOpen ? "Open" : "Folded")
        .accessibilityAddTraits(inChat ? .isSelected : [])
    }

    static func spoken(_ badge: PanelBadge) -> String {
        switch badge {
        case .count(let n): "\(n)"
        case .mark(let state): state.spoken
        }
    }
}

/// A 40 pt panel row: icon, label, then what it says at the right; `fill` marks it current. The pointer gives it the
/// dark-panel ground.
private struct PanelRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let fill: Color?
    let bold: Bool
    /// A child row's leading inset (the kinds under Chats); the fill still spans the row.
    var indent: CGFloat = 0
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).font(.system(size: Icon.panel)).frame(width: Icon.panel)
            Text(title).typeRole(.panelRow, weight: bold ? .bold : nil).lineLimit(1)
            Spacer(minLength: Space.s)
            trailing()
        }
        .padding(.leading, Space.m + indent).padding(.trailing, Space.m)
        .frame(height: Size.sectionPanel.row)
        .background {
            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                .fill(fill ?? (hovered ? Ink.surface.panelRow : .clear))
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .onHover { hovered = $0 }
    }
}

/// The panel's bottom row: the device's rounded-square avatar, its name, a status dot with `linked · <host>`, and `…`
/// (`menu`: Settings, Unpair).
public struct DeviceRow<Menu: View>: View {
    let device: DeviceStatus
    let menu: Menu

    public init(device: DeviceStatus, @ViewBuilder menu: () -> Menu) {
        self.device = device
        self.menu = menu()
    }

    public var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: Symbol.device).font(.system(size: Icon.panel)).foregroundStyle(Ink.text.onPanel)
                .frame(width: Size.avatar.device, height: Size.avatar.device)
                .rounded(Radius.s, fill: Ink.surface.panelRow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name).typeRole(.panelRow, weight: .bold).foregroundStyle(Ink.text.onPanel).lineLimit(1)
                HStack(spacing: Space.s) {
                    dot
                    Text(device.line).typeRole(.callout).foregroundStyle(Ink.text.onDark).lineLimit(1).truncationMode(.tail)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            SwiftUI.Menu { menu } label: { IconCell(symbol: Symbol.ellipsis, onInk: true) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Device")
                .accessibilityLabel("Device actions")
        }
        .padding(.leading, Space.s).padding(.trailing, Space.xs).padding(.top, Space.s).padding(.bottom, Space.xs)
        .frame(minHeight: Size.sectionPanel.device)
        .overlay(alignment: .top) { Rectangle().fill(Ink.surface.panelRow).frame(height: Stroke.hairline) }
    }

    /// Green linked, yellow while connecting, hollow offline: the word says it too.
    private var dot: some View {
        Circle()
            .fill(device.state == .linked ? Ink.status.online : device.state == .reconnecting ? Ink.selection : .clear)
            .overlay { if device.state == .offline { Circle().strokeBorder(Ink.text.onDark, lineWidth: Stroke.hairline) } }
            .frame(width: Size.marker, height: Size.marker)
            .accessibilityHidden(true)
    }
}

/// A 30 pt icon button's face (`.ib`, `m` corners): sunken with an ink glyph on paper, bare with a white glyph on the ink
/// panel; `isOn` (a pane that is open) is ink with a white glyph. Also a `Menu`'s label.
public struct IconCell: View {
    let symbol: String
    let isOn: Bool
    let onInk: Bool

    public init(symbol: String, isOn: Bool = false, onInk: Bool = false) {
        self.symbol = symbol
        self.isOn = isOn
        self.onInk = onInk
    }

    public var body: some View {
        Image(systemName: symbol).font(.system(size: Icon.section))
            .foregroundStyle(isOn || onInk ? Ink.text.onPanel : Ink.text.primary)
            .frame(width: Size.control, height: Size.control)
            .background {
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(isOn ? Ink.surface.inverse : onInk ? .clear : Ink.surface.sunken)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
    }
}

/// `IconCell` as a button, the word as tooltip and accessibility label.
public struct IconButton: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let onInk: Bool
    let action: () -> Void

    public init(_ title: String, symbol: String, isOn: Bool = false, onInk: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isOn = isOn
        self.onInk = onInk
        self.action = action
    }

    public var body: some View {
        Button(action: action) { IconCell(symbol: symbol, isOn: isOn, onInk: onInk) }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
