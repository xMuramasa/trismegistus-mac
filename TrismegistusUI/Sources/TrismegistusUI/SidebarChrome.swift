import SwiftUI

public extension EnvironmentValues {
    /// The pointer is over this conversation row. `conversationChrome` sets it for the card under the row's overlays.
    @Entry var rowHovered = false
    /// Set while the section panel is hidden: the list header leaves room for the window's buttons and shows the
    /// sidebar toggle, which calls it.
    @Entry var revealPanel: PanelReveal? = nil
}

/// The action that shows the section panel again. Always equal to another: only being set or not is a change, so the
/// environment doesn't invalidate the lists on every update.
public struct PanelReveal: Equatable {
    let action: @MainActor () -> Void

    public init(_ action: @escaping @MainActor () -> Void) { self.action = action }

    public static func == (a: Self, b: Self) -> Bool { true }
}

public extension View {
    /// A list column `List`: keyboard selection as before, no ground of its own.
    func sidebarList() -> some View { listStyle(.plain).scrollContentBackground(.hidden) }

    /// A row of a list column, edge to edge. Every row sets `listRowBackground`: it replaces the row view's ground,
    /// where macOS draws its selection highlight (a thin blue line showed past the rows otherwise).
    func sidebarRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Ink.surface.sidebar)
    }

    /// A conversation card's cell: 2 pt above and under the 56 pt card, a 60 pt pitch (#68). A `List` clips each row,
    /// so the selected card's cell is 8 pt taller on each side for its frame and arcs. The backing runs under the list's
    /// 8 pt side margins, where macOS still draws its selection highlight (`RowGround`).
    func sidebarCardCell(isSelected: Bool = false) -> some View {
        padding(.vertical, isSelected ? Space.s : Space.xxs).background { Ink.surface.sidebar.padding(.horizontal, -Space.s) }
    }
}

/// `APP // 10`: ExtraBold ink, the slashes secondary and lighter (#68). A title that doesn't fit shrinks rather than
/// truncating its count.
public struct SidebarTitle: View {
    let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        var text = AttributedString(title.uppercased())
        if let slashes = text.range(of: "//") {
            text[slashes].foregroundColor = Ink.text.secondary
            text[slashes].font = TypeRole.columnTitle.spec.font(weight: .semibold)
        }
        return Text(text).typeRole(.columnTitle).monospacedDigit()
            .foregroundStyle(Ink.text.onSidebar)
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The list column's header (#68): `leading` (`…`; first, while the panel is hidden, room for the window's buttons and
/// the sidebar toggle), the title centred, `trailing` (the yellow `+`, a section's own actions). Both sides take the
/// same width, so the title stays in the middle.
public struct ListHeader<Leading: View, Trailing: View>: View {
    let title: String
    let leading: Leading
    let trailing: Trailing
    @Environment(\.revealPanel) private var revealPanel

    public init(title: String, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                if let revealPanel {
                    Color.clear.frame(width: Size.trafficLights, height: Size.control).accessibilityHidden(true)
                    IconButton("Show sidebar (⌃⌘S)", symbol: Symbol.sidebar) { revealPanel.action() }
                }
                leading
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SidebarTitle(title).layoutPriority(1)
            HStack(spacing: Space.s) { trailing }.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, Space.l)
        .frame(height: Size.sidebarHead)
    }
}

/// The list header's `+`: a yellow `m` square with an ink edge and glyph, the region's primary action. While the open
/// conversation runs Steer is the yellow action, and `+` steps down to white (#68).
public struct PlusButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void

    public init(_ title: String, isPrimary: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isPrimary = isPrimary
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: Symbol.plus).font(.system(size: Icon.panel)).foregroundStyle(Ink.text.primary)
                .frame(width: Size.control, height: Size.control)
                .rounded(Radius.m, fill: isPrimary ? Ink.selection : Ink.surface.raised, edge: Ink.line.strong)
                .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// An ink slab in the list column (PINNED, CONVERSATIONS): inset 8 pt like the cards, `m` corners, a yellow square and
