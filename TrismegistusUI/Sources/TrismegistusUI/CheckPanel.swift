import SwiftUI

/// The first card of an issue waiting for Martin's check (#59, `.check`, `.look`): what Hermes asked him to look at as a
/// numbered list with tick boxes, and the two answers. Ticks are a personal aid and never gate Looks good. Without
/// `canAct` (a viewer device) the card shows the lines and no actions. With a `result` it folds to one line.
public struct CheckPanel: View {
    /// What an answer posted.
    public enum Result: Sendable {
        case confirmed, notePosted

        var line: String {
            switch self {
            case .confirmed: "Confirmed on screen · Status Done"
            case .notePosted: "Note posted · Status Todo"
            }
        }
    }

    let lines: [String]
    /// `from Hermes · <comment date>`, right-aligned.
    let source: String
    let canAct: Bool
    let busy: Bool
    @Binding var note: String
    let ticked: Set<String>
    let result: Result?
    let tick: @MainActor (String) -> Void
    let looksGood: @MainActor () -> Void
    let notRight: @MainActor () -> Void

    public init(lines: [String], source: String, canAct: Bool, busy: Bool, note: Binding<String>, ticked: Set<String>,
                result: Result? = nil, tick: @escaping @MainActor (String) -> Void,
                looksGood: @escaping @MainActor () -> Void, notRight: @escaping @MainActor () -> Void) {
        self.lines = lines
        self.source = source
        self.canAct = canAct
        self.busy = busy
        self._note = note
        self.ticked = ticked
        self.result = result
        self.tick = tick
        self.looksGood = looksGood
        self.notRight = notRight
    }

    /// `ticked/total`.
    var reading: String { "\(lines.filter(ticked.contains).count)/\(lines.count)" }

    public var body: some View {
        Group {
            if let result {
                HStack(spacing: Space.s) {
                    Rectangle().fill(result == .confirmed ? Ink.status.online : Ink.status.bad).frame(width: Size.marker, height: Size.marker)
                    Text(result.line).typeRole(.label).foregroundStyle(Ink.text.primary).lineLimit(1)
                }
            } else {
                open
            }
        }
        .padding(.top, Stroke.accent + Space.m).padding([.horizontal, .bottom], Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        // #69: a section card whose yellow 2 pt top line glows faintly.
        .background {
            let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            ZStack {
                shape.fill(Ink.surface.sectionCard).shadow(Shadow.checkGlow)
                VStack(spacing: 0) {
                    Rectangle().fill(Ink.selection).frame(height: Stroke.accent)
                    Spacer(minLength: 0)
                }
                .clipShape(shape)
            }
        }
        .edge(Ink.line.rule, radius: Radius.control)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(result?.line ?? "Needs your check")
    }

    private var open: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Space.s) {
                Rectangle().fill(Ink.marker).frame(width: Size.marker, height: Size.marker).rotationEffect(.degrees(45))
                    .accessibilityHidden(true)
                Text("Needs your check").typeRole(.trackedLabel).foregroundStyle(Ink.text.secondary)
                if !lines.isEmpty { Text(verbatim: reading).typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary) }
                Spacer(minLength: Space.s)
                Text(source).typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary).lineLimit(1)
            }
            .padding(.bottom, Space.m)
            if lines.isEmpty {
                Text("No on-screen notes from Hermes; see the latest comment").typeRole(.body).foregroundStyle(Ink.text.secondary)
            } else {
                VStack(spacing: 0) {
                    rule
                    ForEach(lines.indices, id: \.self) { i in
                        LookRow(number: i + 1, line: lines[i], isTicked: ticked.contains(lines[i])) { tick(lines[i]) }
                        rule
                    }
                }
            }
            if canAct {
                HStack(spacing: Space.s) {
                    EndfieldButton("Looks good", symbol: Symbol.check, kind: .primary, action: looksGood).disabled(busy)
                    EndfieldTextField("What's not right? (posted as a comment)", text: $note).disabled(busy)
                    EndfieldButton("Not right", symbol: Symbol.close, kind: .danger, action: notRight)
                        .disabled(busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, lines.isEmpty ? Space.s : Space.l).padding(.bottom, Space.s)
                Text("Looks good: comments \"Confirmed on screen by Martin.\", Status Done. Not right: comments your note, reopens the issue if closed, Status Todo.")
                    .typeRole(.caption).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairlineFine)
    }
}

/// One look-at line: its number, a tick box and the text; the whole row ticks.
private struct LookRow: View {
    let number: Int
    let line: String
    let isTicked: Bool
    let toggle: @MainActor () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: Space.s) {
                Text(verbatim: "\(number)").typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary)
                    .frame(width: Space.l, height: Size.taskBox, alignment: .trailing)
                TaskBox(done: isTicked)
                Text(line).typeRole(.body).foregroundStyle(isTicked ? Ink.text.secondary : Ink.text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, Space.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(line)
        .accessibilityValue(isTicked ? "Ticked" : "Not ticked")
        .accessibilityAddTraits(.isToggle)
    }
}

