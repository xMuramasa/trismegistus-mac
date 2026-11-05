import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// One conversation: approval banner, messages, working indicator, input. `compact` is the popover layout (tool and
/// subagent rows inline); the window passes `compact: false` and gets one chip per run, whose menu reaches this
/// conversation's calls in the Commands section through `onShowCommands`.
struct ChatView: View {
    let sessionID: String
    var compact: Bool = true
    var onShowCommands: ((String) -> Void)? = nil

    @Environment(AppModel.self) private var model
    @State private var draft = ""
    /// Failed prompts already retried or steered (the outbox keeps failed prompts until the history reloads).
    @State private var hidden: Set<String> = []
    @State private var actionError: String?
    /// When this view first saw the current run, for a run with no events yet.
    @State private var runSeen = Date()
    /// The current run's chip is unfolded.
    @State private var workOpen = false
    /// Raised by Steer on an empty field: the field takes the focus.
    @State private var composerFocusRequests = 0
    @State private var handingOff: SessionInfo?
    /// The composer's dragged height (0: auto-grow): kept in the window, per view in the popover.
    @AppStorage("composer.height") private var windowComposerHeight = 0.0
    @State private var popoverComposerHeight = 0.0
    /// The column's height: the composer is dragged up to half of it.
    @State private var columnHeight: CGFloat = 0
    /// Images waiting for the next message, per conversation.
    @State private var tray = ImageTray()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The newest part of the conversation's thread: older parts show folded above, the composer sends here.
    private var id: String { model.store?.threadTip(of: sessionID) ?? sessionID }
    private var state: SessionState? { model.store?.sessions[id] }
    private var info: SessionInfo? { model.sessions.first { $0.id == id } }
    private var run: ActiveRun? { state?.run }
    private var approval: PendingApproval? { state?.approvals.first }

    var body: some View {
        let items = self.items
        // An empty, loaded chat shows the window's background across its width; otherwise the column reads on paper.
        let empty = items.isEmpty && state?.historyLoaded == true && state?.historyError == nil
        VStack(spacing: 0) {
            if let approval { banner(approval) }
            // The composer block lies over the scroll view's bottom, never under it (#52, `DockedScroll`).
            DockedScroll {
                LazyVStack(alignment: .leading, spacing: compact ? Space.m : Space.xl) {
                    OlderParts(tipID: id, compact: compact)
                    historyStatus
                    ChatTranscript(items: items, sessionID: id, events: state?.events ?? [], onShowCommands: showCommands, retry: retry(_:))
                    if let run { working(run) } else if let info, SessionCapabilities(info).canHandOff, Self.stalled(items) { stallRow(info) }
                }
                // The window: Space.m under the header's title rule.
                .padding(.vertical, compact ? Space.l : Space.m)
                // A readable column, the composer's: on a wide window, opening a pane or the sidebar doesn't re-wrap the messages.
                .frame(maxWidth: Size.chatColumn)
                .padding(.horizontal, Space.l)
                .frame(maxWidth: .infinity)
                .environment(\.plainAnswers, !compact)
            } dock: {
                ComposerBlock { runLine } input: { input }
            }
            .background { if !compact && !empty { Ink.surface.window.frame(maxWidth: Size.chatColumn + 2 * Space.l) } }
        }
        .background { if compact { Ink.surface.window } else { EndfieldBackdrop() } }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { columnHeight = $0 }
        .imageDrop(
            room: ImageUpload.maxPerMessage - tray.items[id, default: []].count, limit: ImageUpload.maxPerMessage,
            refusal: model.device?.canManage != true ? .viewer : isReadOnly ? .readOnly : nil, later: run != nil
        ) { tray.add($0, $1, to: id) }
        .background(PasteCatcher { canAttach && tray.paste(to: id) })
        .task(id: id) {
            await model.store?.images?.forgetFailures() // a reopened conversation asks again for images that failed
            await model.store?.open(id)
        }
        .onChange(of: run?.id, initial: true) {
            runSeen = Date()
            workOpen = false
        }
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
        HStack(spacing: Space.s) {
            Text("The model stopped answering. Continue in a new conversation from a digest of this one.")
                .typeRole(.caption).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            EndfieldButton("Hand off", symbol: Symbol.handoff, kind: .primary) { handingOff = info }
        }
        .padding(Space.m)
        .background(Ink.surface.sunken)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
    }

