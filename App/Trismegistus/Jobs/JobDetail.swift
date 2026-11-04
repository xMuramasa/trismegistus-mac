import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// One job, or the create form (`job` nil). A manager edits what the relay lets the app write (name, schedule,
/// prompt, delivery, skills, repeat) and pauses, resumes, runs or deletes it; a viewer reads the same values. Model,
/// provider, toolsets, script, workdir and the rest are Hermes' and only shown. Then the job's runs, newest first.
struct JobDetail: View {
    let job: Job?
    let board: JobBoard
    let onOpen: (String) -> Void
    let onCreated: (String) -> Void

    @State private var draft: JobDraft
    @State private var busy = false
    /// The relay's or Hermes' refusal of the last write.
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var runs: [JobRun]?
    @State private var runsFailed = false

    init(job: Job?, board: JobBoard, onOpen: @escaping (String) -> Void, onCreated: @escaping (String) -> Void) {
        self.job = job
        self.board = board
        self.onOpen = onOpen
        self.onCreated = onCreated
        _draft = State(initialValue: job.map(JobDraft.init(job:)) ?? JobDraft())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader {
                Text(verbatim: job?.title ?? "New job")
            } subtitle: {
                EmptyView()
            } trailing: {
                EmptyView()
            }
            VStack(alignment: .leading, spacing: Space.xl) {
                if let job { status(job) }
                if board.canManage {
                    form
                    buttons
                } else if let job {
                    summary(job)
                }
                if let job {
                    hermesValues(job)
                    runList(job)
                }
            }
            .padding(Space.l)
            .frame(maxWidth: Size.chatColumn, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Delete job?", isPresented: $confirmingDelete, presenting: job) { job in
            Button("Delete", role: .destructive) { write { try await board.delete(job) } }
            Button("Cancel", role: .cancel) {}
        } message: { job in
            Text(verbatim: "“\(job.title)” is deleted from Hermes and won't run again. Its past runs stay in the conversation list.")
        }
    }

    // MARK: Status

