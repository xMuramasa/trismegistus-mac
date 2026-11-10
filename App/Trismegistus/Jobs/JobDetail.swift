import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// One job, or the create form (`job` nil). The readout and the prompt under the pinned header, then the job's runs,
/// newest first, and its settings. A manager pauses, resumes and runs it from the header; Edit swaps the reading for the
/// form with what the relay lets the app write (name, schedule, prompt, delivery, skills, repeat) and Delete. Model,
/// provider, toolsets, script, workdir and the rest are Hermes' and only shown.
struct JobDetail: View {
    let job: Job?
    let board: JobBoard
    let onOpen: (String) -> Void
    let onCreated: (String) -> Void
    var onCancel: () -> Void = {}

    @State private var draft: JobDraft
    @State private var editing: Bool
    @State private var busy = false
    /// The relay's or Hermes' refusal of the last write.
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var runs: [JobRun]?
    @State private var runsFailed = false

    init(job: Job?, board: JobBoard, onOpen: @escaping (String) -> Void, onCreated: @escaping (String) -> Void, onCancel: @escaping () -> Void = {}) {
        self.job = job
        self.board = board
        self.onOpen = onOpen
        self.onCreated = onCreated
        self.onCancel = onCancel
        _draft = State(initialValue: job.map(JobDraft.init(job:)) ?? JobDraft())
        _editing = State(initialValue: job == nil)
    }