    private var items: [ChatItem] {
        guard let state else { return [] }
        return ChatTimeline.items(state, compact: compact).filter {
            switch $0 {
            case .prompt(let p, _): !hidden.contains(p.id)
            case .marker(let id, _): id != run.map { "m-\($0.id)" } // the work line carries the live run's chip
            default: true
            }
        }
    }

    private var showCommands: (@MainActor () -> Void)? {
        guard let onShowCommands else { return nil }
        return { onShowCommands(id) }
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
        .padding([.horizontal, .top], Space.l)
        .background(Ink.surface.window)
        .zIndex(1)
    }

    @ViewBuilder private var historyStatus: some View {
        if let error = state?.historyError {
            HStack(spacing: Space.s) {
                Text(error).typeRole(.caption).foregroundStyle(Ink.text.error)
                EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) {
                    Task { await model.store?.loadHistory(id) }
                }
            }
        } else if let state, !state.historyLoaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity)
        }
    }

    private func runStart(_ run: ActiveRun) -> Date {
        let first = state?.events.first { $0.runID == run.id }
        return first.map { Date(timeIntervalSince1970: Double($0.ts) / 1000) } ?? runSeen
    }

    private static func elapsed(from start: Date, to now: Date) -> String {
        Duration.seconds(max(0, Int(now.timeIntervalSince(start)))).formatted(.time(pattern: .minuteSecond(padMinuteToLength: 2)))
    }

    /// The work line with the window's chip and cards; the popover shows the tool rows inline.
    private func working(_ run: ActiveRun) -> some View {
        let start = runStart(run)
        let tools = state.map { ChatTimeline.toolCount($0, runID: run.id) } ?? 0
        let entries = compact ? [] : TerminalTranscript.entries(from: state?.events.filter { $0.runID == run.id } ?? [])
        let summary = TerminalTranscript.summary(of: entries)
        return VStack(alignment: .leading, spacing: Space.s) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                WorkLine(detail: "\(Self.elapsed(from: start, to: context.date)) · " + (run.status == .waitingForApproval ? "approval" : "\(tools) \(tools == 1 ? "tool" : "tools")")) {
                    if summary.commandCount > 0 { RunChip(summary: summary, isOpen: $workOpen, showCommands: showCommands) }
                }
            }
            if workOpen { RunCards(entries: entries) }
        }
    }

    /// Over the input: the run's state and clock, the keys in the window.
    @ViewBuilder private var runLine: some View {
        if let run {
            let start = model.store?.overview[id]?.run?.startedAt ?? runStart(run)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                RunLine("Run active", isActive: true, clock: Self.elapsed(from: start, to: context.date), hints: hints)
            }
        } else {
            RunLine(isReadOnly ? "Read-only" : "Ready", hints: hints)
        }
    }

    private var input: some View {
        let steering = run != nil
        let empty = Composer.message(draft).isEmpty
        let images = tray.items[id, default: []]
        // Never while an image is still being prepared. Steer stays pressable with no text: it then focuses the field.
        let blocked = isReadOnly || tray.isPreparing(id) || Composer.isOverLimit(draft)
        return VStack(alignment: .leading, spacing: Space.s) {
            if !images.isEmpty {
                AttachmentTray(
                    items: images.map { AttachmentTray.Item(id: $0.id, image: $0.thumbnail, error: $0.error) },
                    note: steering ? "Steers are text only: the images go with the next new message." : nil
                ) { tray.remove($0, from: id) }
                .transition(AttachmentTray.insertion(reduceMotion))
            }
            if let notice = tray.notice {
                Text(notice).typeRole(.caption).foregroundStyle(Ink.text.error).lineLimit(1)
            }
            HStack(alignment: .bottom, spacing: Space.s) {
                if canAttach {
                    EndfieldButton("Attach images", symbol: Symbol.attach, kind: .quiet, iconOnly: true) { tray.choose(for: id) }
                }
                Composer(
                    approval != nil ? "Steer or wait" : steering ? "Steer this run" : "Message Hermes", text: $draft,
                    maxLines: compact ? Size.composer.popoverLines : Size.composer.windowLines,
                    chosenHeight: compact ? $popoverComposerHeight : $windowComposerHeight, maxHeight: columnHeight / 2,
                    focusRequests: composerFocusRequests)
                .disabled(isReadOnly)
                if let run {
                    // Not `blocked`: a read-only conversation's run can still be stopped.
                    EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger, iconOnly: true, shortcut: KeyboardShortcut(".", modifiers: .command)) {
                        act { try await model.stop(runID: run.id) }
                    }
                    // While an approval is open, Once is the primary action.
                    EndfieldButton("Steer", symbol: Symbol.steer, kind: approval == nil ? .primary : .secondary, shortcut: KeyboardShortcut(.return, modifiers: .command)) {
                        submit()
                    }
                    .disabled(blocked)
                } else {
                    // Text or images.
                    EndfieldButton("Send", symbol: Symbol.send, kind: .primary, iconOnly: true, shortcut: KeyboardShortcut(.return, modifiers: .command)) {
                        submit()
                    }
                    .disabled(blocked || (empty && tray.uploads(id).isEmpty))
                }
            }
            if isReadOnly {
                Text(verbatim: "Read-only: this conversation comes from \(info?.source ?? (id.hasPrefix("cron_") ? "cron" : "another app")); reply there.")
                    .typeRole(.caption).foregroundStyle(Ink.text.secondary).lineLimit(1)
            }
            if let actionError {
                Text(actionError).typeRole(.caption).foregroundStyle(Ink.text.error).lineLimit(1)
            }
        }
        .animation(Motion.dropIn, value: images.map(\.id))
    }

    private var isReadOnly: Bool { SessionInfo.isReadOnly(id: id, info: info) }

    /// Images go only from a manager device (the relay refuses a viewer's upload) into a writable conversation.
    private var canAttach: Bool { !isReadOnly && model.device?.canManage == true }

    /// The window's keys (the popover's chat page has its own strip). ⌘K is the window's "Conversations" command.
    private var hints: [(key: String, action: String)] {
        guard !compact else { return [] }
        var hints: [(key: String, action: String)] = []
        if !isReadOnly { hints.append(("⌘↩", run == nil ? "send" : "steer")) }
        if run != nil { hints.append(("⌘.", "stop")) }
        return hints + [("⌘⌥T", "terminal"), ("⌘K", "conversations")]
    }

    /// `⌘↩`: a prompt with the tray's images, or a steer while a run is active (the relay answers a prompt during a run
    /// with `busy`); a steer leaves the images for the next prompt.
    private func submit() {
        let text = Composer.message(draft)
        if let run {
            guard !text.isEmpty else {
                composerFocusRequests += 1
                return
            }
            draft = ""
            act {
                do {
                    try await model.steer(runID: run.id, text: text, in: id)
                } catch {
                    if draft.isEmpty { draft = text }
                    throw error
                }
            }
        } else {
            guard !tray.isPreparing(id), !text.isEmpty || !tray.uploads(id).isEmpty else { return }
            draft = ""
            let images = tray.take(id)
            Task { await model.send(text, images: images, to: id) }
        }
    }

    /// A failed prompt again: as a steer when the relay said busy, the run is still going and it has no images (steers
    /// are text only), else as a prompt in its place.
    private func retry(_ prompt: OutgoingPrompt) {
        if case .failed(.busy, _) = prompt.status, let run, prompt.images.isEmpty {
            hidden.insert(prompt.id)
            act { try await model.steer(runID: run.id, text: prompt.text, in: id) }
        } else {
            Task { await model.store?.retryPrompt(prompt.id, in: id) }
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
extension EnvironmentValues {
    /// The window's chat (older parts included): answers as plain text, no yellow bar (#32).
    @Entry var plainAnswers = false
}

struct ChatTranscript: View {
    let items: [ChatItem]
    /// Whose messages: Hermes' media files are fetched per session.
    let sessionID: String
    /// The live events: a run's cards unfold from them.
    var events: [Event] = []
    var onShowCommands: (@MainActor () -> Void)? = nil
    var retry: @MainActor (OutgoingPrompt) -> Void = { _ in }
    @State private var expanded: Set<String> = []

    var body: some View {
        ForEach(items) { item in
            switch item {
            case .user(_, let text, let time, let images, let steer):
                UserMessage(
                    text: text, label: (steer ? "You // steer" : "You") + stamp(time), sessionID: sessionID,
                    images: images.map(MessageImage.chat))
            case .prompt(let p, let time):
                VStack(alignment: .leading, spacing: Space.xs) {
                    UserMessage(
                        text: p.text,
                        label: (p.isSteer ? "You // steer" : "You") + (time != nil ? stamp(time) : p.status == .pending ? " // sending" : ""),
                        sessionID: sessionID, images: p.images.map(MessageImage.upload))
                    if case .failed(let code, let message) = p.status {
                        HStack(spacing: Space.s) {
                            Text(message).typeRole(.caption).foregroundStyle(Ink.text.error).lineLimit(2)
                            Spacer()
                            if code == .busy, p.images.isEmpty {
                                EndfieldButton("Steer", symbol: Symbol.steer) { retry(p) }
                            } else {
                                EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { retry(p) }
                            }
                        }
                    }
                }
            case .answer(_, let text, let time):
                AnswerMessage(text: text, label: "Hermes" + stamp(time), sessionID: sessionID)
            case .tool(let id, let row):
                ToolRowView(
                    tool: row.tool, summary: row.summary, duration: row.duration, output: row.output, exitCode: row.exitCode,
                    isExpanded: isExpanded(id))
            case .subagent(_, let name, let toolCount, let duration):
                SubagentRowView(name: name, toolCount: toolCount, duration: duration)
            case .marker(let id, let summary):
                VStack(alignment: .leading, spacing: Space.s) {
                    RunChip(summary: summary, isOpen: isExpanded(id), showCommands: onShowCommands)
                    if expanded.contains(id) {
                        RunCards(entries: TerminalTranscript.entries(from: events).filter { "m-\($0.runID)" == id })
                    }
                }
            case .note(_, let text, let isError):
                Text(text).typeRole(.caption).foregroundStyle(isError ? Ink.text.error : Ink.text.secondary)
            }
        }
    }

    private func isExpanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { if $0 { expanded.insert(id) } else { expanded.remove(id) } })
    }

    private func stamp(_ time: Date?) -> String {
        time.map { " // " + $0.formatted(.clock.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) } ?? ""
    }
}

