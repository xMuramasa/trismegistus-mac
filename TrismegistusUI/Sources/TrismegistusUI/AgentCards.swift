import SwiftUI

// The Agents section's run cards (#60). Here rather than in the app so the snapshots draw these views; the app feeds
// them from Kit's `AgentRun`.

/// The run's outcome (`.panel`; a section card since #69): `// RESULT`, its chip and facts, a title, then the report
/// folded after 8 lines.
public struct AgentResultCard<Report: View>: View {
    let chip: StatusChip
    let meta: String
    let title: AttributedString
    @ViewBuilder let report: Report

    @State private var isOpen = false
    /// The report's natural height, once laid out.
    @State private var height: CGFloat = 0

    public init(chip: StatusChip, meta: String, title: AttributedString, @ViewBuilder report: () -> Report) {
        self.chip = chip
        self.meta = meta
        self.title = title
        self.report = report()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text(verbatim: "// Result").typeRole(.trackedLabel).foregroundStyle(Ink.text.secondary)
                chip
                Spacer(minLength: Space.s)
                Text(verbatim: meta).typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary).lineLimit(1)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).typeRole(.headline).foregroundStyle(Ink.text.primary).tint(Ink.text.link).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                report.fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                    .frame(maxHeight: isOpen ? nil : Size.reportFold, alignment: .top)
                    .clipped()
                    // Blocks don't stack in whole lines, so the fold's edge can cut one: fade the last 32 pt out.
                    .mask {
                        if !isOpen && height > Size.reportFold {
                            LinearGradient(stops: [.init(color: .black, location: 1 - Space.xxxl / Size.reportFold),
                                                   .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                        } else {
                            Rectangle()
                        }
                    }
                    .padding(.top, height > 0 ? Space.m : 0)  // an empty report takes up a slot in a stack
                if height > Size.reportFold { foldButton.padding(.top, Space.m) }
            }
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rounded(Radius.control, fill: Ink.surface.sectionCard, edge: Ink.line.rule)
    }

    private var foldButton: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Space.xs) {
                Text(isOpen ? "Show less" : "Show all").textCase(.uppercase)
                Image(systemName: Symbol.fold(isOpen: isOpen)).font(.system(size: Icon.l)).accessibilityHidden(true)
            }
            .typeRole(.button).foregroundStyle(Ink.text.primary)
            .frame(height: Size.rowTool)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isOpen ? "Folds the report" : "Shows the whole report")
    }
}

/// The run's steps in one section card (`.steps`, #69): a `// 9 STEPS` label line over a rule folds them.
public struct AgentStepsCard<Rows: View>: View {
    let line: String
    @Binding var isOpen: Bool
    @ViewBuilder let rows: Rows

    public init(line: String, isOpen: Binding<Bool>, @ViewBuilder rows: () -> Rows) {
        self.line = line
        _isOpen = isOpen
        self.rows = rows()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button { isOpen.toggle() } label: {
                HStack(spacing: Space.s) {
                    Text(verbatim: "// \(line)").typeRole(.trackedLabel).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: Symbol.fold(isOpen: isOpen)).font(.system(size: Icon.l)).accessibilityHidden(true)
                }
                .lineLimit(1)
                .foregroundStyle(Ink.text.secondary)
                .padding(.horizontal, Space.l)
                .frame(height: Size.stepsHead)
                .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides the steps" : "Shows the steps")
            if isOpen { rows }
        }
        .rounded(Radius.control, fill: Ink.surface.sectionCard, edge: Ink.line.rule)
    }
}

/// The run's scroll view. A live run opens on its tail and follows it unless scrolled up, where new steps land out of
/// sight and Follow brings the tail back; a finished run opens on its result, at the top.
public struct AgentRunScroll<Content: View>: View {
    let alive: Bool
    @ViewBuilder let content: Content

    @State private var position: ScrollPosition
    @State private var atBottom: Bool

    public init(alive: Bool, @ViewBuilder content: () -> Content) {
        self.alive = alive
        self.content = content()
        _position = State(initialValue: ScrollPosition(edge: alive ? .bottom : .top))
        _atBottom = State(initialValue: alive)
    }

    public var body: some View {
        ScrollView {
            content
                .padding(Space.l)
                .frame(maxWidth: Size.runColumn + 2 * Space.l)
                .frame(maxWidth: .infinity)
        }
        .scrollPosition($position)
        .defaultScrollAnchor(alive ? .bottom : .top, for: .initialOffset)
        .defaultScrollAnchor(alive ? .bottom : .top, for: .sizeChanges)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - Space.xxl
        } action: { _, nowAtBottom in
            atBottom = nowAtBottom
        }
        .overlay(alignment: .bottomTrailing) {
            if alive, !atBottom {
                EndfieldButton("Follow", symbol: Symbol.chevronDown, kind: .primary) {
                    atBottom = true
                    position.scrollTo(edge: .bottom)
                }
                .padding(Space.l)
            }
        }
    }
}

/// A tool's icon in its row.
public func agentToolSymbol(_ tool: String) -> String {
    switch tool {
    case "Bash": Symbol.terminal
    case "Edit", "MultiEdit", "NotebookEdit": "pencil"
    case "Write": "doc.badge.plus"
    case "Read": "doc.text"
    case "Grep", "Glob", "ToolSearch": "magnifyingglass"
    case "WebFetch", "WebSearch": "globe"
    case "Result": "arrow.turn.down.right"  // a result without its call (`AgentRun.orphanResult`)
    default: "hammer"
    }
}
