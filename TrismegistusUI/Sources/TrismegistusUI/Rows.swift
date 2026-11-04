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
/// off. `TitleRule` draws it at `Size.titleRuleSmall`; the window's conversation header at `Size.titleRule` (#32).
public struct SegmentRule: View {
    let widths: (magenta: CGFloat, yellow: CGFloat, green: CGFloat)
    let height: CGFloat
    let hairline: Bool
    let stretches: Bool

    /// - Parameter stretches: magenta and yellow keep their widths and green fills the rest of the width (the window's
    ///   rule under the conversation header, as in the Penpot frame); otherwise all three keep their widths and a
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
    /// True in the window's sidebar (`SidebarSplit` sets it): rows sit on its `secondary` grey ground (#41) with light
    /// text, the selected one a white card with a 1 pt yellow border and ink text. Off (the popover): white rows, a
    /// yellow bar on the selected one, meta in `muted`.
    @Entry var onSidebar = false
}

/// The text colours of a list row: ink on the white rows (the popover, the sidebar's selected card), light on the
/// window sidebar's grey, where nothing is dimmer than `on-sidebar-secondary` (red and blue are too dark there).
public struct RowInk: Sendable {
    public let title: Color
    public let meta: Color
    public let error: Color
    public let link: Color

    public init(onSidebar: Bool, isSelected: Bool) {
        let onGrey = onSidebar && !isSelected
        title = onGrey ? Ink.text.onSidebar : Ink.text.primary
        meta = onGrey ? Ink.text.onSidebarSecondary : onSidebar ? Ink.text.secondary : Ink.text.muted
        error = onGrey ? Ink.text.onSidebar : Ink.text.error
        link = onGrey ? Ink.text.onSidebar : Ink.text.link
    }
}

public extension View {
    /// The ground and selection mark of a list row (`SessionRowView`, the window sidebar's rows); see `onSidebar`.
    /// On the sidebar the fill is opaque so the list's own selection highlight never shows through.
    func rowGround(isSelected: Bool) -> some View { modifier(RowGround(isSelected: isSelected)) }
}

private struct RowGround: ViewModifier {
    let isSelected: Bool
    @Environment(\.onSidebar) private var onSidebar

    func body(content: Content) -> some View {
        if onSidebar {
            content
                .padding(.leading, Stroke.mark)
                .background(isSelected ? Ink.surface.raised : Ink.surface.sidebar)
                .overlay { if isSelected { Rectangle().strokeBorder(Ink.selection, lineWidth: Stroke.hairline) } }
                // macOS keeps an 8 pt inset on list rows and draws its selection highlight (blue in a key window)
                // across the full row, so it showed in those margins beside the selected row. A backing in the
                // sidebar's ground under the margins hides it whatever the window state.
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

/// A conversation row: 52 high, marker, name, source + activity, RUN / APPROVAL / lock marks.
public struct SessionRowView: View {
    let name: String
    let source: SessionSource
    let activity: String
    let isSelected: Bool
    let isReadOnly: Bool
    let runElapsed: String?
    let needsApproval: Bool

    public init(
        name: String, source: SessionSource, activity: String, isSelected: Bool = false, isReadOnly: Bool = false,
        runElapsed: String? = nil, needsApproval: Bool = false
    ) {
        self.name = name
        self.source = source
        self.activity = activity
        self.isSelected = isSelected
        self.isReadOnly = isReadOnly
        self.runElapsed = runElapsed
        self.needsApproval = needsApproval
    }

    @Environment(\.onSidebar) private var onSidebar

    public var body: some View {
        let ink = RowInk(onSidebar: onSidebar, isSelected: isSelected)
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(name).typeRole(.headline).foregroundStyle(ink.title).lineLimit(1)
                HStack(spacing: Space.s) {
                    SourceIcon(source)
                    if isReadOnly { Image(systemName: Symbol.lock).font(.system(size: Icon.s)) }
                    Text(isReadOnly ? "\(activity) · read-only" : activity).typeRole(.monoSmall)
                }
                .foregroundStyle(ink.meta)
            }
            Spacer(minLength: Space.s)
            if needsApproval {
                Text("Approval").typeRole(.label).foregroundStyle(Ink.text.primary)
                    .padding(.horizontal, Space.s).padding(.vertical, Space.xxs).background(Ink.marker)
            } else if let runElapsed {
                HStack(spacing: Space.s) {
                    Text("Run").typeRole(.label).foregroundStyle(ink.link)
                    Text(runElapsed).typeRole(.monoSmall).foregroundStyle(ink.title)
                }
            } else if isSelected {
                Image(systemName: Symbol.chevronRight).font(.system(size: Icon.s)).foregroundStyle(Ink.text.primary)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Size.row)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                    Image(systemName: isExpanded ? Symbol.chevronDown : Symbol.chevronRight)
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

/// One marker per run in the chat: `>_ 4 COMMANDS · 6.1 s · 1 failed`; with an action it focuses the terminal pane.
public struct RunMarker: View {
    let commands: Int
    let duration: String
    let failed: Int
    let action: (@MainActor () -> Void)?

    public init(commands: Int, duration: String, failed: Int = 0, action: (@MainActor () -> Void)? = nil) {
        self.commands = commands
        self.duration = duration
        self.failed = failed
        self.action = action
    }

    private var text: some View {
        HStack(spacing: Space.s) {
            Text(">_").typeRole(.monoSmall, weight: .bold)
            Text(verbatim: "\(commands) \(commands == 1 ? "command" : "commands") · \(duration)").typeRole(.label)
            if failed > 0 { Text(verbatim: "· \(failed) failed").typeRole(.label).foregroundStyle(Ink.text.error) }
        }
        .foregroundStyle(Ink.text.primary)
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .background(Ink.surface.sunken)
        .edge(Ink.line.rule)
        .accessibilityElement(children: .combine)
    }

    public var body: some View {
        if let action {
            Button(action: action) { text }.buttonStyle(.plain)
        } else {
            text
        }
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
        RunMarker(commands: 4, duration: "6.1 s", failed: 1)
    }
    .frame(width: 320).padding().background(Ink.surface.window)
}