/// The chip of a run's commands; its context menu reaches the Commands section.
private struct RunChip: View {
    let summary: RunSummary
    @Binding var isOpen: Bool
    let showCommands: (@MainActor () -> Void)?

    var body: some View {
        CommandChip(
            commands: summary.commandCount, duration: String(format: "%.1f s", summary.totalDuration), failed: summary.failedCount,
            isOpen: $isOpen
        )
        .contextMenu {
            if let showCommands { Button("Show in Commands") { showCommands() } }
        }
    }
}

/// A run's item cards, unfolded in place under its chip.
private struct RunCards: View {
    let entries: [TerminalEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxl) {
            ForEach(entries) { EntryRow(entry: $0) }
        }
        .padding(.top, Space.s).padding(.bottom, Space.xs)
    }
}

/// One call as an item card, here and in the Commands log.
struct EntryRow: View {
    let entry: TerminalEntry
    var oneLine = false
    /// Some entry in the same list is from an earlier day: every time column takes the dated width.
    var dated = false

    /// The list holds a call from an earlier day, whose time carries the day.
    static func dated(_ entries: [TerminalEntry]) -> Bool {
        entries.contains { !Calendar.current.isDateInToday(Date(timeIntervalSince1970: Double($0.time) / 1000)) }
    }

    var body: some View {
        TerminalEntryView(
            time: Self.time(entry.time), tool: entry.tool, detail: entry.cwd,
            command: entry.command ?? "…", output: output, exitCode: entry.exitCode, failed: entry.failed,
            isRunning: entry.isRunning, startedAt: Date(timeIntervalSince1970: Double(entry.time) / 1000),
            duration: entry.duration, oneLine: oneLine, timeWidth: dated ? Size.toolRow.timeDated : nil)
    }

