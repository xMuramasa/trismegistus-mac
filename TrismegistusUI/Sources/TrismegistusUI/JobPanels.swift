import SwiftUI

// The job detail's parts (#61), fed by `JobDetail`. Plain values only, no TrismegistusKit; here so the snapshots draw
// the shipped views.
// shortcut: `TrismegistusUITests/JobPanels.swift` is a copy of this file (a test fails if they differ); move this to
// TrismegistusUI as public views and drop the copy.

/// A raised box (`.panel`), under a head when it has one.
public struct JobPanel<Content: View>: View {
    let title: String?
    let content: Content

    public init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                // `.prompt-head`: 1 pt ink under the label.
                Text(title).typeRole(.label).foregroundStyle(Ink.text.primary)
                    .padding(.bottom, Space.xs)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.strong).frame(height: Stroke.hairline) }
                    .padding(.bottom, Space.m)
            }
            content
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
    }
}

/// The header's actions.
public struct JobActions: View {
    let isPaused: Bool
    let isBusy: Bool
    let onPause: () -> Void
    let onRun: () -> Void
    let onEdit: () -> Void

    public init(isPaused: Bool, isBusy: Bool, onPause: @escaping () -> Void, onRun: @escaping () -> Void, onEdit: @escaping () -> Void) {
        self.isPaused = isPaused
        self.isBusy = isBusy
        self.onPause = onPause
        self.onRun = onRun
        self.onEdit = onEdit
    }

    public var body: some View {
        EndfieldButton(isPaused ? "Resume" : "Pause", symbol: isPaused ? "play" : "pause") { onPause() }.disabled(isBusy)
        EndfieldButton("Run now", symbol: "play.fill", kind: .primary) { onRun() }.disabled(isBusy)
        EndfieldButton("Edit", symbol: "pencil") { onEdit() }.disabled(isBusy)
    }
}

/// The header's actions while editing.
public struct JobEditActions: View {
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    public init(canSave: Bool, onCancel: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.canSave = canSave
        self.onCancel = onCancel
        self.onSave = onSave
    }

    public var body: some View {
        EndfieldButton("Cancel", symbol: Symbol.close) { onCancel() }
        EndfieldButton("Save", symbol: Symbol.check, kind: .primary) { onSave() }.disabled(!canSave)
    }
}

/// Cadence, next runs and last result (`.stats`): three equal columns, 1 pt rules.
public struct JobReadout: View {
    public struct Last {
        var failed: Bool
        var time: String
        var ago: String
        var error: String?

        public init(failed: Bool, time: String, ago: String, error: String? = nil) {
            self.failed = failed
            self.time = time
            self.ago = ago
            self.error = error
        }
    }

    let cadence: String
    let cron: String?
    let nextRuns: [String]
    /// In place of `nextRuns` when there are none.
    let noRuns: String
    let last: Last?

    public init(cadence: String, cron: String?, nextRuns: [String], noRuns: String, last: Last?) {
        self.cadence = cadence
        self.cron = cron
        self.nextRuns = nextRuns
        self.noRuns = noRuns
        self.last = last
    }

