import SwiftUI

/// What a kind chip says it needs: a run is going (green) or an approval waits (magenta, wins).
public enum KindMark: Sendable {
    case running, approval
}

/// One tab of `KindTabs`: `id` is what `onSelect` gets back.
public struct KindChip: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// The SF Symbol that stands for the kind (the app maps kinds to symbols; this package doesn't know them).
    public let symbol: String
    public let count: Int
    public let mark: KindMark?

    public init(id: String, title: String, symbol: String, count: Int, mark: KindMark? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.count = count
        self.mark = mark
    }

    /// The full name and count: the tooltip, and what VoiceOver reads (with the mark).
    var described: String { "\(title), \(count) \(count == 1 ? "conversation" : "conversations")" }

    var spoken: String { described + (mark.map { $0 == .approval ? ", approval waiting" : ", running" } ?? "") }
}

/// The chat list's kind tabs (#48): a bare row of icons with their counts, in the section bar's language. The selected
/// tab is bright with a bar under it (yellow on the sidebar, ink off it), and a dot on the icon's corner says its
/// conversations need you. MORE is a menu of `more`; with one of its entries chosen it shows that entry's icon and
/// count. The full name is the tooltip and what VoiceOver reads.
public struct KindTabs: View {
    let tabs: [KindChip]
    let more: [KindChip]
    /// What the MORE tab shows while no entry of the menu is chosen.
    let moreMark: KindMark?
    let selection: String
    let onSelect: (String) -> Void

    @Environment(\.onSidebar) private var onSidebar

    public init(tabs: [KindChip], more: [KindChip], moreMark: KindMark? = nil, selection: String, onSelect: @escaping (String) -> Void) {
        self.tabs = tabs
        self.more = more
        self.moreMark = moreMark
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button { onSelect(tab.id) } label: { cell(tab, isOn: selection == tab.id) }
                    .buttonStyle(.plain)
                    .help(tab.described)
                    .accessibilityLabel(tab.spoken)
                    .accessibilityAddTraits(selection == tab.id ? .isSelected : [])
            }
            moreMenu
        }
    }

    private var moreMenu: some View {
        let chosen = more.first { $0.id == selection }
        return Menu {
            ForEach(more) { entry in
                // A toggle gives the native checkmark and keeps the symbol.
                Toggle(isOn: Binding(get: { entry.id == selection }, set: { _ in onSelect(entry.id) })) {
                    Label("\(entry.title)  \(entry.count)", systemImage: entry.symbol)
                }
            }
        } label: {
            cell(chosen ?? KindChip(id: "", title: "More", symbol: Symbol.more, count: 0, mark: moreMark), isOn: chosen != nil, menu: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help(chosen?.described ?? "More conversations")
        .accessibilityLabel(chosen?.spoken ?? "More conversations")
    }

    private var ground: Color { onSidebar ? Ink.surface.sidebar : Ink.surface.window }

    /// One tab: the icon (with its dot), the count and, for MORE, a chevron; at least `Size.sectionTarget` tall and the
    /// whole cell clickable. MORE with no entry chosen has no count of its own.
    private func cell(_ chip: KindChip, isOn: Bool, menu: Bool = false) -> some View {
        let bright = onSidebar ? Ink.text.onSidebar : Ink.text.primary
        let icon = isOn ? bright : (onSidebar ? Ink.icon.onSidebar : Ink.text.secondary)
        let count = isOn ? bright : (onSidebar ? Ink.text.onSidebarSecondary : Ink.text.secondary)
        return HStack(spacing: Space.xs) {
            Image(systemName: chip.symbol).font(.system(size: Icon.l))
                .foregroundStyle(icon)
                .overlay(alignment: .topTrailing) { dot(chip.mark).offset(x: Space.xs, y: -Space.xxs) }
            if !(menu && !isOn) { Text(verbatim: "\(chip.count)").typeRole(.monoSmall).foregroundStyle(count) }
            if menu { Image(systemName: Symbol.chevronDown).font(.system(size: Icon.xxs, weight: .bold)).foregroundStyle(count) }
        }
        .lineLimit(1).fixedSize()
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) {
            if isOn { Rectangle().fill(onSidebar ? Ink.selection : Ink.line.strong).frame(height: Stroke.accent) }
        }
        .frame(maxWidth: .infinity, minHeight: Size.sectionTarget)
        .contentShape(Rectangle())
    }

    /// A badge on the icon's top-trailing corner, ringed in the ground's colour so it reads apart from the icon.
    @ViewBuilder private func dot(_ mark: KindMark?) -> some View {
        if let mark {
            Circle().fill(mark == .approval ? Ink.marker : Ink.status.online)
                .frame(width: Size.dot, height: Size.dot)
                .padding(Stroke.accent)
                .background(Circle().fill(ground))
                .allowsHitTesting(false)
        }
    }
}