    /// The running entry says why it has no output yet, as in the draft.
    private var output: String? {
        if entry.isRunning { return "output arrives when it finishes" }
        if entry.awaitsResult { return "no result in the history yet" }
        var lines: [String] = []
        // Only the terminal tool reports an exit code; other tools show their failure here.
        if entry.isError, entry.exitCode == nil { lines.append("✘ the tool reported an error") }
        if let text = entry.output, !text.isEmpty { lines.append(text) }
        if let text = entry.errorText, !text.isEmpty { lines.append(text) }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// `14:02:11`, with the day before it when it isn't today (history reaches back days).
    private static func time(_ ms: Int) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let clock = date.formatted(.clock.hour(.twoDigits(amPM: .omitted)).minute().second())
        return Calendar.current.isDateInToday(date) ? clock : date.formatted(.clock.day().month(.abbreviated)) + " " + clock
    }
}

private struct UserMessage: View {
    let text: String
    let label: String
    let sessionID: String
    let images: [MessageImage]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeRole(.label).foregroundStyle(Ink.text.secondary)
            if !images.isEmpty { MessageImages(sessionID: sessionID, images: images) }
            if !text.isEmpty || images.isEmpty {
                Text(text).typeRole(.body).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.surface.raised)
                    .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
            }
        }
    }
}

