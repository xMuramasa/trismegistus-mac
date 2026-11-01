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
        .background(Ink.surface.sunken)
    }
}

/// WORKING, elapsed, and a 2 px track with a yellow sweep (static under Reduce Motion).
public struct WorkingIndicator: View {
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The sweep: a third of the track wide, across it every 1.4 s, parked at 35 % under Reduce Motion.
    private static let sweepPeriod = 1.4, sweepWidth = 0.3, restingPhase = 0.35

    public init(detail: String) { self.detail = detail }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Text("Working").typeRole(.label)
                Text(detail).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                Spacer()
                Text("⌘. stop").typeRole(.caption).foregroundStyle(Ink.text.muted)
            }
            TimelineView(.animation(paused: reduceMotion)) { context in
                let phase = reduceMotion
                    ? Self.restingPhase
                    : (context.date.timeIntervalSinceReferenceDate / Self.sweepPeriod).truncatingRemainder(dividingBy: 1)
                Rectangle().fill(Ink.line.rule).frame(height: Stroke.accent)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().fill(Ink.selection)
                                .frame(width: geo.size.width * Self.sweepWidth)
                                .offset(x: geo.size.width * (1 - Self.sweepWidth) * phase)
                        }
                    }
                    .clipped()
            }
            .frame(height: Stroke.accent)
        }
        .foregroundStyle(Ink.text.primary)
        .accessibilityElement(children: .combine)
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
        .background(Ink.surface.raised)
        .shadow(Shadow.panel)
    }
}

/// One tool call in the terminal pane: meta line, `$ command`, output, exit code or a running cursor. Output longer than
/// `previewLines` shows its first lines and a button for the rest: the history has outputs in full, and typesetting
/// thousands of lines is what a row costs when it scrolls into view.
/// One tool call in the terminal pane, after Arknights' item cards (Martin's reference): an orange header (a dash, the
/// time and tool in white, the duration, a chevron that folds the entry), then the command and its output with the
/// cyan/magenta/yellow accent column on the right, and a rule under it; a white box with a rounded top-right corner
/// and a faded shadow for an outline.
public struct TerminalEntryView: View {
    public static let previewLines = 12
    /// The accent column, top to bottom (sampled from the reference card), the last one a faded track.
    static let accents: [Color] = Ink.card.accents.dropLast() + [Ink.card.accents.last!.opacity(Opacity.track)]

    let title: String
    let detail: String?
    let command: String
    let output: String?
    let exitCode: Int?
    let isRunning: Bool
    let startedAt: Date?
    let duration: Double?
    @State private var expanded = false
    @State private var folded: Bool
    /// The body's natural height, once laid out: past `maxBodyHeight` it scrolls.
    @State private var bodyHeight: CGFloat?

    /// A conversation row in the sidebar (`SessionRowView`, measured in `TerminalEntryTests`).
    static let rowHeight = Size.row
    static let headerHeight = Size.cardHeader
    /// A card is at most eight conversation rows tall (Martin); the body scrolls inside it.
    static let maxBodyHeight = Size.cardMaxRows * rowHeight - headerHeight - 1

    /// - Parameters:
    ///   - title: the header's text, e.g. `14:02:11 terminal`.
    ///   - detail: a line above the command (the working directory).
    ///   - startedAt: while running, the header counts up from it.
    ///   - duration: once finished, seconds, shown in the header.
    ///   - startsFolded: entries start as their header only (Martin); a click opens one.
    public init(
        title: String, detail: String? = nil, command: String, output: String? = nil, exitCode: Int? = nil,
        isRunning: Bool = false, startedAt: Date? = nil, duration: Double? = nil, startsFolded: Bool = true
    ) {
        _folded = State(initialValue: startsFolded)
        self.title = title
        self.detail = detail
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.isRunning = isRunning
        self.startedAt = startedAt
        self.duration = duration
    }

