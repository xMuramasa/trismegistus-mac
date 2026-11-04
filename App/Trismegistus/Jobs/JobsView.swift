import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The Jobs section's sidebar: `JOBS // n`, New job for a manager, the filter, one row per job.
struct JobsSidebar: View {
    @Binding var selection: String?
    var filterFocus: FocusState<Bool>.Binding

    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        let board = model.jobs
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let jobs = (board?.jobs ?? []).filter { needle.isEmpty || $0.title.localizedCaseInsensitiveContains(needle) }
        VStack(spacing: 0) {
            SidebarHeader(title: "Jobs // \(board?.jobs.count ?? 0)", prompt: "Filter jobs", filter: $filter, focus: filterFocus) {
                if board?.canManage == true {
                    EndfieldButton("New job", symbol: Symbol.plus, kind: .quiet, iconOnly: true) { selection = JobsView.newJob }
                }
            }
            if let board, board.jobs.isEmpty {
                SidebarNote(text: board.isLoaded ? "No jobs yet." : "Reading the jobs…")
            } else if board == nil {
                SidebarNote(text: "Not connected.")
            }
            List(selection: $selection) {
                ForEach(jobs) { job in
                    JobRow(job: job, isSelected: selection == job.id).tag(job.id).sidebarRow()
                }
            }
            .sidebarList()
        }
    }
}

/// Hermes' cron jobs: the selected job's detail (or the create form) at full height. Fetched again every 30 s while
/// shown. A viewer device reads; only a manager gets the form and the job's buttons.
struct JobsView: View {
    static let failedSymbol = "exclamationmark.triangle"
    /// The selection while the create form is shown.
    static let newJob = "new"
    @Binding var selection: String?
    let onOpen: (String) -> Void

    @Environment(AppModel.self) private var model

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
                        guard board.isLoaded, selection != Self.newJob || !board.canManage else { return }
                        selection = WindowSection.kept(selection, in: ids)
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
            if let error = board.error { notice(error, board: board) }
            if selection == Self.newJob, board.canManage {
                ScrollView {
                    JobDetail(job: nil, board: board, onOpen: onOpen, onCreated: { selection = $0 }).id(Self.newJob)
                }
                .settledWidth()
            } else if let job = board.jobs.first(where: { $0.id == selection }) {
                ScrollView {
                    JobDetail(job: job, board: board, onOpen: onOpen, onCreated: { _ in }).id(job.id)
                }
                .settledWidth()
            } else {
                SectionEmpty(symbol: WindowSection.jobs.symbol, text: board.isLoaded ? "No job selected" : "Reading the jobs…")
            }
        }
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
}

/// A job in the sidebar: name and marks, then schedule in words, next run, last run.
private struct JobRow: View {
    let job: Job
    let isSelected: Bool

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        let ink = RowInk(onSidebar: onSidebar, isSelected: isSelected)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    Text(job.title).typeRole(.headline).foregroundStyle(ink.title).lineLimit(1)
                    Spacer(minLength: Space.s)
                    if job.isPaused { Text("Paused").typeRole(.label).foregroundStyle(ink.meta) }
                }
                HStack(spacing: Space.s) {
                    Text(job.scheduleWords)
                    if !job.isPaused, let next = job.nextRun { Text(verbatim: "· next \(JobDetail.relative(next, now: context.date))") }
                    lastRun(now: context.date, ink: ink)
                }
                .typeRole(.monoSmall).foregroundStyle(ink.meta).lineLimit(1)
            }
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
            .rowGround(isSelected: isSelected)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private func lastRun(now: Date, ink: RowInk) -> some View {
        if let last = job.lastRun {
            if job.lastRunFailed {
                Text(verbatim: "· failed \(PopoverFormat.ago(last, now: now)): \(job.lastErrorLine ?? "no error line")").foregroundStyle(ink.error)
            } else {
                Text(verbatim: "· ok \(PopoverFormat.ago(last, now: now))")
            }
        }
    }
}
