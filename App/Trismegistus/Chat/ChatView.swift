import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// One conversation: approval banner, messages, working indicator, input. `compact` is the popover layout (tool and
/// subagent rows inline); the window passes `compact: false` and gets one marker per run that calls `onShowTerminal`.
struct ChatView: View {
    let sessionID: String
    var compact: Bool = true
    var onShowTerminal: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    /// Failed prompts already retried or steered (the outbox keeps failed prompts until the history reloads).
    @State private var hidden: Set<String> = []
    @State private var actionError: String?
    /// When this view first saw the current run, for a run with no events yet.
    @State private var runSeen = Date()
    @State private var handingOff: SessionInfo?

    /// The newest part of the conversation's thread: older parts show folded above, the composer sends here.
    private var id: String { model.store?.threadTip(of: sessionID) ?? sessionID }
    private var state: SessionState? { model.store?.sessions[id] }
    private var info: SessionInfo? { model.sessions.first { $0.id == id } }
    private var run: ActiveRun? { state?.run }
    private var approval: PendingApproval? { state?.approvals.first }

    var body: some View {
        VStack(spacing: 0) {
            if let approval { banner(approval) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    OlderParts(tipID: id, compact: compact)
                    historyStatus
                    let items = self.items
                    ChatTranscript(items: items, onShowTerminal: showTerminal, retry: retry(_:))
                    if let run { working(run) } else if let info, SessionCapabilities(info).canHandOff, Self.stalled(items) { stallRow(info) }
                }
                .padding(16)
                // A readable column: on a wide window, opening a pane or the sidebar doesn't re-wrap the messages.
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .settledWidth()
            if let run { runStrip(run) }
            input
        }
        .background(Theme.paper)
        .task(id: id) { await model.store?.open(id) }
        .onChange(of: run?.id, initial: true) { runSeen = Date() }
        .handoffSheet($handingOff)
    }

    /// The last answer or error says the model stopped answering (Hermes' stall messages).
    private static func stalled(_ items: [ChatItem]) -> Bool {
        for item in items.reversed() {
            switch item {
            case .answer(_, let text, _), .note(_, let text, true): return HandoffDigest.isStall(text)
            default: continue
            }
        }
        return false
    }

    private func stallRow(_ info: SessionInfo) -> some View {
        HStack(spacing: 8) {
            Text("The model stopped answering. Continue in a new conversation from a digest of this one.")
                .typeRole(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            EndfieldButton("Hand off", symbol: Symbol.handoff, kind: .primary) { handingOff = info }
        }
        .padding(10)
        .background(Theme.sunken)
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
    }

    private var items: [ChatItem] {
        guard let state else { return [] }
        return ChatTimeline.items(state, compact: compact).filter {
            if case .prompt(let p, _) = $0 { !hidden.contains(p.id) } else { true }
        }
    }

    private var showTerminal: (@MainActor () -> Void)? {
        guard let onShowTerminal else { return nil }
        return { onShowTerminal() }
    }

    private func banner(_ approval: PendingApproval) -> some View {
        ApprovalBannerView(
            // Hermes asks approval for terminal commands only; the request doesn't name the tool.
            tool: TerminalTranscript.terminalTool, command: approval.request.command,
            explanation: approval.request.description ?? ""
        ) { action in
            let choice: ApprovalChoice = switch action {
            case .once: .once
            case .session: .session
            case .deny: .deny
            }
            act { try await model.approve(approval, choice: choice) }
        }
        .padding([.horizontal, .top], 16)
        .zIndex(1)
    }

    @ViewBuilder private var historyStatus: some View {
        if let error = state?.historyError {
            HStack(spacing: 8) {
                Text(error).typeRole(.caption).foregroundStyle(Theme.red)
                EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) {
                    Task { await model.store?.loadHistory(id) }
                }
            }
        } else if let state, !state.historyLoaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
    }

