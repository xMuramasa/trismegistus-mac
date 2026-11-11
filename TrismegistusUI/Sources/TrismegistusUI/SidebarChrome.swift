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

    /// A row of a list column, edge to edge, on the column's own ground. Every row sets `listRowBackground`: it replaces
    /// the row view's ground, where macOS draws its selection highlight (a thin blue line showed past the rows
    /// otherwise).
    func sidebarRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear)
    }

    /// A card's cell: 2 pt above and under the 46 pt card, a 50 pt pitch (#69). A `List` clips each row, so the selected
    /// card's cell is 8 pt taller on each side for its bracket corners.
    func sidebarCardCell(isSelected: Bool = false) -> some View {
        padding(.vertical, isSelected ? Space.s : Space.xxs).background { SelectionMargins(isSelected: isSelected) }
    }
}

/// macOS keeps an 8 pt inset on list rows and draws its selection highlight (blue in a key window) across the full
/// row, so it showed in those margins beside the selected row. Opaque strips in the column's ground over the margins
/// hide it whatever the window state; other rows leave the translucent ground alone.
struct SelectionMargins: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            HStack(spacing: 0) {
                Ink.surface.sidebarSolid.frame(width: Space.s)
                Spacer(minLength: 0)
                Ink.surface.sidebarSolid.frame(width: Space.s)
            }
            .padding(.horizontal, -Space.s)
        }
    }
}

/// The list header's title (#69): `// APP` in tracked caps, then the count as the one large numeral; a title without a
/// count (`All conversations`) is the label alone. `APP // 10` is the call sites' form: the part after `//` is the
/// count, and a word after the number (`14 open`) is a second label.
public struct SidebarTitle: View {
    let title: String

    public init(_ title: String) { self.title = title }

    /// `GitHub // 14 open` → (`GitHub`, `14`, `open`).
    static func parts(_ title: String) -> (label: String, count: String?, suffix: String?) {
        guard let slashes = title.range(of: "//") else { return (title, nil, nil) }
        let label = title[..<slashes.lowerBound].trimmingCharacters(in: .whitespaces)
        let rest = title[slashes.upperBound...].trimmingCharacters(in: .whitespaces)
        let count = rest.prefix { $0.isNumber }
        let suffix = rest.dropFirst(count.count).trimmingCharacters(in: .whitespaces)
        return (label, count.isEmpty ? rest : String(count), suffix.isEmpty || count.isEmpty ? nil : suffix)
    }

    public var body: some View {
        let parts = Self.parts(title)
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(verbatim: "// \(parts.label)").typeRole(.columnLabel).foregroundStyle(Ink.text.secondary)
            if let count = parts.count {
                Text(verbatim: count).typeRole(.count).monospacedDigit().foregroundStyle(Ink.text.onSidebar)
            }
            if let suffix = parts.suffix { Text(verbatim: suffix).typeRole(.columnLabel).foregroundStyle(Ink.text.secondary) }
        }
        .lineLimit(1).minimumScaleFactor(0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title.replacingOccurrences(of: "//", with: ""))
        .accessibilityAddTraits(.isHeader)
    }
}

/// The list column's header (#69): `leading` (`…`; first, while the panel is hidden, room for the window's buttons and
/// the sidebar toggle), the title centred, `trailing` (the yellow `+`, a section's own actions), and a short diagonal
/// hatch left of the actions. Both sides take the same width, so the title stays in the middle.
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
        .overlay(alignment: .topTrailing) {
            Hatch().stroke(Ink.line.contour, lineWidth: Stroke.hairline)
                .frame(width: Size.hatch.headWidth, height: Size.hatch.headHeight)
                .clipped()
                .padding(.top, Space.xxl).padding(.trailing, Size.hatch.inset)
                .accessibilityHidden(true)
        }
    }
}

/// Short diagonal lines (`/`) across the rect, `Size.hatch.pitch` apart: the hatch in the list header and on the selected
/// card's top edge. Clip it to its frame.
struct Hatch: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            var x = rect.minX - rect.height
            while x < rect.maxX {
                p.move(to: CGPoint(x: x, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += Size.hatch.pitch
            }
        }
    }
}

