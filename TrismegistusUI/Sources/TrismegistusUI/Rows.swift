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
        case .linked: Theme.green
        case .reconnecting: Theme.yellow
        case .offline: .clear
        }
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 7, height: 7).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
            Text(label).typeRole(.label)
            Text(detail).typeRole(.monoSmall).foregroundStyle(Theme.secondary)
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
        HStack(spacing: 6) {
            Text(key).typeRole(.monoSmall).foregroundStyle(Theme.secondary)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .edge(Theme.secondary)
            Text(action).typeRole(.caption).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Hints along the bottom edge, with a rule on top.
public struct KeyHintStrip: View {
    let hints: [(key: String, action: String)]

    public init(_ hints: [(key: String, action: String)]) { self.hints = hints }

    public var body: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.key) { KeyHint($0.key, $0.action) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }
}

/// Heading with the three-segment rule under it (magenta, yellow, green, then a hairline).
public struct TitleRule: View {
    let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).typeRole(.heading).foregroundStyle(Theme.ink)
            SegmentRule()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Endfield's title rule alone: magenta, yellow and green segments, then a hairline to the end unless `hairline` is
/// off. `TitleRule` draws it at 34/88/18 × 2 pt; the window's conversation header at 48/120/24 × 4 pt (#32).
public struct SegmentRule: View {
    let widths: (magenta: CGFloat, yellow: CGFloat, green: CGFloat)
    let height: CGFloat
    let hairline: Bool

    public init(_ widths: (magenta: CGFloat, yellow: CGFloat, green: CGFloat) = (34, 88, 18), height: CGFloat = 2, hairline: Bool = true) {
        self.widths = widths
        self.height = height
        self.hairline = hairline
    }

    public var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Theme.magenta).frame(width: widths.magenta)
            Rectangle().fill(Theme.yellow).frame(width: widths.yellow)
            Rectangle().fill(Theme.green).frame(width: widths.green)
            if hairline { Rectangle().fill(Theme.rule) }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

public extension EnvironmentValues {
    /// True in the window's sidebar (`SidebarSplit` sets it): rows sit on its `sunken` ground, the selected one white
    /// with a 1 pt yellow border, meta text in `secondary` (muted is too faint on sunken). Off (the popover): white
    /// rows, a yellow bar on the selected one, meta in `muted`.
    @Entry var sunkenRows = false
}

public extension View {
    /// The ground and selection mark of a list row (`SessionRowView`, the app's News and Commands rows); see
    /// `sunkenRows`. On sunken the fill is opaque so the list's own selection highlight never shows through.
    func rowGround(isSelected: Bool) -> some View { modifier(RowGround(isSelected: isSelected)) }
}

private struct RowGround: ViewModifier {
    let isSelected: Bool
    @Environment(\.sunkenRows) private var sunken

    func body(content: Content) -> some View {
        if sunken {
            content
                .padding(.leading, 3)
                .background(isSelected ? Theme.raised : Theme.sunken)
                .overlay { if isSelected { Rectangle().strokeBorder(Theme.yellow, lineWidth: 1) } }
                // macOS keeps an 8 pt inset on list rows and draws its selection highlight (blue in a key window)
                // across the full row, so it showed in those margins beside the selected row. A sunken backing
                // under the margins hides it whatever the window state.
                .background { Theme.sunken.padding(.horizontal, -8) }
        } else {
            HStack(spacing: 0) {
                Rectangle().fill(isSelected ? Theme.yellow : .clear).frame(width: 3)
                content
            }
            .background(Theme.raised)
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

    @Environment(\.sunkenRows) private var sunken

    public var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).typeRole(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 6) {
                    SourceIcon(source)
                    if isReadOnly { Image(systemName: Symbol.lock).font(.system(size: 10)) }
                    Text(isReadOnly ? "\(activity) · read-only" : activity).typeRole(.monoSmall)
                }
                .foregroundStyle(sunken ? Theme.secondary : Theme.muted)
            }
            Spacer(minLength: 8)
            if needsApproval {
                Text("Approval").typeRole(.label).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.magenta)
            } else if let runElapsed {
                HStack(spacing: 6) {
                    Text("Run").typeRole(.label).foregroundStyle(Theme.blue)
                    Text(runElapsed).typeRole(.monoSmall).foregroundStyle(Theme.ink)
                }
            } else if isSelected {
                Image(systemName: Symbol.chevronRight).font(.system(size: 10)).foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
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
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? Symbol.chevronDown : Symbol.chevronRight)
                        .font(.system(size: 8, weight: .bold)).frame(width: 8)
                    Text(tool).typeRole(.mono).fontWeight(.semibold)
                    Text(summary).typeRole(.monoSmall).foregroundStyle(Theme.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    if failed, let exitCode {
                        Text("Exit \(exitCode)").typeRole(.label).foregroundStyle(Theme.red)
                    }
                    Text(duration).typeRole(.monoSmall).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
            .accessibilityHint(isExpanded ? "Collapse output" : "Expand output")
            if isExpanded, let output {
                Text(output)
                    .typeRole(.monoSmall).foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.sunken)
                    .padding(6)
            }
        }
        .background(Theme.raised)
        .edge(failed ? Theme.red : Theme.rule)
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
        HStack(spacing: 8) {
            Text("Subagent").typeRole(.label).foregroundStyle(Theme.blue)
            Text(name).typeRole(.mono)
            Text("\(toolCount) tools").typeRole(.monoSmall).foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            Text(duration).typeRole(.monoSmall).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.raised)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.blue).frame(width: 3) }
        .edge(Theme.rule)
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
        HStack(spacing: 6) {
            Text(">_").typeRole(.monoSmall).fontWeight(.bold)
            Text("\(commands) \(commands == 1 ? "command" : "commands") · \(duration)").typeRole(.label)
            if failed > 0 { Text("· \(failed) failed").typeRole(.label).foregroundStyle(Theme.red) }
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.sunken)
        .edge(Theme.rule)
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
    .padding().frame(width: 360).background(Theme.paper)
}

#Preview("Session rows") {
    VStack(spacing: 1) {
        SessionRowView(name: "Homelab backup check", source: .telegram, activity: "2 h")
        SessionRowView(name: "trismegistus-mac UI draft", source: .trismegistus, activity: "now", isSelected: true)
        SessionRowView(name: "Endfield gallery render", source: .trismegistus, activity: "1 min", runElapsed: "00:42")
        SessionRowView(name: "Clean build cache", source: .trismegistus, activity: "3 min", needsApproval: true)
        SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", isReadOnly: true)
    }
    .background(Theme.rule).frame(width: 320).padding().background(Theme.paper)
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
    .frame(width: 320).padding().background(Theme.paper)
}