    /// Square but for the top-right corner (Martin's pick, against Endfield's zero rounding).
    private static let shape = UnevenRoundedRectangle(topTrailingRadius: Radius.card, style: .continuous)

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !folded { cappedContent }
            Rectangle().fill(Ink.line.rule).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.raised)
        .clipShape(Self.shape)
        // A faded shadow instead of an outline. It is the shadow of a plain shape, cheap to draw (#28).
        .background { Self.shape.fill(Ink.surface.raised).shadow(Shadow.card) }
    }

    private var header: some View {
        Button { folded.toggle() } label: {
            HStack(spacing: Space.s) {
                Rectangle().frame(width: Size.cardDash.width, height: Size.cardDash.height)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: Space.s)
                headerTrailing
                // A dropdown's convention: down opens, up closes.
                Image(systemName: folded ? Symbol.chevronDown : Symbol.chevronUp)
                    .font(.system(size: Icon.xs, weight: .bold)).frame(width: Icon.s)
            }
            .typeRole(.monoSmall, weight: .semibold)
            .foregroundStyle(Ink.card.onHeader)
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, minHeight: Self.headerHeight, maxHeight: Self.headerHeight, alignment: .leading)
            .background(Ink.card.header)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(folded ? "Show the command" : "Fold the command")
        .accessibilityLabel(title)
        .accessibilityHint(folded ? "Shows the command and its output" : "Hides the command and its output")
    }

    @ViewBuilder private var headerTrailing: some View {
        if isRunning, let startedAt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let s = max(0, Int(context.date.timeIntervalSince(startedAt)))
                Text(String(format: "%02d:%02d", s / 60, s % 60))
            }
        } else if let duration {
            Text(String(format: "%.1f s", duration)).opacity(Opacity.cardDetail)
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
                Text(preview?.text ?? output).typeRole(.monoSmall).foregroundStyle(Ink.text.primary)
                if let preview {
                    Button { expanded = true } label: {
                        HStack(spacing: Space.xs) {
                            Text("\(preview.hidden) more \(preview.hidden == 1 ? "line" : "lines")")
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
                Text("exit \(exitCode)").typeRole(.monoSmall)
                    .foregroundStyle(exitCode == 0 ? Ink.status.ok : Ink.status.error)
            }
        }
        .padding(.leading, Space.m).padding(.trailing, Space.l).padding(.top, Space.s).padding(.bottom, Space.m)
        .frame(maxWidth: .infinity, minHeight: Size.cardBodyMin, alignment: .topLeading)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    /// The body as it is while short; past `maxBodyHeight`, in a scroll view that height. The natural height doesn't
    /// depend on the height it is given (only on the width), so measuring it can't loop. Short bodies get no scroll
    /// view, so the wheel scrolls the pane over them. The accents stay put while the body scrolls.
    private var cappedContent: some View {
        let measured = content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bodyHeight = $0 }
        return Group {
            if let bodyHeight, bodyHeight > Self.maxBodyHeight {
                ScrollView { measured }.frame(height: Self.maxBodyHeight)
            } else {
                measured
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ForEach(Self.accents.indices, id: \.self) {
                    Rectangle().fill(Self.accents[$0]).frame(width: Stroke.cardAccent, height: Size.cardAccent)
                }
            }
            .padding(.top, Space.s)
            .accessibilityHidden(true)
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

#Preview("Blocks") {
    VStack(alignment: .leading, spacing: 16) {
        WorkingIndicator(detail: "00:42 · 3 tools")
        CodeBlockView(language: "bash", code: "cd ~/Projects/homelab/penpot\ndocker compose up -d --wait")
        ApprovalBannerView(
            tool: "terminal", command: "rm -rf ~/.cache/trismegistus-build",
            explanation: "Clear the stale build cache before the release build.", onChoice: { _ in })
        TerminalEntryView(title: "12:04:31 terminal", command: "ls ~/Projects", output: "endfield-dotfiles\nhomelab", exitCode: 0, duration: 0.3, startsFolded: false)
        TerminalEntryView(title: "12:04:40 terminal", command: "pytest -q tests/", exitCode: 1, duration: 4.8)
        TerminalEntryView(title: "12:04:50 terminal", command: "sleep 30", isRunning: true, startedAt: .now)
    }
    .padding().frame(width: 360).background(Ink.surface.window)
}
