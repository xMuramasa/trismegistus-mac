import SwiftUI

/// What a section's row says at its right: a count (GitHub's Needs check, Agents' running) or a glyph-only tag
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

/// The floating section panel (#69, design 13 #a3): translucent dark-panel grey stepping from 93 % to 86 %, a white
/// hairline, `m` corners and the top-right one cut. At the top the window's buttons (AppKit draws them there) and the
/// sidebar toggle, then `// TRISMEGISTUS ——— v0.9`; then a tree (Martin, 2026-11-10) of 36 pt rows: Chats with its kinds
/// indented under it along a guide line (a chevron folds them), then GitHub, Agents, Jobs and Commands. The deepest
/// current row you can see is lit, with a 3 pt yellow bar at its left edge: the current kind in Chat, Chats itself while
/// folded, else the section. The device row at the bottom.
public struct SectionPanel<DeviceMenu: View>: View {
    @Binding var section: WindowSection
    let badges: [WindowSection: PanelBadge]
    let kinds: [KindChip]
    /// The current kind's id; lit while Chat is the section.
    let kind: String
    let onKind: (String) -> Void
    @Binding var chatsOpen: Bool
    let device: DeviceStatus
    /// `v0.9`, at the end of the label line.
    let version: String
    let onToggle: () -> Void
    let deviceMenu: DeviceMenu