/// The list header's `+`: yellow with a yellow edge and `control` corners, the region's primary action (a yellow glow
/// under the pointer). While the open conversation runs Steer is the yellow action, and `+` steps down to a thin-edged
/// white button.
public struct PlusButton: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
    @State private var hovered = false

    public init(_ title: String, isPrimary: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isPrimary = isPrimary
        self.action = action
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        Button(action: action) {
            Image(systemName: Symbol.plus).font(.system(size: Icon.section)).foregroundStyle(Ink.text.primary)
                .frame(width: Size.control, height: Size.control)
                .background {
                    shape.fill(isPrimary ? Ink.selection : hovered ? Ink.surface.raised : Ink.surface.control)
                        .shadow(isPrimary && hovered ? Shadow.plusGlow : Shadow.none)
                }
                .overlay(shape.strokeBorder(isPrimary ? Ink.selection : Ink.line.rule, lineWidth: Stroke.hairline))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

/// `// TITLE ———— 04`: a tracked label, a hairline running to the trailing text. In the list column (`onPanel` off)
/// secondary with a contour line; on the section panel contour with a faint white line and the trailing text muted.
public struct LabelLine: View {
    let title: String
    let trailing: String?
    let onPanel: Bool

    public init(title: String, trailing: String? = nil, onPanel: Bool = false) {
        self.title = title
        self.trailing = trailing
        self.onPanel = onPanel
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Text(verbatim: "// \(title)").typeRole(.trackedLabel).lineLimit(1).fixedSize()
                .foregroundStyle(onPanel ? Ink.text.onPanelQuiet : Ink.text.secondary)
            Rectangle().fill(onPanel ? Ink.line.panelGuide : Ink.line.contour).frame(height: Stroke.hairline)
            if let trailing {
                Text(verbatim: trailing).typeRole(.micro, weight: .semibold).monospacedDigit().fixedSize()
                    .foregroundStyle(onPanel ? Ink.text.muted : Ink.text.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(trailing.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A section head in the list column (PINNED, CONVERSATIONS, a board status): a 24 pt `// PINNED ——— 04` label line,
/// 16 pt in, with a fold chevron after the count when the group folds.
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
            LabelLine(title: title, trailing: count.map { String(format: "%02d", $0) })
            if let folded {
                Image(systemName: Symbol.chevronDown).font(.system(size: Icon.l)).foregroundStyle(Ink.text.secondary)
                    .rotationEffect(.degrees(folded ? -90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Space.l)
        .frame(height: Size.labelLine)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A tag. In the list column a sunken chip with `tag` corners in Inter (#69); elsewhere mono on sunken. `isOn` (a
/// filter's choice, an editor's toggle) is white with a secondary edge.
public struct TagChip: View {
    let tag: String
    let isOn: Bool
    let weight: Font.Weight?

    @Environment(\.onSidebar) private var onSidebar

    public init(tag: String, isOn: Bool = false, weight: Font.Weight? = nil) {
        self.tag = tag
        self.isOn = isOn
        self.weight = weight
    }

    public var body: some View {
        Text(tag).typeRole(onSidebar ? .micro : .monoSmall, weight: weight).monospacedDigit().lineLimit(1)
            .foregroundStyle(isOn ? Ink.text.primary : Ink.text.secondary)
            .padding(.horizontal, onSidebar ? Space.xs : Space.s).padding(.vertical, onSidebar ? 0 : 1)
            .frame(minHeight: onSidebar ? Size.chip : nil)
            .rounded(onSidebar ? Radius.tag : Radius.none, fill: isOn ? Ink.surface.raised : Ink.surface.sunken,
                     edge: isOn ? Ink.text.secondary : onSidebar ? .clear : Ink.line.rule)
    }
}

/// Up to `limit` chips, then `+N`.
public struct TagChips: View {
    let tags: [String]
    let limit: Int
    let weight: Font.Weight?
    let overflow: Color

    @Environment(\.onSidebar) private var onSidebar

    public init(tags: [String], limit: Int = 2, weight: Font.Weight? = nil, overflow: Color = Ink.text.secondary) {
        self.tags = tags
        self.limit = limit
        self.weight = weight
        self.overflow = overflow
    }

    public var body: some View {
        if !tags.isEmpty {
            HStack(spacing: Space.xs) {
                ForEach(tags.prefix(limit), id: \.self) { TagChip(tag: $0, weight: weight) }
                if tags.count > limit {
                    Text(verbatim: "+\(tags.count - limit)").typeRole(onSidebar ? .micro : .monoSmall, weight: .semibold).monospacedDigit()
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
