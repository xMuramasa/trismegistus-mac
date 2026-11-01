import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The window sidebar's Jobs row, under Commands: the job count, and a mark when the last run of any job failed.
struct JobsRowView: View {
    let board: JobBoard
    let isSelected: Bool

    @Environment(\.sunkenRows) private var sunken

    private var detail: String {
        let count = board.jobs.count, paused = board.jobs.filter(\.isPaused).count
        return "\(count) \(count == 1 ? "job" : "jobs")" + (paused > 0 ? " · \(paused) paused" : "")
    }

    var body: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Jobs").typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(1)
                HStack(spacing: Space.s) {
                    Image(systemName: Symbol.cron).font(.system(size: Icon.m))
                    Text(detail).typeRole(.monoSmall).lineLimit(1)
                }
                .foregroundStyle(sunken ? Ink.text.secondary : Ink.text.muted)
            }
            Spacer(minLength: Space.s)
            if board.anyFailed {
                Image(systemName: JobsView.failedSymbol).font(.system(size: Icon.m)).foregroundStyle(Ink.status.error)
                    .help("The last run of a job failed").accessibilityLabel("A run failed")
            }
            if isSelected {
                Image(systemName: Symbol.chevronRight).font(.system(size: Icon.s)).foregroundStyle(Ink.text.primary)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Size.row)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Hermes' cron jobs: the list on top (up to four rows, then it scrolls), the selected job's detail below it. Fetched
/// again every 30 s while shown. A viewer device reads; only a manager gets the form and the job's buttons.
struct JobsView: View {
    nonisolated static let id = "trismegistus.jobs" // in selections; not a Hermes session id
    static let failedSymbol = "exclamationmark.triangle"
    /// The selection while the create form is shown.
    private static let newJob = "new"
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model
    @State private var selected: String?

    var body: some View {
        Group {
            if let board = model.jobs {
                content(board)
                    .task(id: ObjectIdentifier(board)) {
                        while !Task.isCancelled {
                            await board.refresh()
                            try? await Task.sleep(for: .seconds(30))
                        }
                    }
                    .onChange(of: board.jobs.map(\.id), initial: true) { _, ids in
                        if selected != Self.newJob, !ids.contains(selected ?? "") { selected = ids.first }
                    }
            } else {
                Text("Not connected.").typeRole(.caption).foregroundStyle(Ink.text.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Ink.surface.window)
    }

    private func content(_ board: JobBoard) -> some View {
        VStack(spacing: 0) {
            header(board)
            Rectangle().fill(Ink.line.rule).frame(height: 1)
            if let error = board.error { notice(error, board: board) }
            list(board)
            Rectangle().fill(Ink.line.rule).frame(height: 1)
            ScrollView {
                if selected == Self.newJob, board.canManage {
                    JobDetail(job: nil, board: board, onOpen: onOpen, onCreated: { selected = $0 }).id(Self.newJob)
                } else if let job = board.jobs.first(where: { $0.id == selected }) {
                    JobDetail(job: job, board: board, onOpen: onOpen, onCreated: { _ in }).id(job.id)
                }
            }
            .settledWidth()
        }
    }

    private func header(_ board: JobBoard) -> some View {
        HStack(spacing: Space.s) {
            Text("Jobs // \(board.jobs.count)").typeRole(.label).foregroundStyle(Ink.text.secondary)
            Spacer(minLength: Space.s)
            if board.canManage {
                EndfieldButton("New job", symbol: Symbol.plus, kind: .quiet, iconOnly: true) { selected = Self.newJob }
            }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    /// One line over the jobs already fetched, which stay.
    private func notice(_ error: RelayAPIError, board: JobBoard) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: Self.failedSymbol).font(.system(size: Icon.m)).accessibilityHidden(true)
            Text(error.code == .hermesUnavailable ? "Hermes' cron scheduler isn't available. \(error.message)" : error.message)
                .typeRole(.callout).lineLimit(2)
            Spacer(minLength: Space.s)
            EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) { Task { await board.refresh() } }
        }
        .foregroundStyle(Ink.text.secondary)
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .background(Ink.surface.sunken)
    }

    @ViewBuilder private func list(_ board: JobBoard) -> some View {
        if board.jobs.isEmpty {
            Text(board.isLoaded ? "No jobs yet." : "Reading the jobs…").typeRole(.caption).foregroundStyle(Ink.text.muted)
                .padding(Space.l).frame(maxWidth: .infinity)
        } else {
            let rows = VStack(spacing: 0) {
                ForEach(board.jobs) { job in
                    Button { selected = job.id } label: { JobRow(job: job, isSelected: selected == job.id) }
                        .buttonStyle(.plain)
                }
            }
            if board.jobs.count <= 4 {
                rows
            } else {
                ScrollView { rows }.frame(height: Size.row * 4.5)
            }
        }
    }
}

/// A job in the list: name and marks, then schedule in words, next run, last run, model.
private struct JobRow: View {
    let job: Job
    let isSelected: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(job.title).typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(1)
                    if job.isPaused { Text("Paused").typeRole(.label).foregroundStyle(Ink.text.secondary) }
                    Spacer(minLength: Space.s)
                    if let model = job.model { Text(model).typeRole(.monoSmall).foregroundStyle(Ink.text.muted).lineLimit(1) }
                }
                HStack(spacing: Space.s) {
                    Text(job.scheduleWords)
                    if !job.isPaused, let next = job.nextRun { Text("· next \(JobDetail.relative(next, now: context.date))") }
                    lastRun(now: context.date)
                }
                .typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).lineLimit(1)
            }
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
            .rowGround(isSelected: isSelected)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func lastRun(now: Date) -> some View {
        if let last = job.lastRun {
            if job.lastRunFailed {
                Text("· failed \(PopoverFormat.ago(last, now: now)): \(job.lastErrorLine ?? "no error line")").foregroundStyle(Ink.text.error)
            } else {
                Text("· ok \(PopoverFormat.ago(last, now: now))")
            }
        }
    }
}