    public init(
        section: Binding<WindowSection>, badges: [WindowSection: PanelBadge], kinds: [KindChip], kind: String,
        onKind: @escaping (String) -> Void, chatsOpen: Binding<Bool>, device: DeviceStatus, version: String,
        onToggle: @escaping () -> Void, @ViewBuilder deviceMenu: () -> DeviceMenu
    ) {
        self._section = section
        self.badges = badges
        self.kinds = kinds
        self.kind = kind
        self.onKind = onKind
        self._chatsOpen = chatsOpen
        self.device = device
        self.version = version
        self.onToggle = onToggle
        self.deviceMenu = deviceMenu()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                IconButton("Hide sidebar (⌃⌘S)", symbol: Symbol.sidebar, onInk: true, action: onToggle)
            }
            .frame(height: Size.rowCompact)
            .padding(.bottom, Space.s)
            LabelLine(title: "Trismegistus", trailing: version, onPanel: true)
                .padding(.leading, Space.m).padding(.trailing, Space.m)
                .frame(height: Size.sectionPanel.label)
                .padding(.bottom, Space.s)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    chatsRow
                    if chatsOpen {
                        VStack(alignment: .leading, spacing: Space.xxs) { ForEach(kinds) { kindRow($0) } }
                            // The tree's guide line, under Chats' icon.
                            .overlay(alignment: .topLeading) {
                                Rectangle().fill(Ink.line.panelGuide).frame(width: Stroke.hairline)
                                    .padding(.leading, Space.m + Icon.panel / 2).padding(.bottom, Space.m)
                                    .accessibilityHidden(true)
                            }
                            .padding(.bottom, Space.s)
                    }
                    ForEach(WindowSection.allCases.filter { $0 != .chat }) { row($0) }
                }
            }
            .scrollIndicators(.never)
            DeviceRow(device: device) { deviceMenu }
        }
        .padding(Space.s)
        .background {
            ZStack {
                ChamferedPanel().fill(LinearGradient(colors: [Ink.surface.panel, Ink.surface.panelLow], startPoint: .top, endPoint: .bottom))
                ChamferedPanel(inset: Stroke.hairlineFine).stroke(Ink.line.panelEdge, lineWidth: Stroke.hairline)
                ChamferedPanel.cut(inset: Stroke.hairlineFine).stroke(Ink.line.panelChamfer, lineWidth: Stroke.hairline)
            }
        }
        .environment(\.onSidebar, false)
    }

    private func row(_ entry: WindowSection) -> some View {
        let current = entry == section
        return Button { section = entry } label: {
            PanelRow(symbol: entry.symbol, title: entry.title, isLit: current, isStrong: current) {
                switch badges[entry] {
                case .count(let n)?: Self.count(n, lit: current)
                case .mark(let state)?: Sticker(state, isBadge: true)
                case nil: EmptyView()
                }
            }
        }
        .buttonStyle(.plain)
        .help(entry.help)
        .accessibilityLabel(entry.title + (badges[entry].map { ", " + Self.spoken($0) } ?? ""))
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func kindRow(_ chip: KindChip) -> some View {
        let current = section == .chat && chip.id == kind
        return Button { onKind(chip.id) } label: {
            PanelRow(symbol: chip.symbol, title: chip.title, isLit: current, isStrong: current, indent: Self.childIndent) {
                if let mark = chip.mark { Sticker(mark, isBadge: true) }
                Self.count(chip.count, lit: current)
            }
        }
        .buttonStyle(.plain)
        .help(chip.described)
        .accessibilityLabel(chip.spoken)
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private static func count(_ n: Int, lit: Bool) -> some View {
        Text(verbatim: "\(n)").typeRole(.callout).monospacedDigit().foregroundStyle(lit ? Ink.text.onPanel : Ink.text.onPanelQuiet)
    }

    /// A kind's icon sits under the Chats label: the row's icon column and its gap.
    public static var childIndent: CGFloat { Icon.panel + Space.m }

    /// Chats, the tree's parent (white, semibold): picks Chat (its current kind); the chevron beside it folds the kinds.
    /// Chat's strongest state shows here only while folded (open, the kinds carry their own).
    private var chatsRow: some View {
        let inChat = section == .chat
        let lit = inChat && !chatsOpen
        return HStack(spacing: Space.xxs) {
            Button { section = .chat } label: {
                PanelRow(symbol: WindowSection.chat.symbol, title: "Chats", isLit: lit, isStrong: true) {
                    if !chatsOpen, case .mark(let state)? = badges[.chat] { Sticker(state, isBadge: true) }
                }
            }
            .buttonStyle(.plain)
            .help(WindowSection.chat.help)
            .accessibilityLabel("Chats" + (!chatsOpen ? badges[.chat].map { ", " + Self.spoken($0) } ?? "" : ""))
            .accessibilityValue(chatsOpen ? "Open" : "Folded")
            .accessibilityAddTraits(inChat ? .isSelected : [])
            FoldButton(isOpen: chatsOpen) { withAnimation(Motion.panel) { chatsOpen.toggle() } }
        }
    }

    static func spoken(_ badge: PanelBadge) -> String {
        switch badge {
        case .count(let n): "\(n)"
        case .mark(let state): state.spoken
        }
    }
}

/// The panel's outline: `m` corners but for the top-right one, cut at 45° (`Size.sectionPanel.chamfer`).
struct ChamferedPanel: Shape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let cut = Size.sectionPanel.chamfer - inset
        var path = Path()
        path.move(to: CGPoint(x: r.minX + Radius.m, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
        path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: Radius.m)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: Radius.m)
        path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: Radius.m)
        path.closeSubpath()
        return path
    }

    /// The cut edge alone, drawn a little brighter than the rest of the hairline.
    static func cut(inset: CGFloat) -> some Shape {
        CutEdge(inset: inset)
    }

    private struct CutEdge: Shape {
        let inset: CGFloat

        func path(in rect: CGRect) -> Path {
            let r = rect.insetBy(dx: inset, dy: inset)
            let cut = Size.sectionPanel.chamfer - inset
            return Path { p in
                p.move(to: CGPoint(x: r.maxX - cut, y: r.minY))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
            }
        }
    }
}

/// The chevron that folds Chats' kinds (`.tfold`): a 30 pt square in contour grey, lit under the pointer.
private struct FoldButton: View {
    let isOpen: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: Symbol.chevronDown).font(.system(size: Icon.l, weight: .semibold))
                .rotationEffect(.degrees(isOpen ? 0 : -90))
                .foregroundStyle(Ink.text.onPanelQuiet)
                .frame(width: Size.control, height: Size.control)
                .background(hovered ? Ink.surface.panelHover : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(isOpen ? "Hide the kinds" : "Show the kinds")
        .accessibilityLabel(isOpen ? "Hide the kinds" : "Show the kinds")
    }
}

