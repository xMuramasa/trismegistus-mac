import SwiftUI

/// `● RUNNING  sonnet · 5 min` in an ink outline: the header mark of an issue with a live run. A view of its own so the
/// header's right side can put other marks next to it.
public struct RunningMark: View {
    let detail: String

    @Environment(\.onSteel) private var onSteel

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
        .foregroundStyle(onSteel ? Ink.text.onDark : Ink.text.primary)
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .overlay(Rectangle().strokeBorder(onSteel ? Ink.line.outlineOnDark : Ink.line.strong, lineWidth: Stroke.hairline))
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

/// The composer's top line: the run's state and clock (Inter, tabular figures, #68), then the keys as key caps on the
/// right. The keys go first when a pane narrows the column.
public struct RunLine: View {
    let state: String
    let isActive: Bool
    let clock: String?
    let hints: [(key: String, action: String)]

    public init(_ state: String, isActive: Bool = false, clock: String? = nil, hints: [(key: String, action: String)] = []) {
        self.state = state
        self.isActive = isActive
        self.clock = clock
        self.hints = hints
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            if isActive {
                Rectangle().fill(Ink.status.online).frame(width: Size.marker, height: Size.marker).accessibilityHidden(true)
            }
            Text(state).typeRole(.label).foregroundStyle(Ink.text.primary).lineLimit(1).fixedSize()
            if let clock { Text(verbatim: clock).typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary).fixedSize() }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.m) {
                    ForEach(hints, id: \.key) { hint($0.key, $0.action) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Color.clear.frame(height: 0)
            }
        }
        .frame(minHeight: Space.xl)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: Space.xs) {
            KeyCap(key)
            Text(action).typeRole(.callout).foregroundStyle(Ink.text.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// `>_ 2 COMMANDS · 6.7 s` with a chevron: unfolds the run's item cards in place.
public struct CommandChip: View {
    let commands: Int
    let duration: String
    let failed: Int
    @Binding var isOpen: Bool

    public init(commands: Int, duration: String, failed: Int = 0, isOpen: Binding<Bool>) {
        self.commands = commands
        self.duration = duration
        self.failed = failed
        self._isOpen = isOpen
    }

    public var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Space.s) {
                Text(verbatim: ">_").typeRole(.label)
                Text(verbatim: "\(commands) \(commands == 1 ? "command" : "commands") · \(duration)").typeRole(.label).monospacedDigit()
                if failed > 0 { Text(verbatim: "· \(failed) failed").typeRole(.label).foregroundStyle(Ink.text.error) }
                Image(systemName: isOpen ? Symbol.chevronUp : Symbol.chevronDown).font(.system(size: Icon.xxs, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Ink.text.primary)
            .padding(.horizontal, Space.s)
            .frame(height: Size.cardHeader)
            .rounded(Radius.m, fill: Ink.surface.sunken)
            .contentShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? "Open" : "Folded")
    }
}

/// The running work: the command chip, WORKING and its readings on one line, a progress track under them.
public struct WorkLine<Chip: View>: View {
    let detail: String
    let chip: Chip

    public init(detail: String, @ViewBuilder chip: () -> Chip) {
        self.detail = detail
        self.chip = chip()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.m) {
                chip
                Text("Working").typeRole(.label).foregroundStyle(Ink.text.primary)
                Text(verbatim: detail).typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary)
            }
            WorkTrack()
        }
    }
}

/// A 2 pt rule with an ink segment going to and fro, parked under Reduce Motion. Ink, not yellow: the screen's one yellow
/// mark stays on Steer.
struct WorkTrack: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The segment: 30 % of the track, 2.4 s each way, parked at 35 %.
    private static let period = 2.4, width = 0.3, restingPhase = 0.35

    /// Eased position across the track, 0…1, at a time in seconds.
    static func phase(_ time: Double) -> Double {
        let t = (time / period).truncatingRemainder(dividingBy: 2)
        let way = t <= 1 ? t : 2 - t
        return way * way * (3 - 2 * way)
    }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let phase = reduceMotion ? Self.restingPhase : Self.phase(context.date.timeIntervalSinceReferenceDate)
            Rectangle().fill(Ink.line.rule)
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().fill(Ink.line.strong)
                            .frame(width: geo.size.width * Self.width)
                            .offset(x: geo.size.width * (1 - Self.width) * phase)
                    }
                }
                .clipped()
        }
        .frame(height: Stroke.accent)
        .accessibilityHidden(true)
    }
}