/// label (with a fold chevron when the group folds), the group's count at the right.
public struct SectionHead: View {
    let title: String
    let count: Int?
    let folded: Bool?

    public init(title: String, count: Int? = nil, folded: Bool? = nil) {
        self.title = title
        self.count = count
        self.folded = folded
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Rectangle().fill(Ink.selection).frame(width: Size.marker, height: Size.marker)
            Text(title).typeRole(.sectionHead).foregroundStyle(Ink.selection).lineLimit(1)
            if let folded {
                Image(systemName: Symbol.fold(isOpen: !folded)).font(.system(size: Icon.xxs, weight: .bold)).foregroundStyle(Ink.selection)
            }
            Spacer(minLength: Space.s)
            if let count { Text(verbatim: "\(count)").typeRole(.sectionHead).monospacedDigit().foregroundStyle(Ink.text.muted) }
        }
        .padding(.horizontal, Space.l)
        .frame(height: Size.sectionHead)
        .rounded(Radius.m, fill: Ink.surface.inverse)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A tag. In the list column a sunken chip with `s` corners in Inter (dark-panel on the selected ink card); elsewhere
/// mono on sunken. `isOn` (a filter's choice, an editor's toggle) is ink with yellow text.
public struct TagChip: View {
    let tag: String
    let isOn: Bool
    let onInk: Bool
    let weight: Font.Weight?

    @Environment(\.onSidebar) private var onSidebar

    public init(tag: String, isOn: Bool = false, onInk: Bool = false, weight: Font.Weight? = nil) {
        self.tag = tag
        self.isOn = isOn
        self.onInk = onInk
        self.weight = weight
    }

    public var body: some View {
        let fill = isOn ? Ink.surface.inverse : onInk ? Ink.surface.darkPanel : Ink.surface.sunken
        Text(tag).typeRole(onSidebar ? .caption : .monoSmall, weight: onSidebar ? weight ?? .medium : weight).monospacedDigit().lineLimit(1)
            .foregroundStyle(isOn ? Ink.selection : onInk ? Ink.text.onDark : Ink.text.secondary)
            .padding(.horizontal, onSidebar ? Space.xs : Space.s).padding(.vertical, onSidebar ? 0 : 1)
            .frame(minHeight: onSidebar ? Size.chip : nil)
            .rounded(onSidebar ? Radius.s : Radius.none, fill: fill, edge: isOn ? Ink.line.strong : onSidebar ? .clear : Ink.line.rule)
    }
}

/// Up to `limit` chips, then `+N`.
public struct TagChips: View {
    let tags: [String]
    let limit: Int
    let weight: Font.Weight?
    let overflow: Color
    let onInk: Bool

    @Environment(\.onSidebar) private var onSidebar

    public init(tags: [String], limit: Int = 2, weight: Font.Weight? = nil, overflow: Color = Ink.text.secondary, onInk: Bool = false) {
        self.tags = tags
        self.limit = limit
        self.weight = weight
        self.overflow = overflow
        self.onInk = onInk
    }

    public var body: some View {
        if !tags.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(tags.prefix(limit), id: \.self) { TagChip(tag: $0, onInk: onInk, weight: weight) }
                if tags.count > limit {
                    Text(verbatim: "+\(tags.count - limit)").typeRole(onSidebar ? .data : .monoSmall, weight: weight).monospacedDigit()
                        .foregroundStyle(overflow)
                }
            }
            .frame(maxWidth: Size.tagsMax, alignment: .trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tags: \(tags.joined(separator: ", "))")
        }
    }
}

#Preview("List column parts") {
    VStack(alignment: .leading, spacing: Space.s) {
        ListHeader(title: "App // 10") { IconCell(symbol: Symbol.ellipsis) } trailing: { PlusButton("New conversation") {} }
        SectionHead(title: "Pinned", count: 4)
    }
    .environment(\.onSidebar, true)
    .frame(width: 520).background(Ink.surface.sidebar)
}
