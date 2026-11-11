import AppKit
import SwiftUI

/// Fenced code from the Markdown answer: language label, icon-only copy button, scrolls sideways.
public struct CodeBlockView: View {
    let language: String?
    let code: String

    public init(language: String? = nil, code: String) {
        self.language = language
        self.code = code
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(language ?? "").typeRole(.label).foregroundStyle(Ink.text.secondary)
                Spacer()
                EndfieldButton("Copy", symbol: Symbol.copy, kind: .quiet, iconOnly: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
            }
            ScrollView(.horizontal) {
                Text(code).typeRole(.mono).foregroundStyle(Ink.text.primary).fixedSize().textSelection(.enabled)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rounded(Radius.l, fill: Ink.surface.sunken)
    }
}

public enum ApprovalAction: Sendable {
    case once, session, deny
}

/// Pinned at the top of the chat while a request is open. `always` is never offered (the protocol forbids it).
public struct ApprovalBannerView: View {
    let tool: String
    let command: String
    let explanation: String
    let onChoice: @MainActor (ApprovalAction) -> Void

    public init(tool: String, command: String, explanation: String, onChoice: @escaping @MainActor (ApprovalAction) -> Void) {
        self.tool = tool
        self.command = command
        self.explanation = explanation
        self.onChoice = onChoice
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Ink.selection).frame(height: Stroke.mark)
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    Rectangle().fill(Ink.marker).frame(width: Size.marker, height: Size.marker)
                    Text("Approval // Required").typeRole(.label)
                    Spacer()
                    Text(tool).typeRole(.monoSmall).foregroundStyle(Ink.text.muted)
                }
                Text(command).typeRole(.mono).textSelection(.enabled)
                    .padding(Space.s).frame(maxWidth: .infinity, alignment: .leading).background(Ink.surface.sunken)
                Text(explanation).typeRole(.callout).foregroundStyle(Ink.text.secondary)
                HStack(spacing: Space.s) {
                    // No keyboard shortcuts on approval buttons: macOS fires key equivalents before the focused text field, so
                    // Return (or ⌘⌫) typed in the steer field would answer the approval. Approvals are click-only.
                    EndfieldButton("Once", symbol: Symbol.check, kind: .primary) { onChoice(.once) }
                    EndfieldButton("Session", symbol: Symbol.clock) { onChoice(.session) }
                    Spacer()
                    EndfieldButton("Deny", symbol: Symbol.close, kind: .danger) {
                        onChoice(.deny)
                    }
                }
                Text("click to answer · “always” is never offered").typeRole(.caption).foregroundStyle(Ink.text.muted)
            }
            .padding(Space.m)
        }
        .foregroundStyle(Ink.text.primary)
        // An `l` box (#68): the yellow bar follows its top corners.
        .rounded(Radius.l, fill: Ink.surface.raised)
        .shadow(Shadow.panel)
    }
}

/// One tool call, in the terminal pane, the Commands log and under the chat's chip, after Arknights' item cards (Martin's
/// reference): an orange header (time, tool, the command's first line, duration, the exit chip when it failed, a chevron
/// that folds the entry), then the command and its output, an accent column down the right by tool; a white box with a
/// rounded top-right corner and a faded shadow for an outline. `oneLine` draws the header as a 28 pt tool row instead
/// (`.tool-row.commands`); rows stack edge to edge. Output longer than `previewLines` shows its first lines and a button
/// for the rest: the history has outputs in full, and typesetting thousands of lines is what a row costs when it scrolls
/// into view.
public struct TerminalEntryView: View {
    public static let previewLines = 12

    let time: String
    let tool: String
    let detail: String?
    let command: String
    let output: String?
    let exitCode: Int?
    let failed: Bool
    let isRunning: Bool
    let startedAt: Date?
    let duration: Double?
    let oneLine: Bool
    /// The time column's width: a list holding an earlier day's call (`3 Nov 22:40:12`) passes `Size.toolRow.timeDated`
    /// to every entry, so the columns line up down the list.
    let timeWidth: CGFloat?
    var forceHovered = false  // snapshots and previews: hover can't be set from outside
    @State private var expanded = false
    @State private var folded: Bool
    @State private var hovered = false
    /// The Commands log's rows (#69); the chat's chip keeps #68's look.
    @Environment(\.hairlineControls) private var hairline
    /// The body's natural height, once laid out: past `maxBodyHeight` it scrolls.
    @State private var bodyHeight: CGFloat?

    /// A conversation row in the sidebar (`SessionRowView`, measured in `TerminalEntryTests`).
    static let rowHeight = Size.row
    static let headerHeight = Size.cardHeader
    /// A card is at most eight conversation rows tall (Martin); the body scrolls inside it.
    static let maxBodyHeight = Size.cardMaxRows * rowHeight - headerHeight

