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
    /// True in the window's list column (`WindowColumns` sets it, #68): rows sit on paper with ink text, the selected
    /// one white with an ink edge; conversations are `SessionRowView`'s cards. Off (the popover): white rows, a yellow
    /// bar on the selected one, meta in `muted`.
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
    /// `onSidebar`. In the list column the fill is opaque so the list's own selection highlight never shows through.
    func rowGround(isSelected: Bool) -> some View { modifier(RowGround(isSelected: isSelected)) }
}

private struct RowGround: ViewModifier {
    let isSelected: Bool
    @Environment(\.onSidebar) private var onSidebar

    func body(content: Content) -> some View {
        if onSidebar {
            content
                .padding(.leading, Stroke.mark)
                // Yellow wouldn't read on paper: the selected row is a white `l` card with an ink edge.
                .background {
                    RoundedRectangle(cornerRadius: Radius.l, style: .continuous).fill(isSelected ? Ink.surface.raised : Ink.surface.sidebar)
                }
                .edge(isSelected ? Ink.line.strong : .clear, radius: Radius.l)
                // macOS keeps an 8 pt inset on list rows and draws its selection highlight (blue in a key window)
                // across the full row, so it showed in those margins beside the selected row. A backing in the
                // column's ground under the margins hides it whatever the window state.
                .background { Ink.surface.sidebar.padding(.horizontal, -Space.s) }
        } else {
            HStack(spacing: 0) {
                Rectangle().fill(isSelected ? Ink.selection : .clear).frame(width: Stroke.mark)
                content
            }
            .background(Ink.surface.raised)
        }
    }
}

/// A conversation row. In the window's list column a card (#65, rounded in #68): 56 pt, `l` corners, white with a 4 pt
/// muted head band and a dark-panel foot bar clipped by the corners, sunken under the pointer, ink when selected; a
/// 36 pt source avatar, the title and age, then the preview (the list's `preview` as the relay sends it) with the tags,
/// the sticker 12 pt in from the right edge and the pin or lock. A quiet row is regular weight. In the popover a white
/// row with the yellow bar, the pin after the age and the sticker on its top-right corner.
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

    public init(
        name: String, source: SessionSource, activity: String, preview: String? = nil, isSelected: Bool = false,
        isReadOnly: Bool = false, isPinned: Bool = false, runElapsed: String? = nil, needsApproval: Bool = false,
        finished: StickerState? = nil, tags: [String] = []
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
        // Bold is for titles and active things: a row with nothing to say drops to regular.
        let quiet = state == nil && !isSelected
        let meta = isSelected ? Ink.text.onDark : Ink.text.secondary
        return HStack(spacing: Space.m) {
            SourceAvatar(source, size: Size.avatar.card, onInk: isSelected)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Space.s) {
                    Text(name).typeRole(.cardTitle, weight: quiet ? .regular : nil)
                        .foregroundStyle(isSelected ? Ink.selection : Ink.text.primary).lineLimit(1)
                    Spacer(minLength: Space.s)
                    Text(activity).typeRole(.callout).monospacedDigit().foregroundStyle(meta).lineLimit(1).fixedSize()
                }
                .frame(height: Space.xl)
                HStack(spacing: Space.s) {
                    Text(preview ?? "").typeRole(.body).foregroundStyle(meta).lineLimit(1)
                    Spacer(minLength: 0)
                    TagChips(tags: tags, weight: quiet ? .regular : nil, overflow: meta, onInk: isSelected)
                    if let state {
                        Sticker(state, time: state == .running ? runElapsed : nil, edge: isSelected ? Ink.text.onDark : Ink.line.strong)
                    }
                    if isPinned { Image(systemName: Symbol.pinOutline).font(.system(size: Icon.l)).foregroundStyle(meta) }
                    if isReadOnly { Image(systemName: Symbol.lockOutline).font(.system(size: Icon.l)).foregroundStyle(meta) }
                }
                .frame(height: Space.xxl)
            }
        }
        .padding(.horizontal, Space.m)
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

