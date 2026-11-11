import SwiftUI

/// One tab of `KindTabs`: `id` is what `onSelect` gets back.
public struct KindChip: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// The SF Symbol that stands for the kind (the app maps kinds to symbols; this package doesn't know them).
    public let symbol: String
    public let count: Int
    public let mark: StickerState?

    public init(id: String, title: String, symbol: String, count: Int, mark: StickerState? = nil) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.count = count
        self.mark = mark
    }

    /// The full name and count: the tooltip, and what VoiceOver reads (with the mark).
    var described: String { "\(title), \(count) \(count == 1 ? "conversation" : "conversations")" }

    var spoken: String { described + (mark.map { ", \($0.spoken)" } ?? "") }
}

/// The popover's kind tabs (#48): a bare row of icons with their counts, in the section bar's language: the selected tab
/// is bright with an ink bar under it, and a dot on the icon's corner says its conversations need you. MORE is a menu of
/// `more`; with one of its entries chosen it shows that entry's icon and count. The full name is the tooltip and what
/// VoiceOver reads. The window has the section panel's Chats group instead (#68).
public struct KindTabs: View {
    let tabs: [KindChip]
    let more: [KindChip]
    /// What the MORE tab shows while no entry of the menu is chosen.
    let moreMark: StickerState?
    let selection: String
    let onSelect: (String) -> Void

    public init(tabs: [KindChip], more: [KindChip], moreMark: StickerState? = nil, selection: String, onSelect: @escaping (String) -> Void) {
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

    private func cell(_ chip: KindChip, isOn: Bool, menu: Bool = false) -> some View { bare(chip, isOn: isOn, menu: menu) }

    /// One popover tab: the icon (with its dot), the count and, for MORE, a chevron; at least `Size.sectionTarget` tall
    /// and the whole cell clickable. MORE with no entry chosen has no count of its own.
    private func bare(_ chip: KindChip, isOn: Bool, menu: Bool) -> some View {
        let icon = isOn ? Ink.text.primary : Ink.text.secondary
        return HStack(spacing: Space.xs) {
            Image(systemName: chip.symbol).font(.system(size: Icon.l))
                .foregroundStyle(icon)
                .overlay(alignment: .topTrailing) { dot(chip.mark).offset(x: Space.xs, y: -Space.xxs) }
            if !(menu && !isOn) { Text(verbatim: "\(chip.count)").typeRole(.monoSmall).foregroundStyle(icon) }
            if menu { Image(systemName: Symbol.chevronDown).font(.system(size: Icon.xxs, weight: .bold)).foregroundStyle(icon) }
        }
        .lineLimit(1).fixedSize()
        .padding(.vertical, Space.s)
        .overlay(alignment: .bottom) {
            if isOn { Rectangle().fill(Ink.line.strong).frame(height: Stroke.accent) }
        }
        .frame(maxWidth: .infinity, minHeight: Size.sectionTarget)
        .contentShape(Rectangle())
    }

    /// A badge on the icon's top-trailing corner, ringed in the ground's colour so it reads apart from the icon.
    @ViewBuilder private func dot(_ mark: StickerState?) -> some View {
        if let mark {
            Group {
                // Failed and done by their shape (#66); approval and a run keep the dot.
                if mark == .failed || mark == .done {
                    StickerGlyph(state: mark).fill(mark.mark).frame(width: Size.sticker.glyph, height: Size.sticker.glyph)
                } else {
                    Circle().fill(mark == .approval ? Ink.marker : Ink.status.online).frame(width: Size.dot, height: Size.dot)
                }
            }
            .padding(Stroke.accent)
            .background(Circle().fill(Ink.surface.window))
            .allowsHitTesting(false)
        }
    }
}
