import SwiftUI

/// `● RUNNING  sonnet · 5 min` in an ink outline: the header mark of an issue with a live run. A view of its own so the
/// header's right side can put other marks next to it.
public struct RunningMark: View {
    let detail: String

    public init(detail: String) {
        self.detail = detail
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Circle().fill(Ink.status.online).frame(width: Size.dot, height: Size.dot)
                .overlay(Circle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
            Text("Running").typeRole(.label)
            if !detail.isEmpty { Text(detail).typeRole(.monoSmall) }
        }
        .foregroundStyle(Ink.text.primary)
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .overlay(Rectangle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.isEmpty ? "Running" : "Running, \(detail)")
    }
}

/// A filled triangle beside `#N` in a list row: a live run, by shape and not by colour.
public struct RunningTriangle: View {
    public init() {}

    public var body: some View {
        Image(systemName: "play.fill").font(.system(size: Icon.xxs)).accessibilityLabel("Running")
    }
}

/// The run on an issue, in the Agents list's style: model, age and how it stands, then its last progress line, with a
/// link to the transcript and, for a manager while it runs, Stop. Plain values, so the app owns the agent model.
public struct IssueRunRow: View {
    let model: String?
    let age: String
    let status: String
    let isAlive: Bool
    let failed: Bool
    let progress: String?
    /// `Stop` shows for a manager's live run; `Stopping…` once asked.
    let canStop: Bool
    let isStopping: Bool
    let openTranscript: @MainActor () -> Void
    let stop: @MainActor () -> Void

    public init(model: String?, age: String, status: String, isAlive: Bool, failed: Bool, progress: String?, canStop: Bool,
                isStopping: Bool, openTranscript: @escaping @MainActor () -> Void, stop: @escaping @MainActor () -> Void) {
        self.model = model
        self.age = age
        self.status = status
        self.isAlive = isAlive
        self.failed = failed
        self.progress = progress
        self.canStop = canStop
        self.isStopping = isStopping
        self.openTranscript = openTranscript
        self.stop = stop
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.s) {
                    if isAlive {
                        Circle().fill(Ink.status.online).frame(width: Size.dot, height: Size.dot)
                            .overlay(Circle().strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
                            .accessibilityHidden(true)
                    }
                    Text(model ?? "run").typeRole(.headline).foregroundStyle(Ink.text.primary)
                    Text(age).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                    Text(status).typeRole(.label).foregroundStyle(failed ? Ink.text.error : Ink.text.secondary)
                }
                if let progress, !progress.isEmpty {
                    Text(progress).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).lineLimit(2).truncationMode(.tail)
                }
            }
            Spacer(minLength: Space.s)
            EndfieldButton("Transcript", symbol: Symbol.chevronRight, action: openTranscript)
            if canStop {
                if isStopping {
                    Text("Stopping…").typeRole(.label).foregroundStyle(Ink.text.secondary)
                } else {
                    EndfieldButton("Stop", symbol: Symbol.stop, kind: .danger, action: stop)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
    }
}