    private func working(_ run: ActiveRun) -> some View {
        let first = state?.events.first { $0.runID == run.id }
        let start = first.map { Date(timeIntervalSince1970: Double($0.ts) / 1000) } ?? runSeen
        let tools = state.map { ChatTimeline.toolCount($0, runID: run.id) } ?? 0
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Duration.seconds(max(0, Int(context.date.timeIntervalSince(start))))
                .formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
            WorkingIndicator(
                detail: "\(elapsed) · " + (run.status == .waitingForApproval ? "approval" : "\(tools) \(tools == 1 ? "tool" : "tools")"))
        }
    }

    private func runStrip(_ run: ActiveRun) -> some View {
        HStack(spacing: 8) {
            Text("Run active").typeRole(.label).foregroundStyle(Theme.ink)
            if !isReadOnly { Text("⌘↩ steers this run").typeRole(.caption).foregroundStyle(Theme.secondary) }
            Spacer()
            EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger, iconOnly: true, shortcut: KeyboardShortcut(".", modifiers: .command)) {
                act { try await model.stop(runID: run.id) }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Theme.sunken)
    }

    private var input: some View {
        let steering = run != nil
        let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                EndfieldTextField(
                    approval != nil ? "Steer or wait" : steering ? "Steer this run" : "Message Hermes", text: $draft)
                if steering {
                    // While an approval is open, Once is the primary action.
                    EndfieldButton("Steer", symbol: Symbol.steer, kind: approval == nil ? .primary : .secondary, shortcut: KeyboardShortcut(.return, modifiers: .command)) {
                        submit()
                    }
                    .disabled(empty)
                } else {
                    EndfieldButton("Send", symbol: Symbol.send, kind: .primary, iconOnly: true, shortcut: KeyboardShortcut(.return, modifiers: .command)) {
                        submit()
                    }
                    .disabled(empty)
                }
            }
            .disabled(isReadOnly)
            if isReadOnly {
                Text("Read-only: this conversation comes from \(info?.source ?? "another app"); reply there.")
                    .typeRole(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
            }
            if let actionError {
                Text(actionError).typeRole(.caption).foregroundStyle(Theme.red).lineLimit(1)
            }
        }
        .padding(16)
        .overlay(alignment: .top) { Rectangle().fill(Theme.rule).frame(height: 1) }
    }

    private var isReadOnly: Bool { info?.isReadOnly ?? false }

    /// `⌘↩`: a prompt, or a steer while a run is active (the relay answers a prompt during a run with `busy`).
    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        if let run {
            act {
                do {
                    try await model.steer(runID: run.id, text: text)
                } catch {
                    if draft.isEmpty { draft = text }
                    throw error
                }
            }
        } else {
            Task { await model.send(text, to: id) }
        }
    }

    /// A failed prompt again: as a steer when the relay said busy and the run is still going, else as a prompt.
    private func retry(_ prompt: OutgoingPrompt) {
        hidden.insert(prompt.id)
        if case .failed(.busy, _) = prompt.status, let run {
            act { try await model.steer(runID: run.id, text: prompt.text) }
        } else {
            Task { await model.send(prompt.text, to: id) }
        }
    }

    private func act(_ operation: @escaping @MainActor () async throws -> Void) {
        actionError = nil
        Task {
            do { try await operation() } catch { actionError = "Not connected to the relay. Try again." }
        }
    }
}

/// The rows of a conversation.
struct ChatTranscript: View {
    let items: [ChatItem]
    var onShowTerminal: (@MainActor () -> Void)? = nil
    var retry: @MainActor (OutgoingPrompt) -> Void = { _ in }
    @State private var expanded: Set<String> = []

    var body: some View {
        ForEach(items) { item in
            switch item {
            case .user(_, let text, let time):
                UserMessage(text: text, label: "You" + stamp(time))
            case .prompt(let p, let time):
                VStack(alignment: .leading, spacing: 4) {
                    UserMessage(text: p.text, label: "You" + (time != nil ? stamp(time) : p.status == .pending ? " // sending" : ""))
                    if case .failed(let code, let message) = p.status {
                        HStack(spacing: 8) {
                            Text(message).typeRole(.caption).foregroundStyle(Theme.red).lineLimit(2)
                            Spacer()
                            if code == .busy {
                                EndfieldButton("Steer", symbol: Symbol.steer) { retry(p) }
                            } else {
                                EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { retry(p) }
                            }
                        }
                    }
                }
            case .answer(_, let text, let time):
                AnswerMessage(text: text, label: "Hermes" + stamp(time))
            case .tool(let id, let row):
                ToolRowView(
                    tool: row.tool, summary: row.summary, duration: row.duration, output: row.output, exitCode: row.exitCode,
                    isExpanded: Binding(
                        get: { expanded.contains(id) },
                        set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } }))
            case .subagent(_, let name, let toolCount, let duration):
                SubagentRowView(name: name, toolCount: toolCount, duration: duration)
            case .marker(_, let summary):
                RunMarker(
                    commands: summary.commandCount, duration: String(format: "%.1f s", summary.totalDuration),
                    failed: summary.failedCount, action: onShowTerminal)
            case .note(_, let text, let isError):
                Text(text).typeRole(.caption).foregroundStyle(isError ? Theme.red : Theme.secondary)
            }
        }
    }

    private func stamp(_ time: Date?) -> String {
        time.map { " // " + $0.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? ""
    }
}