extension MarkdownPart where Extra == MarkdownBlock {
    /// `markdown` for `MarkdownView`: tables and images stay blocks for the caller to draw. `clean` runs over the text
    /// first (GitHub text drops its HTML).
    static func parse(_ markdown: String, clean: (String) -> String = { $0 }) -> [MarkdownPart<MarkdownBlock>] {
        func styled(_ text: String) -> AttributedString { MarkdownText.styled(clean(text)) }
        func converted(_ item: MarkdownListItem) -> MarkdownItem {
            let marker: MarkdownItem.Marker = switch item.marker {
            case .bullet: .bullet
            case .number(let n): .number(n)
            case .task(let done): .task(done: done)
            }
            return MarkdownItem(marker, text: styled(item.text), children: item.children.map(converted))
        }
        return MarkdownBlocks.document(markdown).map {
            switch $0 {
            case .block(.prose(let text)): .prose(styled(text))
            case .block(.code(let language, let text)): .code(language: language, text: text)
            case .block(let block): .extra(block)
            case .heading(_, let text): .heading(styled(text))
            case .list(let items): .list(items.map(converted))
            }
        }
    }
}

/// The answer as Markdown: `MarkdownView`, with Hermes' `MEDIA:` files as images. Parsed once per text: the lazy stack
/// recreates a row each time it scrolls back into view.
private struct AnswerMessage: View {
    let text: String
    let label: String
    let sessionID: String
    /// Plain (the window): the text inset Space.m, level with a user message's text. Else a yellow bar beside it.
    @Environment(\.plainAnswers) private var plain

    private final class Parsed {
        let parts: [MarkdownPart<MarkdownBlock>]
        init(_ parts: [MarkdownPart<MarkdownBlock>]) { self.parts = parts }
    }

    private static let parsed: NSCache<NSString, Parsed> = {
        let cache = NSCache<NSString, Parsed>()
        cache.countLimit = 500
        return cache
    }()

    private static func parts(_ text: String) -> [MarkdownPart<MarkdownBlock>] {
        if let hit = parsed.object(forKey: text as NSString) { return hit.parts }
        let parts = MarkdownPart.parse(text)
        parsed.setObject(Parsed(parts), forKey: text as NSString)
        return parts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeRole(.label).foregroundStyle(Ink.text.secondary)
            HStack(alignment: .top, spacing: Space.m) {
                if !plain { Rectangle().fill(Ink.selection).frame(width: Stroke.mark) }
                MarkdownView(Self.parts(text)) { block in
                    switch block {
                    case .table(let header, let rows, let alignments):
                        MarkdownTableView(header: header, rows: rows, alignments: alignments)
                    case .image(let path):
                        MessageImages(sessionID: sessionID, images: [.chat(.media(path: path))])
                    case .prose, .code:
                        EmptyView() // `parse` makes parts of these
                    }
                }
            }
            .padding(.horizontal, plain ? Space.m : 0)
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
        ScrollView { LazyVStack(alignment: .leading, spacing: 10) { ChatTranscript(items: ChatTimeline.items(state, compact: true), sessionID: "s") } }
        ScrollView { LazyVStack(alignment: .leading, spacing: 10) { ChatTranscript(items: ChatTimeline.items(state, compact: false), sessionID: "s") } }
    }
    .padding().frame(width: 360, height: 720).background(Ink.surface.window)
}