    public var body: some View {
        HStack(spacing: 0) {
            column("Cadence") {
                Text(verbatim: cadence).typeRole(.headline).foregroundStyle(Ink.text.primary)
                if let cron {
                    Text(verbatim: cron).typeRole(.monoSmall).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                        .padding(.horizontal, Space.xs).background(Ink.surface.sunken)
                }
            }
            column("Next runs", ruled: true) {
                if nextRuns.isEmpty {
                    Text(verbatim: noRuns).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                } else {
                    ForEach(nextRuns, id: \.self) { Text(verbatim: $0).typeRole(.monoSmall).foregroundStyle(Ink.text.primary) }
                }
            }
            column("Last result", ruled: true) {
                if let last {
                    HStack(spacing: Space.s) {
                        StatusChip(last.failed ? "failed" : "ok", kind: last.failed ? .err : .ok)
                        Text(verbatim: last.time).typeRole(.monoSmall).foregroundStyle(Ink.text.primary)
                    }
                    Text(verbatim: last.ago).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                    if let error = last.error {
                        Text(verbatim: error).typeRole(.monoSmall).foregroundStyle(Ink.text.error).textSelection(.enabled)
                    }
                } else {
                    Text("no runs yet").typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
    }

    private func column(_ label: String, ruled: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeRole(.label).foregroundStyle(Ink.text.secondary)
            content()
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) {
            if ruled { Rectangle().fill(Ink.line.rule).frame(width: Stroke.hairline) }
        }
    }
}

/// The prompt under its head, folded after 8 lines with Show all.
public struct JobPromptPanel<Prompt: View>: View {
    let prompt: Prompt

    @State private var isOpen: Bool
    /// The prompt's natural height, once laid out.
    @State private var height: CGFloat = 0

    public init(isOpen: Bool = false, @ViewBuilder prompt: () -> Prompt) {
        _isOpen = State(initialValue: isOpen)
        self.prompt = prompt()
    }

    public var body: some View {
        JobPanel("Prompt") {
            prompt.fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .frame(maxHeight: isOpen ? nil : Size.jobPromptFold, alignment: .top)
                .clipped()
                // Blocks don't stack in whole lines, so the fold's edge can cut one: fade the last 32 pt out.
                .mask {
                    if !isOpen && height > Size.jobPromptFold {
                        LinearGradient(stops: [.init(color: .black, location: 1 - Space.xxxl / Size.jobPromptFold),
                                               .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle()
                    }
                }
            if height > Size.jobPromptFold { foldButton.padding(.top, Space.s) }
        }
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
        .accessibilityHint(isOpen ? "Folds the prompt" : "Shows the whole prompt")
    }
}

/// One run: its time, then its outcome and length where Hermes has them. Opens the conversation.
public struct JobRunRow: View {
    let time: String
    var failed: Bool?
    var duration: String?
    let onOpen: () -> Void

    public init(time: String, failed: Bool? = nil, duration: String? = nil, onOpen: @escaping () -> Void) {
        self.time = time
        self.failed = failed
        self.duration = duration
        self.onOpen = onOpen
    }

    public var body: some View {
        Button { onOpen() } label: {
            HStack(spacing: Space.s) {
                Text(verbatim: time).typeRole(.monoSmall).foregroundStyle(Ink.text.primary)
                if let failed { StatusChip(failed ? "failed" : "ok", kind: failed ? .err : .ok) }
                if let duration { Text(verbatim: duration).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary) }
                Spacer(minLength: Space.s)
                Image(systemName: Symbol.chevronRight).font(.system(size: Icon.xs)).foregroundStyle(Ink.text.link)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Size.rowTool)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open the conversation")
    }
}

/// Label and value rows: the job's settings.
public struct JobValues: View {
    let rows: [(String, String)]

    public init(rows: [(String, String)]) { self.rows = rows }

    public var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Space.m, verticalSpacing: Space.xs) {
            ForEach(rows, id: \.0) { label, value in
                GridRow {
                    Text(label).typeRole(.caption).foregroundStyle(Ink.text.secondary)
                    Text(value).typeRole(.monoSmall).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                }
            }
        }
    }
}

/// The form's schedule controls: `JobDetail` turns a preset into these, nil where the preset has no such control.
public struct JobSchedulePicker {
    /// The preset's name; nil for a schedule no preset wrote.
    var kind: String?
    var kinds: [String]
    var choose: (String) -> Void
    var weekdays: [String]
    var weekday: Binding<Int>?
    var minute: Binding<Int>?
    var time: Binding<Date>?

    public init(kind: String?, kinds: [String], choose: @escaping (String) -> Void, weekdays: [String],
                weekday: Binding<Int>? = nil, minute: Binding<Int>? = nil, time: Binding<Date>? = nil) {
        self.kind = kind
        self.kinds = kinds
        self.choose = choose
        self.weekdays = weekdays
        self.weekday = weekday
        self.minute = minute
        self.time = time
    }
}

/// The job form: what the relay lets the app write. `paused` is create only, `onDelete` an existing job's.
public struct JobForm: View {
    @Binding var name: String
    @Binding var schedule: String
    @Binding var prompt: String
    @Binding var deliver: String
    @Binding var skills: String
    @Binding var repeatTimes: String
    var paused: Binding<Bool>?
    let picker: JobSchedulePicker
    /// What the schedule means next.
    let preview: String
    var onDelete: (() -> Void)?

    public init(name: Binding<String>, schedule: Binding<String>, prompt: Binding<String>, deliver: Binding<String>,
                skills: Binding<String>, repeatTimes: Binding<String>, paused: Binding<Bool>? = nil, picker: JobSchedulePicker,
                preview: String, onDelete: (() -> Void)? = nil) {
        _name = name
        _schedule = schedule
        _prompt = prompt
        _deliver = deliver
        _skills = skills
        _repeatTimes = repeatTimes
        self.paused = paused
        self.picker = picker
        self.preview = preview
        self.onDelete = onDelete
    }

    public var body: some View {
        JobPanel {
            VStack(alignment: .leading, spacing: Space.m) {
                field("Name") { EndfieldTextField("Nightly backup", text: $name) }
                field("Schedule") {
                    VStack(alignment: .leading, spacing: Space.s) {
                        presets
                        EndfieldTextField("0 3 * * *, every 2h, 30m or an ISO time", text: $schedule)
                        Text(verbatim: preview).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                    }
                }
                field("Prompt") {
                    TextEditor(text: $prompt)
                        .typeRole(.mono)
                        .foregroundStyle(Ink.text.primary)
                        .scrollContentBackground(.hidden)
                        .padding(Space.s)
                        .frame(height: Size.jobPromptEditor)
                        .background(Ink.surface.raised)
                        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
                        .accessibilityLabel("Prompt")
                }
                field("Deliver to") {
                    HStack(spacing: Space.s) {
                        ForEach(["local", "telegram"], id: \.self) { target in
                            FilterChip(title: target, symbol: target == "local" ? "tray" : Symbol.telegram, isOn: deliver == target) {
                                deliver = target
                            }
                        }
                        EndfieldTextField("or another target", text: $deliver)
                    }
                }
                field("Skills") { EndfieldTextField("none (comma-separated)", text: $skills) }
                field("Repeat") {
                    EndfieldTextField("forever (or a number of runs)", text: $repeatTimes).frame(maxWidth: Size.pickerMax)
                }
                if let paused {
                    Toggle("Start paused", isOn: paused).endfieldSwitch().typeRole(.body)
                }
                if let onDelete {
                    EndfieldButton("Delete", symbol: "trash", kind: .danger) { onDelete() }
                }
            }
        }
    }

    private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).typeRole(.label).foregroundStyle(Ink.text.secondary)
            content()
        }
    }

    private var presets: some View {
        HStack(spacing: Space.s) {
            Menu(picker.kind?.capitalized ?? "Custom") {
                ForEach(picker.kinds, id: \.self) { kind in
                    Button(kind.capitalized) { picker.choose(kind) }
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .accessibilityLabel("Schedule preset")
            if let weekday = picker.weekday {
                Picker("Day", selection: weekday) {
                    ForEach(picker.weekdays.indices, id: \.self) { Text(picker.weekdays[$0]).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            if let minute = picker.minute {
                Picker("Minute", selection: minute) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "at :%02d", $0)).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            if let time = picker.time {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .fixedSize()
            }
        }
    }
}