/// A source as a rounded-square avatar (`s` corners, #68): the app's `T` on ink, Telegram on blue, the terminal on
/// dark-panel, cron and the rest an ink glyph on sunken with a rule edge. `onInk` (the selected card): the app's
/// avatar turns white with an ink `T`.
public struct SourceAvatar: View {
    let source: SessionSource
    let size: CGFloat
    let onInk: Bool

    public init(_ source: SessionSource, size: CGFloat = Size.avatar.card, onInk: Bool = false) {
        self.source = source
        self.size = size
        self.onInk = onInk
    }

    public var body: some View {
        let (fill, glyph): (Color, Color) = switch source {
        case .trismegistus: onInk ? (Ink.surface.raised, Ink.text.primary) : (Ink.avatar.app, Ink.text.onPanel)
        case .telegram: (Ink.avatar.telegram, Ink.text.onPanel)
        case .cli: (Ink.avatar.terminal, Ink.text.onPanel)
        case .cron: (Ink.avatar.other, Ink.text.primary)
        }
        Group {
            switch source {
            case .trismegistus: Text(verbatim: "T").typeRole(size < Size.avatar.card ? .cardTitle : .avatarMark)
            case .telegram: Image(systemName: Symbol.telegram).font(.system(size: Icon.panel))
            case .cli: Image(systemName: Symbol.cli).font(.system(size: Icon.panel))
            case .cron: Image(systemName: Symbol.clock).font(.system(size: Icon.panel))
            }
        }
        .foregroundStyle(glyph)
        .frame(width: size, height: size)
        .rounded(Radius.s, fill: fill, edge: source == .cron ? Ink.line.rule : .clear)
        .accessibilityHidden(true)
    }
}

/// A card's ground. Selected: ink with the soft shadow, a 1 pt yellow frame 4 pt outside it (`xl`, the card's `l` + 4)
/// with yellow arcs over its corners and a soft glow. Otherwise white (sunken under the pointer) with the head band and
/// foot bar, flat 4 pt strips clipped by the card's corners.
private struct CardGround: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool

    private static let shape = RoundedRectangle(cornerRadius: Radius.l, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if isSelected { frame.shadow(Shadow.selectionGlow) }
                    // On the fill alone: a shadow on a stack is one per child, so the head band would cast one.
                    Self.shape.fill(isSelected ? Ink.surface.inverse : isHovered ? Ink.surface.cardHover : Ink.surface.paperCard)
                        .shadow(isSelected ? Shadow.block : Shadow.none)
                    if !isSelected { bands.clipShape(Self.shape) }
                }
            }
            .overlay { if isSelected { frame } }
    }

    private var bands: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Ink.surface.cardHead).frame(height: Stroke.rule)
            Spacer(minLength: 0)
            Rectangle().fill(Ink.surface.cardFoot).frame(height: Stroke.rule)
        }
    }

    private var frame: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Ink.selection, lineWidth: Stroke.hairline)
                .padding(-Space.xs)
            CornerArcs().fill(Ink.selection).padding(-(Space.xs + Stroke.hairline))
        }
        .allowsHitTesting(false)
    }
}

/// Four quarter arcs, `Stroke.mark` thick and `xl` in radius, over a rounded frame's corners: B2's corner nodes on a
/// rounded selection.
struct CornerArcs: Shape {
    func path(in rect: CGRect) -> Path {
        let r = Radius.xl
        let mid = r - Stroke.mark / 2
        var path = Path()
        let corners: [(CGPoint, Double)] = [
            (CGPoint(x: rect.minX + r, y: rect.minY + r), 180), (CGPoint(x: rect.maxX - r, y: rect.minY + r), 270),
            (CGPoint(x: rect.maxX - r, y: rect.maxY - r), 0), (CGPoint(x: rect.minX + r, y: rect.maxY - r), 90),
        ]
        for (center, start) in corners {
            path.addPath(Path { $0.addArc(center: center, radius: mid, startAngle: .degrees(start), endAngle: .degrees(start + 90), clockwise: false) })
        }
        return path.strokedPath(StrokeStyle(lineWidth: Stroke.mark))
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