/// A 36 pt panel row: icon, label (Inter 13, on-steel; white and semibold when `isStrong`), then what it says at the
/// right. `isLit` marks it current: a lighter row with a 3 pt yellow bar at its left edge. The pointer lights it faintly.
private struct PanelRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let isLit: Bool
    let isStrong: Bool
    /// A child row's leading inset (the kinds under Chats); the light still spans the row.
    var indent: CGFloat = 0
    @ViewBuilder let trailing: () -> Trailing
    @State private var hovered = false

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).font(.system(size: Icon.panel)).frame(width: Icon.panel)
            Text(title).typeRole(.quietTitle, weight: isStrong ? .semibold : nil).lineLimit(1)
            Spacer(minLength: Space.s)
            trailing()
        }
        .foregroundStyle(isStrong ? Ink.text.onPanel : Ink.text.onDark)
        .padding(.leading, Space.m + indent).padding(.trailing, Space.m)
        .frame(height: Size.sectionPanel.row)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(isLit ? Ink.surface.panelRow : hovered ? Ink.surface.panelHover : .clear)
        }
        .overlay(alignment: .leading) {
            if isLit { Rectangle().fill(Ink.selection).frame(width: Stroke.mark).padding(.vertical, Space.s) }
        }
        .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .onHover { hovered = $0 }
    }
}

/// The panel's bottom row: the device's 28 pt avatar, its name, a status dot with `linked · <host>`, and `…` (`menu`:
/// Settings, Unpair) with a faint edge.
public struct DeviceRow<Menu: View>: View {
    let device: DeviceStatus
    let menu: Menu

    public init(device: DeviceStatus, @ViewBuilder menu: () -> Menu) {
        self.device = device
        self.menu = menu()
    }

    public var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: Symbol.device).font(.system(size: Icon.panel)).foregroundStyle(Ink.text.onDark)
                .frame(width: Size.avatar.device, height: Size.avatar.device)
                .rounded(Radius.control, fill: Ink.surface.deviceAvatar)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name).typeRole(.headline).foregroundStyle(Ink.text.onPanel).lineLimit(1)
                HStack(spacing: Space.s) {
                    dot
                    Text(device.line).typeRole(.caption).monospacedDigit().foregroundStyle(Ink.text.onPanelQuiet)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            SwiftUI.Menu { menu } label: { IconCell(symbol: Symbol.ellipsis, onInk: true).edge(Ink.line.panelGuide, radius: Radius.control) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Device")
                .accessibilityLabel("Device actions")
        }
        .padding(.leading, Space.s).padding(.trailing, Space.xs).padding(.top, Space.s).padding(.bottom, Space.xs)
        .frame(minHeight: Size.sectionPanel.device)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line.onDark).frame(height: Stroke.hairline) }
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

/// A 30 pt icon button's face (`.ib`, `control` corners, #69): in the list column white at 70 % with a rule hairline,
/// in a detail header bare with the hairline; on the dark panel bare with an on-steel glyph. `isOn` (a pane that is
/// open) is sunken with a secondary edge. The pointer turns it white with a contour edge. Also a `Menu`'s label.
public struct IconCell: View {
    let symbol: String
    let isOn: Bool
    let onInk: Bool
    @Environment(\.onSidebar) private var onSidebar
    @State private var hovered = false

    public init(symbol: String, isOn: Bool = false, onInk: Bool = false) {
        self.symbol = symbol
        self.isOn = isOn
        self.onInk = onInk
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        let fill = onInk ? (hovered ? Ink.surface.panelHover : .clear)
            : isOn ? Ink.surface.sunken : hovered ? Ink.surface.raised : onSidebar ? Ink.surface.control : .clear
        let edge = onInk ? Color.clear : isOn ? Ink.text.secondary : hovered ? Ink.line.contour : Ink.line.rule
        Image(systemName: symbol).font(.system(size: Icon.section))
            .foregroundStyle(onInk ? Ink.text.onDark : Ink.text.primary)
            .frame(width: Size.control, height: Size.control)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: Stroke.hairline))
            .contentShape(shape)
            .onHover { hovered = $0 }
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
