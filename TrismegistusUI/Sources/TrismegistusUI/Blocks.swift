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

/// One tool call in the terminal pane: meta line, `$ command`, output, exit code or a running cursor.
public struct TerminalEntryView: View {
    let meta: String
    let command: String
    let output: String?
    let exitCode: Int?
    let isRunning: Bool

    public init(meta: String, command: String, output: String? = nil, exitCode: Int? = nil, isRunning: Bool = false) {
        self.meta = meta
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.isRunning = isRunning
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meta).typeRole(.monoSmall).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("$").foregroundStyle(Theme.blue)
                Text(command).foregroundStyle(Theme.ink)
            }
            .typeRole(.mono)
            if let output {
                Text(output).typeRole(.monoSmall).foregroundStyle(Theme.ink).textSelection(.enabled)
            }
            if isRunning {
                Rectangle().fill(Theme.ink).frame(width: 7, height: 13).accessibilityLabel("Running")
            } else if let exitCode {
                Text("exit \(exitCode)").typeRole(.monoSmall)
                    .foregroundStyle(exitCode == 0 ? Theme.terminalGreen : Theme.terminalRed)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Blocks") {
    VStack(alignment: .leading, spacing: 16) {
        WorkingIndicator(detail: "00:42 · 3 tools")
        CodeBlockView(language: "bash", code: "cd ~/Projects/homelab/penpot\ndocker compose up -d --wait")
        ApprovalBannerView(
            tool: "terminal", command: "rm -rf ~/.cache/trismegistus-build",
            explanation: "Clear the stale build cache before the release build.", onChoice: { _ in })
        TerminalEntryView(meta: "terminal · 12:04:31", command: "ls ~/Projects", output: "endfield-dotfiles\nhomelab", exitCode: 0)
        TerminalEntryView(meta: "terminal · 12:04:40", command: "pytest -q tests/", exitCode: 1)
        TerminalEntryView(meta: "terminal · 12:04:50", command: "sleep 30", isRunning: true)
    }
    .padding().frame(width: 360).background(Theme.paper)
}