    /// - Parameters:
    ///   - time: the header's clock, e.g. `14:02:11`.
    ///   - detail: a line above the command (the working directory).
    ///   - failed: the tool reported an error; a non-zero `exitCode` counts without it.
    ///   - startedAt: while running, the header counts up from it.
    ///   - duration: once finished, seconds, shown in the header.
    ///   - startsFolded: entries start as their header only (Martin); a click opens one.
    public init(
        time: String, tool: String, detail: String? = nil, command: String, output: String? = nil, exitCode: Int? = nil,
        failed: Bool = false, isRunning: Bool = false, startedAt: Date? = nil, duration: Double? = nil,
        startsFolded: Bool = true, oneLine: Bool = false, timeWidth: CGFloat? = nil
    ) {
        _folded = State(initialValue: startsFolded)
        self.time = time
        self.tool = tool
        self.detail = detail
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.failed = failed || (exitCode ?? 0) != 0
        self.isRunning = isRunning
        self.startedAt = startedAt
        self.duration = duration
        self.oneLine = oneLine
        self.timeWidth = timeWidth
    }

    /// The first line that isn't blank, as written but for its indent and trailing space (an indented first line pushed
    /// the column out of line with the rows around it).
    static func firstLine(_ command: String) -> String {
        command.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) }
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// The accent column: scan the log by kind of tool.
    static func accent(_ tool: String) -> Color {
        switch tool {
        case "terminal": Ink.card.accents[0]
        case "vision_analyze": Ink.card.accents[1]
        default: Ink.card.accents[2]
        }
    }

    /// A non-zero exit code; zero with `failed` set is the tool's own error.
    private var failedExit: Int? { exitCode.flatMap { $0 != 0 ? $0 : nil } }

    /// Square but for the top-right corner (Martin's pick, against Endfield's zero rounding).
    private static let shape = UnevenRoundedRectangle(topTrailingRadius: Radius.l, style: .continuous)

    public var body: some View {
        if oneLine && hairline {
            // #69 (`.crow`): a light row with a rule hairline and a 3 pt left edge, green or red by its exit.
            VStack(spacing: 0) {
                foldButton { row }
                if !folded { cappedContent }
            }
            .background(Ink.surface.sectionCard)
            .overlay(alignment: .leading) { Rectangle().fill(failed ? Ink.status.error : Ink.status.ok).frame(width: Stroke.mark) }
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .edge(Ink.line.rule, radius: Radius.control)
            .onHover { hovered = $0 }
        } else if oneLine {
            VStack(spacing: 0) {
                foldButton { row }
                if !folded { cappedContent.background(Ink.surface.window) }
            }
            .onHover { hovered = $0 }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            foldButton { header }
            if !folded { cappedContent }
        }
        .padding(.trailing, Size.cardEdge)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Self.accent(tool)).frame(width: Size.cardEdge).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.raised)
        .clipShape(Self.shape)
        // A faded shadow instead of an outline. It is the shadow of a plain shape, cheap to draw (#28).
        .background { Self.shape.fill(Ink.surface.raised).shadow(Shadow.card) }
    }

    private func foldButton(@ViewBuilder label: () -> some View) -> some View {
        Button { folded.toggle() } label: { label().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .help(folded ? "Show the command" : "Fold the command")
            .accessibilityLabel(Text(verbatim: "\(time) \(tool) \(Self.firstLine(command))\(failed ? ", failed" : "")"))
            .accessibilityHint(folded ? "Shows the command and its output" : "Hides the command and its output")
    }

    private var header: some View {
        HStack(spacing: Space.m) {
            Text(time).fixedSize().frame(minWidth: timeWidth, alignment: .leading)
            // The column's width when there is room (`vision_analyze` fits); in a narrow pane it gives way before the
            // card overflows, after the first line has gone to "…".
            Text(tool).lineLimit(1).frame(minWidth: 0, maxWidth: Size.cardTool, alignment: .leading).layoutPriority(1)
            Text(Self.firstLine(command)).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            // The prototype's order: the chip, then the duration in a fixed cell, so durations line up down the list.
            if let failedExit {
                ExitChip(failedExit)
            } else if failed {
                StatusChip("failed", kind: .err)
            }
            Color.clear.frame(width: Size.toolRow.duration, height: Size.toolRow.cell).overlay(alignment: .trailing) { elapsed.fixedSize() }
            chevron
        }
        .typeRole(.mono)
        .lineLimit(1)
        .foregroundStyle(Ink.card.onHeader)
        .padding(.horizontal, Space.s)
        .frame(maxWidth: .infinity, minHeight: Self.headerHeight, maxHeight: Self.headerHeight, alignment: .leading)
        .background(Ink.card.header)
    }

    private var row: some View {
        HStack(spacing: Space.m) {
            // #69: the command stays mono, everything around it Inter.
            Text(time).typeRole(hairline ? .caption : .monoSmall).monospacedDigit().foregroundStyle(hairline ? Ink.text.secondary : Ink.text.primary)
                .fixedSize().frame(minWidth: timeWidth ?? Size.toolRow.time, alignment: .leading)
            Text(tool).typeRole(hairline ? .trackedLabel : .monoSmall).foregroundStyle(hairline ? Ink.text.secondary : Ink.text.primary)
                .frame(width: Size.toolRow.nameWide, alignment: .leading)
            Text(Self.firstLine(command)).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            // The cells stay while they are empty, so the columns line up down the list.
            Color.clear.frame(width: Size.toolRow.duration).overlay(alignment: .trailing) {
                elapsed.typeRole(hairline ? .caption : .monoSmall).monospacedDigit().foregroundStyle(Ink.text.secondary)
            }
            Color.clear.frame(width: Size.toolRow.statusNarrow).overlay(alignment: .leading) { status }
            chevron
        }
        .typeRole(.monoSmall)
        .lineLimit(1)
        .foregroundStyle(Ink.text.primary)
        .padding(.leading, hairline ? Space.l : Space.m).padding(.trailing, Space.m)
        .frame(height: Size.rowTool)
        .background(hovered || forceHovered ? Ink.surface.window : hairline ? .clear : Ink.surface.raised)
        .overlay(alignment: .top) { if !hairline { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairlineFine) } }
    }

    private var chevron: some View {
        Image(systemName: Symbol.fold(isOpen: !folded)).font(.system(size: Icon.l))
            .frame(width: Size.toolRow.cell).accessibilityHidden(true)
    }

    @ViewBuilder private var elapsed: some View {
        if isRunning, let startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let s = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text(String(format: "%02d:%02d", s / 60, s % 60))
            }
        } else if let duration {
            Text(String(format: "%.1f s", duration))
        }
    }

    /// Nothing until there is a result: no duration yet means no verdict either.
    @ViewBuilder private var status: some View {
        if let failedExit {
            Text(verbatim: "exit \(failedExit)").typeRole(.label).monospacedDigit().foregroundStyle(Ink.status.error)
        } else if failed {
            Text(verbatim: "failed").typeRole(.label).foregroundStyle(Ink.status.error)
        } else if !isRunning, duration != nil {
            HStack(spacing: Space.xs) {
                Image(systemName: Symbol.check).font(.system(size: Icon.m, weight: .semibold)).accessibilityHidden(true)
                Text(verbatim: "OK").typeRole(.label)
            }
            .foregroundStyle(Ink.status.ok)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if let detail {
                Text(detail).typeRole(.monoSmall).foregroundStyle(Ink.text.muted).lineLimit(1).truncationMode(.head)
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                Text("$").foregroundStyle(Ink.text.link)
                Text(command).foregroundStyle(Ink.text.primary)
            }
            .typeRole(.mono)
            if let output {
                let preview = expanded ? nil : Self.preview(output)
                Text(preview?.text ?? output).typeRole(.monoSmall)
                    .foregroundStyle(failed ? Ink.status.error : Ink.text.primary)
                if let preview {
                    Button { expanded = true } label: {
                        HStack(spacing: Space.xs) {
                            Text(verbatim: "\(preview.hidden) more \(preview.hidden == 1 ? "line" : "lines")")
                            Image(systemName: Symbol.chevronDown).font(.system(size: Icon.xs))
                        }
                        .typeRole(.monoSmall).foregroundStyle(Ink.text.link)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show the whole output")
                }
            }
            if isRunning {
                Rectangle().fill(Ink.text.primary).frame(width: Size.cursor.width, height: Size.cursor.height)
                    .accessibilityLabel("Running")
            } else if let exitCode {
                Text(verbatim: "exit \(exitCode)").typeRole(.monoSmall)
                    .foregroundStyle(exitCode == 0 ? Ink.status.ok : Ink.status.error)
            }
        }
        .padding(.horizontal, Space.m).padding(.top, Space.s).padding(.bottom, Space.m)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    /// The body as it is while short; past `maxBodyHeight`, in a scroll view that height. The natural height doesn't
    /// depend on the height it is given (only on the width), so measuring it can't loop. Short bodies get no scroll
    /// view, so the wheel scrolls the pane over them.
    @ViewBuilder private var cappedContent: some View {
        let measured = content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
        if let bodyHeight, bodyHeight > Self.maxBodyHeight {
            ScrollView { measured }.frame(height: Self.maxBodyHeight)
        } else {
            measured
        }
    }

    /// The first `previewLines` lines and how many are left, or nil when the output is that short.
    static func preview(_ output: String) -> (text: String, hidden: Int)? {
        let utf8 = output.utf8
        var end = utf8.startIndex
        for _ in 0..<previewLines {
            guard let newline = utf8[end...].firstIndex(of: 10) else { return nil }
            end = utf8.index(after: newline)
        }
        let rest = utf8[end...]
        guard !rest.isEmpty else { return nil }
        return (String(output[..<utf8.index(before: end)]), rest.count(where: { $0 == 10 }) + (rest.last == 10 ? 0 : 1))
    }
}

/// One conversation's head in the Commands log (`.cmd-head`): the conversation as a link, its counts, a fold toggle, a
/// 1 pt contour rule under it (#69).
public struct CommandGroupHead: View {
    let title: String
    let calls: Int
    let failed: Int
    let isOpen: Bool
    let onOpen: () -> Void
    let onFold: () -> Void

    public init(title: String, calls: Int, failed: Int, isOpen: Bool, onOpen: @escaping () -> Void, onFold: @escaping () -> Void) {
        self.title = title
        self.calls = calls
        self.failed = failed
        self.isOpen = isOpen
        self.onOpen = onOpen
        self.onFold = onFold
    }

    public var body: some View {
        VStack(spacing: Space.xs) {
            HStack(spacing: Space.m) {
                Button(action: onOpen) {
                    HStack(spacing: Space.xs) {
                        Text(title).typeRole(.headline).lineLimit(1)
                        Image(systemName: Symbol.chevronRight).font(.system(size: Icon.l)).accessibilityHidden(true)
                    }
                    .foregroundStyle(Ink.text.link)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open the conversation")
                Text(verbatim: "\(calls) \(calls == 1 ? "call" : "calls")").typeRole(.callout).monospacedDigit()
                    .foregroundStyle(Ink.text.secondary).fixedSize()
                if failed > 0 {
                    Text(verbatim: "\(failed) failed").typeRole(.callout, weight: .semibold).monospacedDigit().foregroundStyle(Ink.status.error).fixedSize()
                }
                Spacer(minLength: 0)
                Button(action: onFold) {
                    Image(systemName: Symbol.fold(isOpen: isOpen)).font(.system(size: Icon.l))
                        .foregroundStyle(Ink.text.primary)
                        .frame(width: Space.xxl, height: Space.xxl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isOpen ? "Fold" : "Unfold")
                .accessibilityLabel(Text(verbatim: "\(isOpen ? "Fold" : "Unfold") \(title)"))
            }
            Rectangle().fill(Ink.line.contour).frame(height: Stroke.hairline)
        }
    }
}

/// Under a group that hides calls (`.cmd-foot`): how many show, and the button for the rest unless a filter hid them.
public struct CommandGroupFoot: View {
    let shown: Int
    let total: Int
    let onMore: (() -> Void)?

    public init(shown: Int, total: Int, onMore: (() -> Void)?) {
        self.shown = shown
        self.total = total
        self.onMore = onMore
    }

    public var body: some View {
        HStack(spacing: Space.m) {
            Text(verbatim: "showing \(shown) of \(total)").typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
            if let onMore {
                Button(action: onMore) {
                    HStack(spacing: Space.xs) {
                        Text("Show more").textCase(.uppercase)
                        Image(systemName: Symbol.chevronDown).font(.system(size: Icon.l)).accessibilityHidden(true)
                    }
                    .typeRole(.button).foregroundStyle(Ink.text.primary)
                    .frame(height: Size.rowTool)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview("Blocks") {
    VStack(alignment: .leading, spacing: 16) {
        CodeBlockView(language: "bash", code: "cd ~/Projects/homelab/penpot\ndocker compose up -d --wait")
        ApprovalBannerView(
            tool: "terminal", command: "rm -rf ~/.cache/trismegistus-build",
            explanation: "Clear the stale build cache before the release build.", onChoice: { _ in })
        TerminalEntryView(time: "12:04:31", tool: "terminal", command: "ls ~/Projects", output: "endfield-dotfiles\nhomelab", exitCode: 0, duration: 0.3, startsFolded: false)
        TerminalEntryView(time: "12:04:40", tool: "terminal", command: "pytest -q tests/", exitCode: 1, duration: 4.8)
        TerminalEntryView(time: "12:04:50", tool: "terminal", command: "sleep 30", isRunning: true, startedAt: .now)
    }
    .padding().frame(width: 360).background(Ink.surface.window)
}