    private var isEditing: Bool { editing && board.canManage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeader {
                Text(verbatim: job?.title ?? "New job")
            } subtitle: {
                Text(verbatim: isEditing ? "editing" : job?.subtitle ?? "")
            } trailing: {
                actions
                DetailTools(section: .jobs)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: Space.l) {
                    if isEditing, let problem = draft.problem, draft != (job.map(JobDraft.init(job:)) ?? JobDraft()) {
                        Text(problem).typeRole(.caption).foregroundStyle(Ink.text.secondary)
                    }
                    ActionError(message: error)
                    if isEditing {
                        form
                    } else if let job {
                        readout(job)
                        JobPromptPanel { JobPromptText(text: job.prompt ?? "") }
                        runList(job)
                        settings(job)
                    }
                }
                .padding(Space.l)
                .frame(maxWidth: Size.jobColumn + 2 * Space.l)
                .frame(maxWidth: .infinity)
            }
            .settledWidth()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .alert("Delete job?", isPresented: $confirmingDelete, presenting: job) { job in
            Button("Delete", role: .destructive) { write { try await board.delete(job) } }
            Button("Cancel", role: .cancel) {}
        } message: { job in
            Text(verbatim: "“\(job.title)” is deleted from Hermes and won't run again. Its past runs stay in the conversation list.")
        }
    }

    // MARK: Header

    @ViewBuilder private var actions: some View {
        if isEditing {
            JobEditActions(canSave: canSave, onCancel: cancel, onSave: save)
        } else if let job, board.canManage {
            JobActions(
                isPaused: job.isPaused, isBusy: busy,
                onPause: { write { try await board.perform(job.isPaused ? .resume : .pause, on: job) } },
                onRun: { write { try await board.perform(.run, on: job) } },
                onEdit: {
                    draft = JobDraft(job: job)
                    error = nil
                    editing = true
                })
        }
    }

    private var canSave: Bool {
        guard !busy, draft.problem == nil else { return false }
        return job.map { !draft.updateBody(from: $0).isEmpty } ?? true
    }

    private func cancel() {
        if job == nil { return onCancel() }
        error = nil
        editing = false
    }

    private func save() {
        write {
            if let job {
                try await board.save(draft, to: job)
                editing = false
            } else {
                onCreated(try await board.create(draft).id)
            }
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

    /// "in 5 hr", "2 min ago": the Agents section's; Jobs writes `Job.span`.
    static func relative(_ date: Date, now: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }

    // MARK: Reading

    private func readout(_ job: Job) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            JobReadout(
                cadence: job.cadence, cron: job.cron,
                nextRuns: job.nextRuns().map { Job.clockLine($0) },
                noRuns: job.isPaused ? "paused" + (job.pausedReason.map { ": \($0)" } ?? "") : "none scheduled",
                last: job.lastRun.map {
                    JobReadout.Last(failed: job.lastRunFailed, time: Job.clockLine($0), ago: Job.span(context.date.timeIntervalSince($0)) + " ago",
                                    error: job.lastRunFailed ? job.lastErrorLine ?? "no error line" : nil)
                })
        }
    }

    private func settings(_ job: Job) -> some View {
        JobPanel("Settings") {
            JobValues(rows: [
                ("Deliver to", job.deliver ?? "local"),
                ("Skills", job.skills.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? "none"),
                ("Repeat", job.repeat?.times.map { "\(job.repeat?.completed ?? 0) of \($0) runs" } ?? "forever"),
                ("Model", job.model ?? "default"), ("Provider", job.provider ?? "default"),
                ("Toolsets", job.enabledToolsets?.joined(separator: ", ") ?? "default"),
                ("Script", job.script ?? "none"), ("Workdir", job.workdir ?? "none"),
                ("Context from", job.contextFrom.flatMap(Self.text) ?? "none"),
                ("On failure", job.failureDeliver ?? "same as delivery"),
            ])
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

    // MARK: Form (manager)

    private var form: some View {
        JobForm(
            name: $draft.name, schedule: $draft.schedule, prompt: $draft.prompt, deliver: $draft.deliver, skills: $draft.skills,
            repeatTimes: $draft.repeatTimes, paused: job == nil ? $draft.paused : nil, picker: picker, preview: preview,
            onDelete: job == nil ? nil : { confirmingDelete = true })
            // The time picker: every time is 24-hour, and it would follow a 12-hour system clock.
            .environment(\.locale, Locale.autoupdatingCurrent.onTwentyFourHourClock)
    }

    /// Presets that write a cron expression.
    private var picker: JobSchedulePicker {
        let preset = SchedulePreset(expression: draft.schedule)
        let set: (SchedulePreset) -> Void = { draft.schedule = $0.expression }
        func control(_ value: WritableKeyPath<SchedulePreset, Int>) -> Binding<Int>? {
            preset.map { preset in
                Binding(get: { preset[keyPath: value] }, set: { var p = preset; p[keyPath: value] = $0; set(p) })
            }
        }
        let time = preset.map { preset in
            Binding<Date>(
                get: { Calendar.current.date(bySettingHour: preset.hour, minute: preset.minute, second: 0, of: .now) ?? .now },
                set: {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                    var p = preset
                    p.hour = c.hour ?? p.hour
                    p.minute = c.minute ?? p.minute
                    set(p)
                })
        }
        return JobSchedulePicker(
            kind: preset?.kind.rawValue,
            kinds: SchedulePreset.Kind.allCases.map(\.rawValue),
            choose: { name in
                var p = preset ?? SchedulePreset(.daily)
                p.kind = SchedulePreset.Kind(rawValue: name) ?? p.kind
                set(p)
            },
            weekdays: SchedulePreset.weekdayNames,
            weekday: preset?.kind == .weekly ? control(\.weekday) : nil,
            minute: preset?.kind == .hourly ? control(\.minute) : nil,
            time: preset?.kind == .hourly ? nil : time)
    }

    /// The next three runs for a cron expression; Hermes' own words and next run for what it reads itself.
    private var preview: String {
        if let cron = CronExpression(draft.schedule) {
            let runs = cron.next(3, after: .now)
            return runs.isEmpty ? "never runs" : "next " + runs.map { Job.clockLine($0) }.joined(separator: " · ")
        }
        if let job, draft.schedule.trimmingCharacters(in: .whitespaces) == JobDraft(job: job).schedule {
            return job.scheduleWords + (job.nextRun.map { " · next " + Job.clockLine($0) } ?? "")
        }
        return "Hermes reads this schedule when the job is saved."
    }

    // MARK: Runs

    private func runList(_ job: Job) -> some View {
        JobPanel("Runs // \(runs?.count ?? 0)") {
            if let runs, !runs.isEmpty {
                ForEach(runs) { run($0, of: job, newest: $0.id == runs[0].id) }
            } else {
                Text(runsFailed ? "Can't read the runs." : runs == nil ? "Reading the runs…" : "No runs yet.")
                    .typeRole(.caption).foregroundStyle(Ink.text.muted)
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
    private func run(_ run: JobRun, of job: Job, newest: Bool) -> some View {
        let outcome = newest ? job.outcome(ofNewest: run) : nil
        return JobRunRow(
            time: run.startedAt.map { Job.clockLine(Date(timeIntervalSince1970: $0)) } ?? "—",
            failed: outcome?.failed, duration: outcome?.duration, onOpen: { onOpen(run.id) })
    }
}

/// The prompt as Markdown: `MarkdownView` with tables and `MEDIA:` lines. No `stripHTML`, unlike GitHub text: `<name>` in
/// a prompt is the prompt.
private struct JobPromptText: View {
    let text: String

    var body: some View {
        if text.isEmpty {
            Text("No prompt.").typeRole(.caption).foregroundStyle(Ink.text.muted)
        } else {
            MarkdownView(MarkdownPart.parse(text), lineGap: Space.xs) { block in
                switch block {
                case .table(let header, let rows, let alignments):
                    MarkdownTableView(header: header, rows: rows, alignments: alignments)
                case .image(let path):
                    Text("MEDIA:" + path).typeRole(.body).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                case .prose, .code:
                    EmptyView() // `parse` makes parts of these
                }
            }
        }
    }
}