private struct UserMessage: View {
    let text: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).typeRole(.label).foregroundStyle(Theme.secondary)
            Text(text).typeRole(.body).foregroundStyle(Theme.ink).textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised)
                .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
        }
    }
}

/// The answer as Markdown: prose with inline styles (line breaks and list markers kept as written, since `Text` drops
/// block structure), fenced code as `CodeBlockView`. Parsed once per text: the lazy stack recreates a row each time it
/// scrolls back into view.
private struct AnswerMessage: View {
    let text: String
    let label: String

    private enum Block {
        case prose(AttributedString)
        case code(language: String?, text: String)
    }

    private final class Parsed {
        let blocks: [Block]
        init(_ blocks: [Block]) { self.blocks = blocks }
    }

    private static let parsed: NSCache<NSString, Parsed> = {
        let cache = NSCache<NSString, Parsed>()
        cache.countLimit = 500
        return cache
    }()

    private static func blocks(_ text: String) -> [Block] {
        if let hit = parsed.object(forKey: text as NSString) { return hit.blocks }
        let blocks: [Block] = MarkdownBlocks.parse(text).map {
            switch $0 {
            case .prose(let s):
                .prose((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
            case .code(let language, let code): .code(language: language, text: code)
            }
        }
        parsed.setObject(Parsed(blocks), forKey: text as NSString)
        return blocks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).typeRole(.label).foregroundStyle(Theme.secondary)
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Theme.yellow).frame(width: 3)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .prose(let s):
                            Text(s)
                                .typeRole(.body).foregroundStyle(Theme.ink).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .code(let language, let code):
                            CodeBlockView(language: language, code: code)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview("Chat") {
    // Live events of one run, decoded as the relay sends them.
    let frames = """
        [{"type":"event","session_id":"s","run_id":"r1","seq":1,"ts":1793000000000,"kind":"tool.started","data":{"tool":"terminal","preview":"ls design/"}},
         {"type":"event","session_id":"s","run_id":"r1","seq":2,"ts":1793000000200,"kind":"tool.completed","data":{"tool":"terminal","duration":0.2,"error":false,"preview":"{\\"output\\":\\"controls.png\\\\nscreens.png\\",\\"exit_code\\":0}"}},
         {"type":"event","session_id":"s","run_id":"r1","seq":3,"ts":1793000001000,"kind":"tool.started","data":{"tool":"terminal","preview":"pytest -q"}},
         {"type":"event","session_id":"s","run_id":"r1","seq":4,"ts":1793000005800,"kind":"tool.completed","data":{"tool":"terminal","duration":4.8,"error":false,"preview":"{\\"output\\":\\"1 failed\\",\\"exit_code\\":1}"}},
         {"type":"event","session_id":"s","run_id":"r1","seq":5,"ts":1793000006000,"kind":"answer","data":{"text":"The draft is on the **Screens** page.\\n\\n- Popover only, or a window too\\n- Approval sound\\n\\n```bash\\nscripts/mac-build.sh\\n```"}},
         {"type":"event","session_id":"s","run_id":"r1","seq":6,"ts":1793000006100,"kind":"run.completed","data":{}}]
        """
    var state = SessionState(id: "s")
    for e in (try? JSONDecoder().decode([Event].self, from: Data(frames.utf8))) ?? [] { state.apply(.event(e)) }
    return VStack(spacing: 24) {
        ScrollView { LazyVStack(alignment: .leading, spacing: 10) { ChatTranscript(items: ChatTimeline.items(state, compact: true)) } }
        ScrollView { LazyVStack(alignment: .leading, spacing: 10) { ChatTranscript(items: ChatTimeline.items(state, compact: false)) } }
    }
    .padding().frame(width: 360, height: 720).background(Theme.paper)
}
