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
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(language ?? "").typeRole(.label).foregroundStyle(Theme.secondary)
                Spacer()
                EndfieldButton("Copy", symbol: Symbol.copy, kind: .quiet, iconOnly: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
            }
            ScrollView(.horizontal) {
                Text(code).typeRole(.mono).foregroundStyle(Theme.ink).fixedSize().textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken)
    }
}

/// WORKING, elapsed, and a 2 px track with a yellow sweep (static under Reduce Motion).
public struct WorkingIndicator: View {
    let detail: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(detail: String) { self.detail = detail }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Working").typeRole(.label)
                Text(detail).typeRole(.monoSmall).foregroundStyle(Theme.secondary)
                Spacer()
                Text("⌘. stop").typeRole(.caption).foregroundStyle(Theme.muted)
            }
            TimelineView(.animation(paused: reduceMotion)) { context in
                let phase = reduceMotion ? 0.35 : (context.date.timeIntervalSinceReferenceDate / 1.4).truncatingRemainder(dividingBy: 1)
                Rectangle().fill(Theme.rule).frame(height: 2)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle().fill(Theme.yellow)
                                .frame(width: geo.size.width * 0.3)
                                .offset(x: geo.size.width * 0.7 * phase)
                        }
                    }
                    .clipped()
            }
            .frame(height: 2)
        }
        .foregroundStyle(Theme.ink)
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
            Rectangle().fill(Theme.yellow).frame(height: 3)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Rectangle().fill(Theme.magenta).frame(width: 8, height: 8)
                    Text("Approval // Required").typeRole(.label)
                    Spacer()
                    Text(tool).typeRole(.monoSmall).foregroundStyle(Theme.muted)
                }
                Text(command).typeRole(.mono).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(Theme.sunken)
                Text(explanation).typeRole(.callout).foregroundStyle(Theme.secondary)
                HStack(spacing: 8) {
                    // No keyboard shortcuts on approval buttons: macOS fires key equivalents before the focused text field, so
                    // Return (or ⌘⌫) typed in the steer field would answer the approval. Approvals are click-only.
                    EndfieldButton("Once", symbol: Symbol.check, kind: .primary) { onChoice(.once) }
                    EndfieldButton("Session", symbol: Symbol.clock) { onChoice(.session) }
                    Spacer()
                    EndfieldButton("Deny", symbol: Symbol.close, kind: .danger) {
                        onChoice(.deny)
                    }
                }
                Text("click to answer · “always” is never offered").typeRole(.caption).foregroundStyle(Theme.muted)
            }
            .padding(12)
        }
        .foregroundStyle(Theme.ink)
        .background(Theme.raised)
        .shadow(color: Theme.ink.opacity(0.12), radius: 12, y: 4)
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
    /// The accent column, top to bottom (sampled from the reference card), then a grey track.
    static let accents = [Color(hex: 0x1FE5E0), Color(hex: 0xDA16DC), Theme.yellow, Theme.muted.opacity(0.5)]

    let title: String
    let detail: String?
    let command: String
    let output: String?
    let exitCode: Int?
    let isRunning: Bool
    let startedAt: Date?
    let duration: Double?
    @State private var expanded = false
    @State private var folded = false

    /// - Parameters:
    ///   - title: the header's text, e.g. `14:02:11 terminal`.
    ///   - detail: a line above the command (the working directory).
    ///   - startedAt: while running, the header counts up from it.
    ///   - duration: once finished, seconds, shown in the header.
    public init(
        title: String, detail: String? = nil, command: String, output: String? = nil, exitCode: Int? = nil,
        isRunning: Bool = false, startedAt: Date? = nil, duration: Double? = nil
    ) {
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
    private static let shape = UnevenRoundedRectangle(topTrailingRadius: 8, style: .continuous)

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !folded { content }
            Rectangle().fill(Theme.rule).frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised)
        .clipShape(Self.shape)
        // A faded shadow instead of an outline. It is the shadow of a plain shape, cheap to draw (#28).
        .background { Self.shape.fill(Theme.raised).shadow(color: Theme.ink.opacity(0.16), radius: 5, y: 1) }
    }

    private var header: some View {
        Button { folded.toggle() } label: {
            HStack(spacing: 8) {
                Rectangle().frame(width: 8, height: 1.5)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                headerTrailing
                // A dropdown's convention: down opens, up closes.
                Image(systemName: folded ? Symbol.chevronDown : Symbol.chevronUp)
                    .font(.system(size: 9, weight: .bold)).frame(width: 10)
            }
            .typeRole(.monoSmall).fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.arkOrange)
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
            Text(String(format: "%.1f s", duration)).opacity(0.85)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let detail {
                Text(detail).typeRole(.monoSmall).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.head)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$").foregroundStyle(Theme.blue)
                Text(command).foregroundStyle(Theme.ink)
            }
            .typeRole(.mono)
            if let output {
                let preview = expanded ? nil : Self.preview(output)
                Text(preview?.text ?? output).typeRole(.monoSmall).foregroundStyle(Theme.ink)
                if let preview {
                    Button { expanded = true } label: {
                        HStack(spacing: 4) {
                            Text("\(preview.hidden) more \(preview.hidden == 1 ? "line" : "lines")")
                            Image(systemName: Symbol.chevronDown).font(.system(size: 9))
                        }
                        .typeRole(.monoSmall).foregroundStyle(Theme.blue)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show the whole output")
                }
            }
            if isRunning {
                Rectangle().fill(Theme.ink).frame(width: 7, height: 13).accessibilityLabel("Running")
            } else if let exitCode {
                Text("exit \(exitCode)").typeRole(.monoSmall)
                    .foregroundStyle(exitCode == 0 ? Theme.terminalGreen : Theme.terminalRed)
            }
        }
        .padding(.leading, 10).padding(.trailing, 14).padding(.top, 8).padding(.bottom, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .topLeading)
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ForEach(Self.accents.indices, id: \.self) { Rectangle().fill(Self.accents[$0]).frame(width: 4, height: 11) }
            }
            .padding(.top, 7)
            .accessibilityHidden(true)
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
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
        TerminalEntryView(title: "12:04:31 terminal", command: "ls ~/Projects", output: "endfield-dotfiles\nhomelab", exitCode: 0, duration: 0.3)
        TerminalEntryView(title: "12:04:40 terminal", command: "pytest -q tests/", exitCode: 1, duration: 4.8)
        TerminalEntryView(title: "12:04:50 terminal", command: "sleep 30", isRunning: true, startedAt: .now)
    }
    .padding().frame(width: 360).background(Theme.paper)
}
