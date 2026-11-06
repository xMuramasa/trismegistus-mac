import SwiftUI

public extension EnvironmentValues {
    /// The sidebar is narrower than its default width (`SidebarSplit` sets it): stickers drop their word, a row keeps one
    /// tag, the kind tabs and the footer tighten.
    @Entry var sidebarNarrow = false
    /// The pointer is over this conversation row. `conversationChrome` sets it for the card under the row's overlays.
    @Entry var rowHovered = false
}

public extension View {
    /// A sidebar `List`: keyboard selection as before, no ground of its own.
    func sidebarList() -> some View { listStyle(.plain).scrollContentBackground(.hidden) }

    /// A row of a sidebar list, edge to edge. Every row sets `listRowBackground`: it replaces the row view's ground,
    /// where macOS draws its selection highlight (a thin blue line showed past the rows otherwise).
    func sidebarRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Ink.surface.sidebar)
    }

    /// A conversation card's cell, 60 pt tall: 8 pt between cards, with room for the selected card's frame. The backing
    /// runs under the list's 8 pt side margins, where macOS still draws its selection highlight (`RowGround`).
    func sidebarCardCell() -> some View {
        padding(.vertical, Space.xs).background { Ink.surface.sidebar.padding(.horizontal, -Space.s) }
    }
}

/// `APP // 10`: Black, white, with yellow slashes. A title that doesn't fit shrinks rather than truncating its count.
public struct SidebarTitle: View {
    let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        var text = AttributedString(title.uppercased())
        if let slashes = text.range(of: "//") { text[slashes].foregroundColor = Ink.selection }
        return Text(text).typeRole(.display).monospacedDigit()
            .foregroundStyle(Ink.text.onSidebar)
            .lineLimit(1).minimumScaleFactor(0.5)
    }
}

/// An ink slab across the sidebar: a yellow square and label, then contour lines fading in towards the right so the
/// label stays clear. The lines are one column wide whatever the sidebar's width, and each title has its own wobble.
public struct SectionHead: View {
    let title: String

    public init(title: String) { self.title = title }

    public var body: some View {
        HStack(spacing: Space.s) {
            Rectangle().fill(Ink.selection).frame(width: Size.marker, height: Size.marker)
            Text(title).typeRole(.sectionHead).foregroundStyle(Ink.selection).lineLimit(1).fixedSize()
            EndfieldContours(color: Ink.line.contour, lineWidth: Stroke.hairlineFine, spread: Size.sidebar.max, seed: Double(title.count))
                .frame(width: Size.sidebar.max)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .trailing)
                .clipped()
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.7)],
                                     startPoint: .leading, endPoint: .trailing))
        }
        .padding(.leading, Space.s)
        .frame(height: Size.sectionHead)
        .background(Ink.surface.inverse)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// After the last row: the list's count, huge and faint, beside crosshairs, a dot grid and a hatch anchored to the right.
/// Decoration: takes no clicks and is not in the accessibility tree.
public struct SidebarFlare: View {
    let count: Int

    public init(count: Int) { self.count = count }

    public var body: some View {
        ZStack(alignment: .leading) {
            Canvas { context, size in
                context.translateBy(x: size.width - Size.flare.art, y: 0)
                context.stroke(Self.lines, with: .color(Ink.text.onDark), lineWidth: Stroke.hairline)
                context.fill(Self.dots, with: .color(Ink.text.onDark))
            }
            .opacity(Opacity.flareArt)
            Text(verbatim: "\(count)").typeRole(.flare)
                .foregroundStyle(Ink.text.onDark.opacity(Opacity.flareCount))
                .lineLimit(1).fixedSize()
        }
        .frame(height: Size.flare.height)
        .clipped()
        .padding(.horizontal, Space.s).padding(.top, Space.l)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Two crosshairs, the axes and the hatch, in the 272×96 box the design draws them in.
    private static let lines: Path = {
        var path = Path()
        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
            path.move(to: CGPoint(x: x0, y: y0))
            path.addLine(to: CGPoint(x: x1, y: y1))
        }
        for (x, y): (CGFloat, CGFloat) in [(136, 24), (248, 40)] {
            line(x - 8, y, x + 8, y)
            line(x, y - 8, x, y + 8)
        }
        line(96, 8, 96, 88)
        line(96, 48, 272, 48)
        for i in 0..<8 { line(212 + CGFloat(i) * 4, 72, 212 + CGFloat(i) * 4, 88) }
        return path
    }()

    private static let dots: Path = {
        var path = Path()
        for column in 0..<6 {
            for row in 0..<3 {
                path.addRect(CGRect(x: 112 + CGFloat(column) * 12, y: 60 + CGFloat(row) * 12, width: 2, height: 2))
            }
        }
        return path
    }()
}

/// A tag. On the window sidebar a white chip with an ink edge, in Inter; elsewhere mono on sunken. `isOn` (a filter's
/// choice, an editor's toggle) is ink with yellow text.
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
        Text(tag).typeRole(onSidebar ? .data : .monoSmall, weight: weight).monospacedDigit().lineLimit(1)
            .foregroundStyle(isOn ? Ink.selection : onSidebar ? Ink.text.primary : Ink.text.secondary)
            .padding(.horizontal, onSidebar ? Space.xs : Space.s).padding(.vertical, onSidebar ? 0 : 1)
            .frame(minHeight: onSidebar ? Size.chip : nil)
            .background(isOn ? Ink.surface.inverse : onSidebar ? Ink.surface.raised : Ink.surface.sunken)
            .edge(isOn || onSidebar ? Ink.line.strong : Ink.line.rule)
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

#Preview("Sidebar parts") {
    VStack(alignment: .leading, spacing: Space.s) {
        SidebarTitle("App // 10")
        SectionHead(title: "Pinned")
        SidebarFlare(count: 10)
    }
    .environment(\.onSidebar, true)
    .frame(width: 304).background(Ink.surface.sidebar)
}