/// An `info.circle` in the place of Dispatch: the reason it's hidden is its tooltip and accessibility label.
public struct DispatchHiddenMark: View {
    let reason: String

    @Environment(\.onSteel) private var onSteel

    public init(reason: String) { self.reason = reason }

    public var body: some View {
        Image(systemName: "info.circle")
            .typeRole(.button) // the size of the Open in browser icon beside it
            .foregroundStyle(onSteel ? Ink.text.onDark : Ink.text.secondary)
            .padding(Space.s)
            .help(reason)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reason)
    }
}

/// The body's task list in an issue's header (`.band-read`): a tick and `done/total`, on steel.
public struct TaskReading: View {
    let reading: String

    public init(_ reading: String) { self.reading = reading }

    public var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: Symbol.check).font(.system(size: Icon.l))
            Text(verbatim: reading).typeRole(.callout).monospacedDigit()
        }
        .padding(.trailing, Space.s)
        .help("Checklist done / total")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checklist \(reading)")
    }
}

/// A sunken chip in a readout row (`.tag`; Inter with `tag` corners since #69).
public struct ReadoutTag: View {
    let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(verbatim: text).typeRole(.micro).lineLimit(1).fixedSize()
            .padding(.horizontal, Space.xs).frame(minHeight: Size.chip)
            .rounded(Radius.tag, fill: Ink.surface.sunken)
    }
}

/// An issue's labels as `ReadoutTag`s, then `+N` for the ones left out. No labels read `none`. Without `shown`, as many
/// as fit the width offered (`FittingTagsLayout`); with it, the first `shown`.
public struct ReadoutTags: View {
    let tags: [String]
    let shown: Int?

    /// As many as fit the width the row offers (#73).
    public init(_ tags: [String]) {
        self.tags = tags
        self.shown = nil
    }

    public init(_ tags: [String], shown: Int) {
        self.tags = tags
        self.shown = shown
    }

    public var body: some View {
        Group {
            if tags.isEmpty {
                ReadoutTag("none")
            } else if let shown {
                HStack(spacing: Space.xs) {
                    ForEach(Array(tags.prefix(shown).enumerated()), id: \.offset) { ReadoutTag($0.element) }
                    if shown < tags.count { more(tags.count - shown) }
                }
            } else {
                FittingTagsLayout(spacing: Space.xs, count: tags.count) {
                    ForEach(Array(tags.enumerated()), id: \.offset) { ReadoutTag($0.element) }
                    ForEach(1...tags.count, id: \.self) { more($0) }
                }
            }
        }
        .help(tags.joined(separator: ", "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tags.isEmpty ? "none" : tags.joined(separator: ", "))
    }

    private func more(_ count: Int) -> some View {
        Text(verbatim: "+\(count)").typeRole(.micro, weight: .semibold).foregroundStyle(Ink.text.secondary).lineLimit(1).fixedSize()
    }
}

/// `count` tags, then the labels `+1` … `+count`: shows as many tags as fit the width offered, in order, and the one
/// `+N` naming the rest; the others go far off to the side. One layout, measured once (#73): the readout used to try
/// whole rows in a `ViewThatFits`, and with the rows' native menus inside SwiftUI and AppKit never agreed on a size.
struct FittingTagsLayout: Layout {
    let spacing: CGFloat
    let count: Int

    /// How many tags fit in `limit` (nil: no limit), and the width they take with their `+N`.
    static func fit(tags: [CGFloat], more: [CGFloat], spacing: CGFloat, limit: CGFloat?) -> (shown: Int, width: CGFloat) {
        func width(_ n: Int) -> CGFloat {
            var w = tags.prefix(n).reduce(0, +) + CGFloat(max(n - 1, 0)) * spacing
            if n < tags.count { w += (n > 0 ? spacing : 0) + more[tags.count - n - 1] }
            return w
        }
        guard let limit, limit.isFinite else { return (tags.count, width(tags.count)) }
        var n = tags.count
        while n > 0 && width(n) > limit { n -= 1 }
        return (n, width(n))
    }

    private func measure(_ subviews: Subviews) -> (tags: [CGSize], more: [CGSize]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        return (Array(sizes.prefix(count)), Array(sizes.dropFirst(count)))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (tags, more) = measure(subviews)
        let fit = Self.fit(tags: tags.map(\.width), more: more.map(\.width), spacing: spacing, limit: proposal.width)
        return CGSize(width: fit.width, height: (tags + more).map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (tags, more) = measure(subviews)
        let fit = Self.fit(tags: tags.map(\.width), more: more.map(\.width), spacing: spacing, limit: bounds.width)
        let away = CGPoint(x: bounds.minX - 100_000, y: bounds.minY)
        var x = bounds.minX
        for (i, subview) in subviews.enumerated() {
            let size = i < count ? tags[i] : more[i - count]
            let shows = i < count ? i < fit.shown : i - count + 1 == count - fit.shown
            guard shows else {
                subview.place(at: away, proposal: ProposedViewSize(size))
                continue
            }
            subview.place(at: CGPoint(x: x, y: bounds.midY - size.height / 2), proposal: ProposedViewSize(size))
            x += size.width + spacing
        }
    }
}
