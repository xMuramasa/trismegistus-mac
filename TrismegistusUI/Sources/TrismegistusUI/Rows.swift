import SwiftUI

public enum LinkState: Sendable {
    case linked, reconnecting, offline
}

/// Dot, caps label and mono detail. Green only as a dot with an ink edge.
public struct StatusReadout: View {
    let state: LinkState
    let detail: String

    public init(_ state: LinkState, detail: String) {
        self.state = state
        self.detail = detail
    }

    private var label: String {
        switch state {
        case .linked: "Linked"
        case .reconnecting: "Reconnecting"
        case .offline: "Offline"
        }
    }

    private var dot: Color {
        switch state {
        case .linked: Ink.status.online
        case .reconnecting: Ink.selection
        case .offline: .clear
        }
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Circle().fill(dot).frame(width: Size.dot, height: Size.dot)
                .overlay(Circle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
            Text(label).typeRole(.label)
            Text(detail).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

public struct KeyHint: View {
    let key: String
    let action: String

    public init(_ key: String, _ action: String) {
        self.key = key
        self.action = action
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Text(key).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                .padding(.horizontal, Space.xs).padding(.vertical, 1)
                .edge(Ink.text.secondary)
            Text(action).typeRole(.caption).foregroundStyle(Ink.text.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hints along the bottom edge, with a rule on top.
public struct KeyHintStrip: View {
    let hints: [(key: String, action: String)]

    public init(_ hints: [(key: String, action: String)]) { self.hints = hints }

    public var body: some View {
        HStack(spacing: Space.l) {
            ForEach(hints, id: \.key) { KeyHint($0.key, $0.action) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Ink.line.rule).frame(height: 1) }
    }
}

/// Heading with the three-segment rule under it (magenta, yellow, green, then a hairline).
public struct TitleRule: View {
    let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(title).typeRole(.heading).foregroundStyle(Ink.text.primary)
            SegmentRule()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Endfield's title rule alone: magenta, yellow and green segments, then a hairline to the end unless `hairline` is
/// off. `TitleRule` draws it at `Size.titleRuleSmall`; `DetailHeader` at `Size.titleRule` (#32, #57).
public struct SegmentRule: View {
    let widths: (magenta: CGFloat, yellow: CGFloat, green: CGFloat)
    let height: CGFloat
    let hairline: Bool
    let stretches: Bool

    /// - Parameter stretches: magenta and yellow keep their widths and green fills the rest of the width (the window's
    ///   rule under a detail's header, as in the Penpot frame); otherwise all three keep their widths and a
    ///   hairline may follow.
    public init(
        _ widths: (magenta: CGFloat, yellow: CGFloat, green: CGFloat) = (
            Size.titleRuleSmall.magenta, Size.titleRuleSmall.yellow, Size.titleRuleSmall.green),
        height: CGFloat = Size.titleRuleSmall.height, hairline: Bool = true, stretches: Bool = false
    ) {
        self.widths = widths
        self.height = height
        self.hairline = hairline && !stretches
        self.stretches = stretches
    }

    public var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Ink.titleRule[0]).frame(width: widths.magenta)
            Rectangle().fill(Ink.titleRule[1]).frame(width: widths.yellow)
            if stretches {
                Rectangle().fill(Ink.titleRule[2]).frame(minWidth: widths.green, maxWidth: .infinity)
            } else {
                Rectangle().fill(Ink.titleRule[2]).frame(width: widths.green)
                if hairline { Rectangle().fill(Ink.line.rule) }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

public extension EnvironmentValues {
    /// True in the window's list column (`WindowColumns` sets it): every row is a card on the frosted ground (#69),
    /// conversations `SessionRowView`'s. Off (the popover): white rows, a yellow bar on the selected one, meta in `muted`.
    @Entry var onSidebar = false
}

/// The text colours of a list row: ink titles; meta `secondary` in the list column, `muted` in the popover.
public struct RowInk: Sendable {
    public let title: Color
    public let meta: Color
    public let error: Color
    public let link: Color

    public init(onSidebar: Bool, isSelected: Bool) {
        title = Ink.text.primary
        meta = onSidebar ? Ink.text.secondary : Ink.text.muted
        error = Ink.text.error
        link = Ink.text.link
    }
}

public extension View {
    /// The ground and selection mark of a list row (the popover's, the other sections' in the list column); see
    /// `onSidebar`. In the list column a card like a conversation's (#69), in its cell.
    func rowGround(isSelected: Bool) -> some View { modifier(RowGround(isSelected: isSelected)) }
}

private struct RowGround: ViewModifier {
    let isSelected: Bool
    @Environment(\.onSidebar) private var onSidebar
    @State private var hovered = false

    func body(content: Content) -> some View {
        if onSidebar {
            content
                .modifier(CardGround(isSelected: isSelected, isHovered: hovered))
                .onHover { hovered = $0 }
                .sidebarCardCell(isSelected: isSelected)
        } else {
            HStack(spacing: 0) {
                Rectangle().fill(isSelected ? Ink.selection : .clear).frame(width: Stroke.mark)
                content
            }
            .background(Ink.surface.raised)
        }
    }
}

/// A row of the other sections' lists (Agents, Jobs, Commands): title, then one meta line, with marks on the right; a
/// card in the list column (`rowGround`). Here since #69 so the snapshots draw it.
public struct SidebarRow<Marks: View>: View {
    let title: String
    let meta: String
    let isSelected: Bool
    var titleLines = 1
    @ViewBuilder var marks: (RowInk) -> Marks

    @Environment(\.onSidebar) private var onSidebar

    public init(title: String, meta: String, isSelected: Bool, titleLines: Int = 1, @ViewBuilder marks: @escaping (RowInk) -> Marks) {
        self.title = title
        self.meta = meta
        self.isSelected = isSelected
        self.titleLines = titleLines
        self.marks = marks
    }

    public var body: some View {
        let ink = RowInk(onSidebar: onSidebar, isSelected: isSelected)
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text(title).typeRole(onSidebar ? .quietTitle : .headline, weight: onSidebar && isSelected ? .semibold : nil)
                    .foregroundStyle(ink.title).lineLimit(titleLines)
                Text(meta).typeRole(.callout).monospacedDigit().foregroundStyle(ink.meta).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            marks(ink)
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: onSidebar ? Size.card : Size.row, alignment: .leading)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

public extension SidebarRow where Marks == EmptyView {
    init(title: String, meta: String, isSelected: Bool, titleLines: Int = 1) {
        self.init(title: title, meta: meta, isSelected: isSelected, titleLines: titleLines, marks: { _ in EmptyView() })
    }
}

/// A conversation row. In the window's list column a card (#69, design 13 #a3): 46 pt, `control` corners, white
/// stepping to translucent white with a contour hairline (white with a contour edge under the pointer; the selection in
/// `CardGround`); the muted 2-digit index, a 26 pt source avatar, the title (13 pt, 500; 600 with a state or selected)
/// and age, then the preview (the list's `preview` as the relay sends it) with the tags, the state tag and the pin or
/// lock. In the popover a white row with the yellow bar, the pin after the age and the tag on its top-right corner.
public struct SessionRowView: View {
    let name: String
    let source: SessionSource
    let activity: String
    let preview: String?
    let isSelected: Bool
    let isReadOnly: Bool
    let isPinned: Bool
    let runElapsed: String?
    let needsApproval: Bool
    /// FAILED or DONE, once the run alerts exist (#65); approval and a run win over it.
    let finished: StickerState?
    let tags: [String]
    /// The card's place in the conversation list, from 1 (`01`); decoration in the game's manner, not read out.
    let index: Int?

    public init(
        name: String, source: SessionSource, activity: String, preview: String? = nil, isSelected: Bool = false,
        isReadOnly: Bool = false, isPinned: Bool = false, runElapsed: String? = nil, needsApproval: Bool = false,
        finished: StickerState? = nil, tags: [String] = [], index: Int? = nil
    ) {
        self.name = name
        self.source = source
        self.activity = activity
        self.preview = preview
        self.isSelected = isSelected
        self.isReadOnly = isReadOnly
        self.isPinned = isPinned
        self.runElapsed = runElapsed
        self.needsApproval = needsApproval
        self.finished = finished
        self.tags = tags
        self.index = index
    }

    @Environment(\.onSidebar) private var onSidebar
    @Environment(\.rowHovered) private var isHovered

    /// Approval wins over the run it holds up.
    private var state: StickerState? { needsApproval ? .approval : runElapsed != nil ? .running : finished }

    /// What VoiceOver reads (the design's `spoken`).
    var spoken: String {
        ([name, state?.spoken, activity, isReadOnly ? "read-only" : nil, isPinned ? "pinned" : nil, tags.isEmpty ? nil : "tags \(tags.joined(separator: ", "))"] as [String?])
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public var body: some View {
        Group {
            if onSidebar { card } else { popoverRow }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var card: some View {
        // Semibold is for a state and the selection: a quiet row stays at 500.
        let strong = state != nil || isSelected
        return HStack(spacing: Space.s) {
            if let index {
                Text(String(format: "%02d", index)).typeRole(.micro).monospacedDigit().foregroundStyle(Ink.text.muted)
                    .frame(width: Size.cardIndex, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            SourceAvatar(source, size: Size.avatar.card)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.s) {
                    Text(name).typeRole(.quietTitle, weight: strong ? .semibold : nil).foregroundStyle(Ink.text.primary).lineLimit(1)
                    Spacer(minLength: Space.s)
                    Text(activity).typeRole(.caption).monospacedDigit().foregroundStyle(Ink.text.secondary).lineLimit(1).fixedSize()
                }
                .frame(height: Size.sticker.height)
                HStack(spacing: Space.s) {
                    Text(preview ?? "").typeRole(.callout).foregroundStyle(Ink.text.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    TagChips(tags: tags)
                    if let state { Sticker(state, time: state == .running ? runElapsed : nil) }
                    if isPinned { Image(systemName: Symbol.pinOutline).font(.system(size: Icon.sticker)).foregroundStyle(Ink.text.secondary) }
                    if isReadOnly { Image(systemName: Symbol.lockOutline).font(.system(size: Icon.sticker)).foregroundStyle(Ink.text.secondary) }
                }
                .frame(height: Space.xl)
            }
        }
        .padding(.leading, index == nil ? Space.m : Space.xs).padding(.trailing, Space.m)
        .frame(height: Size.card)
        .modifier(CardGround(isSelected: isSelected, isHovered: isHovered))
    }

    private var popoverRow: some View {
        let ink = RowInk(onSidebar: false, isSelected: isSelected)
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.s) {
                Text(name).typeRole(.headline).foregroundStyle(ink.title).lineLimit(1)
                Spacer(minLength: 0)
                if let state {
                    // In the line, so a long title stops short of it; out to the row's corner, inside the row.
                    Sticker(state, time: state == .running ? runElapsed : nil)
                        .padding(.trailing, -Space.m)
                        .offset(y: -Space.xs)
                }
            }
            .frame(height: Space.l)
            HStack(spacing: Space.xs) {
                SourceIcon(source).padding(.trailing, Space.xs)
                Text(activity).typeRole(.monoSmall).monospacedDigit().lineLimit(1)
                if isReadOnly { Image(systemName: Symbol.lock).font(.system(size: Icon.s)) }
                if isPinned { Image(systemName: Symbol.pin).font(.system(size: Icon.s)) }
                Spacer(minLength: Space.s)
                TagChips(tags: tags)
                    // The `…` takes this place on the selected row and the one under the pointer.
                    .padding(.trailing, isSelected || isHovered ? Size.menuButton : 0)
            }
            .foregroundStyle(ink.meta)
            .frame(height: Space.l)
        }
        .padding(.horizontal, Space.m)
        .frame(height: Size.row)
        .rowGround(isSelected: isSelected)
    }
}

/// A source as a rounded-square avatar (`control` corners, #69): the app's `T` on dark-panel, Telegram on blue, the
/// terminal on dark-panel, cron and the rest an ink glyph on sunken with a rule edge.
public struct SourceAvatar: View {
    let source: SessionSource
    let size: CGFloat

    public init(_ source: SessionSource, size: CGFloat = Size.avatar.card) {
        self.source = source
        self.size = size
    }

    public var body: some View {
        let (fill, glyph): (Color, Color) = switch source {
        case .trismegistus: (Ink.avatar.app, Ink.text.onPanel)
        case .telegram: (Ink.avatar.telegram, Ink.text.onPanel)
        case .cli: (Ink.avatar.terminal, Ink.text.onPanel)
        case .cron: (Ink.avatar.other, Ink.text.primary)
        }
        Group {
            switch source {
            case .trismegistus: Text(verbatim: "T").typeRole(.headline)
            case .telegram: Image(systemName: Symbol.telegram).font(.system(size: Icon.avatar))
            case .cli: Image(systemName: Symbol.cli).font(.system(size: Icon.avatar))
            case .cron: Image(systemName: Symbol.clock).font(.system(size: Icon.avatar))
            }
        }
        .foregroundStyle(glyph)
        .frame(width: size, height: size)
        .rounded(Radius.control, fill: fill, edge: source == .cron ? Ink.line.rule : .clear)
        .accessibilityHidden(true)
    }
}

/// A card's ground in the list column (#69). White stepping down to translucent white with a contour hairline; white
/// with a full contour edge under the pointer. Selected: white, a 1.5 pt yellow frame with a faint glow, grey bracket
/// corners 6 pt outside and the hatch on its top edge.
struct CardGround: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool

    private static let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)

    func body(content: Content) -> some View {
        let lit = isSelected || isHovered
        content
            .background {
                // The glow on the fill alone: on a stack it is one per child.
                Self.shape
                    .fill(lit ? AnyShapeStyle(Ink.surface.cardHover)
                              : AnyShapeStyle(LinearGradient(colors: [Ink.surface.paperCard, Ink.surface.cardLow], startPoint: .top, endPoint: .bottom)))
                    .shadow(isSelected ? Shadow.selectionGlow : Shadow.none)
            }
            .overlay {
                Self.shape.strokeBorder(isSelected ? Ink.selection : isHovered ? Ink.line.contour : Ink.line.card,
                                        lineWidth: isSelected ? Stroke.selection : Stroke.hairline)
            }
            .overlay { if isSelected { selection } }
    }

    private var selection: some View {
        ZStack(alignment: .topTrailing) {
            Brackets().stroke(Ink.text.secondary, lineWidth: Stroke.hairline).padding(-Size.bracket)
            Hatch().stroke(Ink.line.contour, lineWidth: Stroke.hairline)
                .frame(width: Size.hatch.width, height: Size.hatch.height).clipped()
                .padding(.top, Space.xxs).padding(.trailing, Size.hatch.inset)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Four corner brackets, `Size.bracket` long, at the rect's corners: the selected card's grey marks.
struct Brackets: Shape {
    func path(in rect: CGRect) -> Path {
        let a = Size.bracket
        let r = rect.insetBy(dx: Stroke.hairlineFine, dy: Stroke.hairlineFine)
        return Path { p in
            for (x, y, dx, dy) in [(r.minX, r.minY, a, a), (r.maxX, r.minY, -a, a), (r.maxX, r.maxY, -a, -a), (r.minX, r.maxY, a, -a)] {
                p.move(to: CGPoint(x: x + dx, y: y))
                p.addLine(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x, y: y + dy))
            }
        }
    }
}

/// A tool call: collapsed or expanded (output on sunken); a failed one gets a red edge and `EXIT n`.
public struct ToolRowView: View {
    let tool: String
    let summary: String
    let duration: String
    let output: String?
    let exitCode: Int?
    @Binding var isExpanded: Bool

    public init(
        tool: String, summary: String, duration: String, output: String? = nil, exitCode: Int? = nil,
        isExpanded: Binding<Bool>
    ) {
        self.tool = tool
        self.summary = summary
        self.duration = duration
        self.output = output
        self.exitCode = exitCode
        self._isExpanded = isExpanded
    }

    private var failed: Bool { (exitCode ?? 0) != 0 }

    public var body: some View {
        VStack(spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: Symbol.fold(isOpen: isExpanded))
                        .font(.system(size: Icon.xxs, weight: .bold)).frame(width: Icon.xxs)
                    Text(tool).typeRole(.mono, weight: .semibold)
                    Text(summary).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).lineLimit(1)
                    Spacer(minLength: Space.s)
                    if failed, let exitCode {
                        Text(verbatim: "Exit \(exitCode)").typeRole(.label).foregroundStyle(Ink.text.error)
                    }
                    Text(duration).typeRole(.monoSmall).foregroundStyle(Ink.text.muted)
                }
                .padding(.horizontal, Space.m)
                .frame(height: Size.rowTool)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.text.primary)
            .accessibilityHint(isExpanded ? "Collapse output" : "Expand output")
            if isExpanded, let output {
                Text(output)
                    .typeRole(.monoSmall).foregroundStyle(Ink.text.primary)
                    .textSelection(.enabled)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.surface.sunken)
                    .padding(Space.s)
            }
        }
        .background(Ink.surface.raised)
        .edge(failed ? Ink.text.error : Ink.line.rule)
    }
}

public struct SubagentRowView: View {
    let name: String
    let toolCount: Int
    let duration: String

    public init(name: String, toolCount: Int, duration: String) {
        self.name = name
        self.toolCount = toolCount
        self.duration = duration
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Text("Subagent").typeRole(.label).foregroundStyle(Ink.text.link)
            Text(name).typeRole(.mono)
            Text(verbatim: "\(toolCount) tools").typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
            Spacer(minLength: Space.s)
            Text(duration).typeRole(.monoSmall).foregroundStyle(Ink.text.muted)
        }
        .padding(.horizontal, Space.m)
        .frame(height: Size.rowTool)
        .background(Ink.surface.raised)
        .overlay(alignment: .leading) { Rectangle().fill(Ink.text.link).frame(width: Stroke.mark) }
        .edge(Ink.line.rule)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Status and hints") {
    VStack(alignment: .leading, spacing: 12) {
        TitleRule("Trismegistus-mac // Controls")
        StatusReadout(.linked, detail: "hermes.lab · 18 ms")
        StatusReadout(.reconnecting, detail: "retry in 4 s")
        StatusReadout(.offline, detail: "relay unreachable")
        KeyHintStrip([("⌘↩", "send"), ("⌘.", "stop")])
    }
    .padding().frame(width: 360).background(Ink.surface.window)
}

#Preview("Session rows") {
    VStack(spacing: 1) {
        SessionRowView(name: "Homelab backup check", source: .telegram, activity: "2 h")
        SessionRowView(name: "trismegistus-mac UI draft", source: .trismegistus, activity: "now", isSelected: true)
        SessionRowView(name: "Endfield gallery render", source: .trismegistus, activity: "1 min", runElapsed: "00:42")
        SessionRowView(name: "Clean build cache", source: .trismegistus, activity: "3 min", needsApproval: true)
        SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", isReadOnly: true)
    }
    .background(Ink.line.rule).frame(width: 320).padding().background(Ink.surface.window)
}

#Preview("Tool and subagent rows") {
    VStack(alignment: .leading, spacing: 8) {
        ToolRowView(tool: "terminal", summary: "ls ~/Projects", duration: "0.3 s", isExpanded: .constant(false))
        ToolRowView(
            tool: "terminal", summary: "ls ~/Projects", duration: "0.3 s", output: "endfield-dotfiles\nhomelab",
            exitCode: 0, isExpanded: .constant(true))
        ToolRowView(
            tool: "terminal", summary: "pytest -q tests/", duration: "4.8 s", exitCode: 1, isExpanded: .constant(false))
        SubagentRowView(name: "research", toolCount: 3, duration: "8.4 s")
    }
    .frame(width: 320).padding().background(Ink.surface.window)
}