    private func status(_ job: Job) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(statusLine(job, now: context.date)).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                if job.lastRunFailed {
                    Text(verbatim: "Last run failed: \(job.lastErrorLine ?? "no error line")").typeRole(.monoSmall)
                        .foregroundStyle(Ink.text.error).textSelection(.enabled)
                }
            }
        }
    }

    private func statusLine(_ job: Job, now: Date) -> String {
        var parts = [job.isPaused ? "paused" + (job.pausedReason.map { ": \($0)" } ?? "") : job.state ?? "scheduled"]
        if !job.isPaused, let next = job.nextRun { parts.append("next \(Self.relative(next, now: now))") }
        if let last = job.lastRun { parts.append("last \(job.lastRunFailed ? "failed" : "ok") \(PopoverFormat.ago(last, now: now))") }
        if let r = job.repeat, let times = r.times { parts.append("\(r.completed ?? 0) of \(times) runs") }
        return parts.joined(separator: " · ")
    }

    /// "in 5 hr", "2 min ago".
    static func relative(_ date: Date, now: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    // MARK: Form (manager)

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            field("Name") { EndfieldTextField("Nightly backup", text: $draft.name) }
            field("Schedule") { schedule }
            field("Prompt") {
                TextEditor(text: $draft.prompt)
                    .typeRole(.mono)
                    .foregroundStyle(Ink.text.primary)
                    .scrollContentBackground(.hidden)
                    .padding(Space.s)
                    .frame(minHeight: Size.row * 3)
                    .background(Ink.surface.raised)
                    .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
                    .accessibilityLabel("Prompt")
            }
            field("Deliver to") {
                HStack(spacing: Space.s) {
                    ForEach(["local", "telegram"], id: \.self) { target in
                        FilterChip(title: target, symbol: target == "local" ? "tray" : Symbol.telegram, isOn: draft.deliver == target) {
                            draft.deliver = target
                        }
                    }
                    EndfieldTextField("or another target", text: $draft.deliver)
                }
            }
            field("Skills") { EndfieldTextField("none (comma-separated)", text: $draft.skills) }
            field("Repeat") {
                EndfieldTextField("forever (or a number of runs)", text: $draft.repeatTimes).frame(maxWidth: Size.pickerMax)
            }
            if job == nil {
                Toggle("Start paused", isOn: $draft.paused).endfieldSwitch().typeRole(.body)
            }
        }
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeRole(.label).foregroundStyle(Ink.text.secondary)
            content()
        }
    }

    /// Presets that write a cron expression, the free field, and what the schedule means next.
    private var schedule: some View {
        let preset = SchedulePreset(expression: draft.schedule)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Menu(preset.map { $0.kind.rawValue.capitalized } ?? "Custom") {
                    ForEach(SchedulePreset.Kind.allCases, id: \.self) { kind in
                        Button(kind.rawValue.capitalized) {
                            var p = preset ?? SchedulePreset(.daily)
                            p.kind = kind
                            draft.schedule = p.expression
                        }
                    }
                }
                .menuStyle(.button)
                .fixedSize()
                .accessibilityLabel("Schedule preset")
                if let preset { presetControls(preset) }
            }
            EndfieldTextField("0 3 * * *, every 2h, 30m or an ISO time", text: $draft.schedule)
            preview
        }
    }

    @ViewBuilder private func presetControls(_ preset: SchedulePreset) -> some View {
        let set: (SchedulePreset) -> Void = { draft.schedule = $0.expression }
        if preset.kind == .weekly {
            Picker("Day", selection: Binding(get: { preset.weekday }, set: { var p = preset; p.weekday = $0; set(p) })) {
                ForEach(0..<7, id: \.self) { Text(SchedulePreset.weekdayNames[$0]).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        }
        if preset.kind == .hourly {
            Picker("Minute", selection: Binding(get: { preset.minute }, set: { var p = preset; p.minute = $0; set(p) })) {
                ForEach(0..<60, id: \.self) { Text(String(format: "at :%02d", $0)).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
        } else {
            DatePicker("Time", selection: Binding(
                get: { Calendar.current.date(bySettingHour: preset.hour, minute: preset.minute, second: 0, of: .now) ?? .now },
                set: {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                    var p = preset
                    p.hour = c.hour ?? p.hour
                    p.minute = c.minute ?? p.minute
                    set(p)
                }), displayedComponents: .hourAndMinute)
                .labelsHidden()
                .fixedSize()
        }
    }

    /// The next three runs for a cron expression; Hermes' own words and next run for what it reads itself.
    private var preview: some View {
        let text: String
        if let cron = CronExpression(draft.schedule) {
            let runs = cron.next(3, after: .now)
            text = runs.isEmpty ? "never runs" : "next " + runs.map { $0.formatted(.clock.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) }.joined(separator: " · ")
        } else if let job, draft.schedule.trimmingCharacters(in: .whitespaces) == JobDraft(job: job).schedule {
            text = job.scheduleWords + (job.nextRun.map { " · next " + $0.formatted(.clock.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) } ?? "")
        } else {
            text = "Hermes reads this schedule when the job is saved."
        }
        return Text(text).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                if let job {
                    EndfieldButton("Save", symbol: Symbol.check, kind: .primary) {
                        write {
                            try await board.save(draft, to: job)
                            // Hermes' spelling of what was saved, so the form matches it.
                            if let saved = board.jobs.first(where: { $0.id == job.id }) { draft = JobDraft(job: saved) }
                        }
                    }
                    .disabled(busy || draft.problem != nil || draft.updateBody(from: job).isEmpty)
                    Spacer(minLength: Space.s)
                    EndfieldButton(job.isPaused ? "Resume" : "Pause", symbol: job.isPaused ? "play" : "pause") {
                        write { try await board.perform(job.isPaused ? .resume : .pause, on: job) }
                    }
                    .disabled(busy)
                    EndfieldButton("Run now", symbol: "bolt") { write { try await board.perform(.run, on: job) } }
                        .disabled(busy)
                    EndfieldButton("Delete", symbol: "trash", kind: .danger) { confirmingDelete = true }
                        .disabled(busy)
                } else {
                    EndfieldButton("Create", symbol: Symbol.check, kind: .primary) {
                        write { onCreated(try await board.create(draft).id) }
                    }
                    .disabled(busy || draft.problem != nil)
                }
            }
            if let problem = draft.problem, draft != (job.map(JobDraft.init(job:)) ?? JobDraft()) {
                Text(problem).typeRole(.caption).foregroundStyle(Ink.text.secondary)
            }
            ActionError(message: error)
        }
    }

    private func write(_ body: @escaping @MainActor () async throws -> Void) {
        busy = true
        Task {
            do {
                try await body()
                error = nil
            } catch {
                self.error = (error as? RelayAPIError)?.message ?? "Can't reach the relay."
            }
            busy = false
        }
    }

    // MARK: Read-only values

    /// What a viewer sees in place of the form.
    private func summary(_ job: Job) -> some View {
        VStack(alignment: .leading, spacing: Space.l) {
            values([
                ("Schedule", job.scheduleWords), ("Deliver to", job.deliver ?? "local"),
                ("Skills", job.skills.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? "none"),
                ("Repeat", job.repeat?.times.map { "\($0) runs" } ?? "forever"),
            ])
            field("Prompt") {
                Text(job.prompt ?? "").typeRole(.mono).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                    .padding(Space.s).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Ink.surface.raised)
                    .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
            }
        }
    }

    /// Hermes' own settings: the relay never writes them.
    private func hermesValues(_ job: Job) -> some View {
        field("Set in Hermes") {
            values([
                ("Model", job.model ?? "default"), ("Provider", job.provider ?? "default"),
                ("Toolsets", job.enabledToolsets?.joined(separator: ", ") ?? "default"),
                ("Script", job.script ?? "none"), ("Workdir", job.workdir ?? "none"),
                ("Context from", job.contextFrom.flatMap(Self.text) ?? "none"),
                ("On failure", job.failureDeliver ?? "same as delivery"),
            ])
        }
    }

    private func values(_ rows: [(String, String)]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.xs) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label).typeRole(.caption).foregroundStyle(Ink.text.secondary)
                    Text(value).typeRole(.monoSmall).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                }
            }
        }
    }

    private static func text(_ value: JSONValue) -> String? {
        switch value {
        case .null: nil
        case .string(let s): s
        case .array(let items): items.compactMap(text).joined(separator: ", ")
        case .number(let n): String(n)
        case .bool(let b): String(b)
        case .object: "…"
        }
    }

    // MARK: Runs

    private func runList(_ job: Job) -> some View {
        field("Runs // \(runs?.count ?? 0)") {
            VStack(alignment: .leading, spacing: Space.xs) {
                if let runs, !runs.isEmpty {
                    ForEach(runs) { run($0) }
                } else {
                    Text(runsFailed ? "Can't read the runs." : runs == nil ? "Reading the runs…" : "No runs yet.")
                        .typeRole(.caption).foregroundStyle(Ink.text.muted)
                }
            }
        }
        // Again when a run ends (the job's last run changes).
        .task(id: "\(job.id) \(job.lastRunAt ?? "")") {
            do {
                runs = try await board.rest.jobRuns(job.id)
                runsFailed = false
            } catch {
                runsFailed = true
            }
        }
    }

    /// Opens its conversation, read-only like every cron session (by its `cron_` id, listed or not).
    private func run(_ run: JobRun) -> some View {
        let when = run.startedAt.map { Date(timeIntervalSince1970: $0).formatted(.clock.day().month(.abbreviated).hour().minute()) } ?? "—"
        return Button { onOpen(run.id) } label: {
            HStack(spacing: Space.s) {
                Text(when).typeRole(.monoSmall)
                Text(run.title ?? run.id).typeRole(.monoSmall).lineLimit(1)
                Image(systemName: Symbol.chevronRight).font(.system(size: Icon.xs))
            }
            .foregroundStyle(Ink.text.link)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the conversation")
    }
}
