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
    /// The message open in the editor (#75), with the text and images being edited.
    @State private var editing: ChatTimeline.Rewindable?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The newest part of the conversation's thread: older parts show folded above, the composer sends here.
    private var id: String { model.store?.threadTip(of: sessionID) ?? sessionID }
    private var state: SessionState? { model.store?.sessions[id] }
    private var info: SessionInfo? { model.sessions.first { $0.id == id } }
    private var run: ActiveRun? { state?.run }
    private var approval: PendingApproval? { state?.approvals.first }

    var body: some View {
        let items = self.items
        VStack(spacing: 0) {
            if let approval { banner(approval) }
            // The composer block lies over the scroll view's bottom, never under it (#52, `DockedScroll`).
            DockedScroll {
                LazyVStack(alignment: .leading, spacing: compact ? Space.m : Space.xl) {
                    OlderParts(tipID: id, compact: compact)
                    historyStatus
                    ChatTranscript(
                        items: items, sessionID: id, events: state?.events ?? [], onShowCommands: showCommands, retry: retry(_:),
                        editing: $editing, resend: canRewind ? resend(_:) : nil)
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
                ComposerBlock(floating: !compact) { runLine } input: { input }
            }
        }
        // The window's chat in the a3 skin (#71): the transcript and the composer straight on the backdrop.
        .environment(\.hairlineControls, !compact)
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
        .onChange(of: id) { editing = nil }
        // A retry or edit the relay refused: the turns are back, and so is the editor with the text sent.
        .onChange(of: state?.outbox.filter { $0.rewindTo != nil && $0.isFailed } ?? []) { _, failed in
            for p in failed where hidden.insert(p.id).inserted {
                editing = ChatTimeline.Rewindable(failed: p)
                if case .failed(_, let message) = p.status { actionError = message }
            }
        }
        // The message is gone (the relay rewound before the run failed to start): the text goes to the composer, so
        // the next send is a plain prompt.
        .onChange(of: items.map(\.id)) { _, ids in
            guard let editing, !ids.contains(editing.itemID), state?.historyStale == false else { return }
            draft = draft.isEmpty ? editing.text : draft + "\n\n" + editing.text // never drop what's typed
            self.editing = nil
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
        .background(compact ? Ink.surface.window : .clear)
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
        // The latest thought Hermes stored (#74), one line truncated at its tail.
        let thought = state?.thought.map { " · thinking: “\($0)”" } ?? ""
        return VStack(alignment: .leading, spacing: Space.s) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                WorkLine(detail: "\(Self.elapsed(from: start, to: context.date)) · " + (run.status == .waitingForApproval ? "approval" : "\(tools) \(tools == 1 ? "tool" : "tools")") + thought) {
                    if summary.commandCount > 0 { RunChip(summary: summary, isOpen: $workOpen, showCommands: showCommands) }
                }
                .lineLimit(1)
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
                    // Text or images. While a message is being edited, its editor's Send is the yellow one and takes ⌘↩.
                    EndfieldButton(
                        "Send", symbol: Symbol.send, kind: editing == nil ? .primary : .secondary, iconOnly: true,
                        shortcut: editing == nil ? KeyboardShortcut(.return, modifiers: .command) : nil
                    ) {
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

    /// Retry and edit (#75): not during a run (steer or stop it), in a read-only conversation, or while a prompt of yours
    /// is on its way.
    private var canRewind: Bool {
        !isReadOnly && run == nil && state?.outbox.contains { !$0.isSteer && !$0.isFailed } == false
    }

    /// `message` again in place of itself and everything after it.
    private func resend(_ message: ChatTimeline.Rewindable) {
        let text = Composer.message(message.text)
        guard !text.isEmpty || !message.attachments.isEmpty else { return }
        editing = nil
        actionError = nil
        Task { await model.store?.sendPrompt(text, images: message.uploads, to: id, rewindTo: message.hermesID) }
    }

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
    /// The message open in the editor (#75); the rows after it are dimmed.
    var editing: Binding<ChatTimeline.Rewindable?> = .constant(nil)
    /// Sends a message again in place of itself and what follows (retry, edit); nil where neither is offered.
    var resend: (@MainActor (ChatTimeline.Rewindable) -> Void)? = nil
    @State private var expanded: Set<String> = []
    /// The row under the pointer: its actions show.
    @State private var hovered: String?
    /// How far a 24 pt action button hangs above its 10 pt label line; less than the window's 20 pt gap between rows,
    /// so a row's hover ground never reaches the row above.
    static let actionReach = Size.messageAction.button - Space.m

    var body: some View {
        let cut = editing.wrappedValue.flatMap { e in items.firstIndex { $0.id == e.itemID } }
        // Retry and edit wait while the editor is open.
        let offer = editing.wrappedValue == nil ? resend : nil
        let last = offer == nil ? nil : ChatTimeline.retry(items)
        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
            row(item, offer: offer, last: last)
                .rewound(cut.map { i > $0 } ?? false)
                // The whole row is hover ground, not just its text and boxes: an empty stretch (the label line right of
                // its words) used to count as outside, so the pencil hid on the way to it and flickered. The ground
                // also reaches up over the actions, which hang above the label line into the gap between rows
                // (Martin's recording, 2026-11-11).
                .padding(.top, Self.actionReach)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
                }
                .padding(.top, -Self.actionReach)
        }
    }

    /// `offer` sends a message again (nil: not offered); `last` is what Retry sends and the answer it replaces.
    @ViewBuilder
    private func row(
        _ item: ChatItem, offer: (@MainActor (ChatTimeline.Rewindable) -> Void)?,
        last: (message: ChatTimeline.Rewindable, answerID: String?)?
    ) -> some View {
        switch item {
        case .user(let itemID, let text, let time, let images, let steer):
            let label = (steer ? "You // steer" : "You") + stamp(time)
            if let open = editing.wrappedValue, open.itemID == itemID {
                VStack(alignment: .leading, spacing: Space.xs) {
                    MessageLabel(label)
                    EditingMessage(
                        message: Binding(get: { editing.wrappedValue ?? open }, set: { editing.wrappedValue = $0 }),
                        removed: ChatTimeline.removed(after: itemID, in: items),
                        onCancel: { editing.wrappedValue = nil }, onSend: { resend?(editing.wrappedValue ?? open) })
                }
            } else {
                let target = offer == nil ? nil : ChatTimeline.rewindable(item)
                UserMessage(text: text, label: label, sessionID: sessionID, images: images.map(MessageImage.chat), hovered: hovered == itemID) {
                    if let target {
                        MessageActionButton("Edit and send again", symbol: Symbol.edit) { editing.wrappedValue = target }
                        // The run left no answer: Retry sits here.
                        if let offer, let last, last.message.itemID == itemID, last.answerID == nil {
                            MessageActionButton("Retry", symbol: Symbol.retry) { offer(target) }
                        }
                    }
                }
            }
        case .prompt(let p, let time):
            VStack(alignment: .leading, spacing: Space.xs) {
                UserMessage(
                    text: p.text,
                    label: (p.isSteer ? "You // steer" : "You") + (time != nil ? stamp(time) : p.status == .pending ? " // sending" : ""),
                    sessionID: sessionID, images: p.images.map(Self.image))
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
        case .answer(let itemID, let text, let time):
            // Copy and Retry only on the last answer, which Retry replaces.
            let again: (@MainActor () -> Void)? = if let offer, let last, last.answerID == itemID { { offer(last.message) } } else { nil }
            AnswerMessage(text: text, label: "Hermes" + stamp(time), sessionID: sessionID, hovered: hovered == itemID, onRetry: again)
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
        case .note(_, let text, true):
            // A failed run (the timeline's only error note): the row's `FAILED` says "Run failed".
            let reason = text.hasPrefix("Run failed: ") ? String(text.dropFirst("Run failed: ".count)) : text == "Run failed" ? "" : text
            if let offer, let last {
                FailureRow(reason) { offer(last.message) }
            } else {
                FailureRow(reason)
            }
        case .note(_, let text, false):
            Text(text).typeRole(.caption).foregroundStyle(Ink.text.secondary)
        case .thinking(let id, let steps, let commands):
            // A finished turn's chip row under its answer: THINKING (#74), then the commands chip with the turn's calls
            // from the history (design 16a); each fold holds while the conversation stays open.
            let summary = TerminalTranscript.summary(of: commands)
            VStack(alignment: .leading, spacing: Space.s) {
                if steps.isEmpty {
                    RunChip(summary: summary, isOpen: isExpanded(id + "-c"), showCommands: onShowCommands)
                } else {
                    ThinkingBlock(
                        steps: steps.map { ThinkingPanel.Step(thought: $0.thought, tool: $0.tool, detail: $0.detail) }, isOpen: isExpanded(id)
                    ) {
                        if summary.commandCount > 0 { RunChip(summary: summary, isOpen: isExpanded(id + "-c"), showCommands: onShowCommands) }
                    }
                }
                if expanded.contains(id + "-c") { RunCards(entries: commands) }
            }
        }
    }

    /// An outbox image: its bytes, or a history image sent again by id (retry, edit), which has none.
    private static func image(_ upload: ImageUpload) -> MessageImage {
        guard upload.data.isEmpty, let id = upload.attachmentID else { return .upload(upload) }
        return .chat(.attachment(AttachmentRef(id: id, mime: upload.mime, width: upload.width, height: upload.height)))
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

/// `actions` (#75) show at the end of the label line while the pointer is over the message (`hovered`).
private struct UserMessage<Actions: View>: View {
    let text: String
    let label: String
    let sessionID: String
    let images: [MessageImage]
    var hovered = false
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            MessageLabelLine(label, showsActions: hovered) { actions }
            if !images.isEmpty { MessageImages(sessionID: sessionID, images: images) }
            if !text.isEmpty || images.isEmpty { UserMessageText(text) }
        }
    }
}

extension UserMessage where Actions == EmptyView {
    init(text: String, label: String, sessionID: String, images: [MessageImage]) {
        self.init(text: text, label: label, sessionID: sessionID, images: images) { EmptyView() }
    }
}

/// Your message as an editor in its place (#75), its images as chips with thumbnails from the cache. History images have
/// no file name: they are "Image" (numbered when there are several).
private struct EditingMessage: View {
    @Binding var message: ChatTimeline.Rewindable
    let removed: (messages: Int, answer: Bool)
    let onCancel: @MainActor () -> Void
    let onSend: @MainActor () -> Void
    @Environment(AppModel.self) private var model
    @State private var thumbnails: [String: NSImage] = [:]

    var body: some View {
        let refs = message.attachments
        MessageEditor(
            text: $message.text,
            chips: refs.enumerated().map { i, ref in
                MessageEditor.Chip(id: ref.id, name: refs.count == 1 ? "Image" : "Image \(i + 1)", thumbnail: thumbnails[ref.id])
            },
            laterMessages: removed.messages, removesAnswer: removed.answer,
            onRemove: { id in message.attachments.removeAll { $0.id == id } }, onCancel: onCancel, onSend: onSend)
        .task(id: refs) {
            for ref in refs where thumbnails[ref.id] == nil {
                if let url = await model.store?.images?.attachment(ref) { thumbnails[ref.id] = NSImage(contentsOf: url) }
            }
        }
    }
}

extension MarkdownPart where Extra == MarkdownBlock {
    /// `markdown` for `MarkdownView`: tables and images stay blocks for the caller to draw. `clean` runs over the text
    /// first (GitHub text drops its HTML); `role` is the view's (bold and inline code take its size).
    static func parse(_ markdown: String, role: TypeRole = .body, clean: (String) -> String = { $0 }) -> [MarkdownPart<MarkdownBlock>] {
        func styled(_ text: String) -> AttributedString { MarkdownText.styled(clean(text), role: role) }
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
    /// The pointer is over it: with `onRetry` (#75, the last answer) Copy and Retry show on its label line.
    var hovered = false
    var onRetry: (@MainActor () -> Void)? = nil
    /// Plain (the window): the text inset Space.m, level with a user message's text. Else a yellow bar beside it.
    @Environment(\.plainAnswers) private var plain
    /// The window's a3 chat (#71): 14 pt.
    @Environment(\.hairlineControls) private var hairline

    private final class Parsed {
        let parts: [MarkdownPart<MarkdownBlock>]
        init(_ parts: [MarkdownPart<MarkdownBlock>]) { self.parts = parts }
    }

    private static let parsed: NSCache<NSString, Parsed> = {
        let cache = NSCache<NSString, Parsed>()
        cache.countLimit = 500
        return cache
    }()

    /// Per role too: the popover and the window can show the same answer.
    private static func parts(_ text: String, role: TypeRole) -> [MarkdownPart<MarkdownBlock>] {
        let key = "\(role)\n\(text)" as NSString
        if let hit = parsed.object(forKey: key) { return hit.parts }
        let parts = MarkdownPart.parse(text, role: role)
        parsed.setObject(Parsed(parts), forKey: key)
        return parts
    }

    var body: some View {
        let role: TypeRole = hairline ? .message : .body
        VStack(alignment: .leading, spacing: Space.xs) {
            MessageLabelLine(label, showsActions: hovered) {
                if let onRetry {
                    MessageActionButton("Copy answer", symbol: Symbol.copy) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string) // the answer's Markdown as it came
                    }
                    MessageActionButton("Retry", symbol: Symbol.retry, action: onRetry)
                }
            }
            HStack(alignment: .top, spacing: Space.m) {
                if !plain { Rectangle().fill(Ink.selection).frame(width: Stroke.mark) }
                MarkdownView(Self.parts(text, role: role), role: role) { block in
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
