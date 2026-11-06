import SwiftUI

/// What a row or a tab has to say, strongest first. The app shows approval and running; failed and done come with the
/// run alerts.
public enum StickerState: CaseIterable, Sendable {
    case approval, running, failed, done

    var word: String {
        switch self {
        case .approval: "Approval"
        case .running: "Run"
        case .failed: "Failed"
        case .done: "Done"
        }
    }

    /// What VoiceOver reads for it.
    var spoken: String {
        switch self {
        case .approval: "approval waiting"
        case .running: "running"
        case .failed: "failed, unseen"
        case .done: "done, unseen"
        }
    }

    var fill: Color {
        switch self {
        case .approval: Ink.marker
        case .running: Ink.surface.inverse
        case .failed: Ink.status.error
        case .done: Ink.status.online
        }
    }

    /// The word and the time on `fill`.
    var text: Color {
        switch self {
        case .approval, .done: Ink.text.primary
        case .running, .failed: Ink.surface.raised
        }
    }

    var cell: Color {
        switch self {
        case .approval, .done: Ink.surface.inverse
        case .running: Ink.selection
        case .failed: Ink.surface.raised
        }
    }

    /// The shape on `cell`.
    var glyph: Color {
        switch self {
        case .approval: Ink.marker
        case .running: Ink.text.primary
        case .failed: Ink.status.error
        case .done: Ink.status.online
        }
    }
}

/// The state's shape, so a sticker never relies on colour: diamond, ring, cross, check, on a 12 pt grid.
struct StickerGlyph: Shape {
    let state: StickerState

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var stroked = true
        switch state {
        case .approval:
            path = Path.svg("M6 1L11 6L6 11L1 6Z")
            stroked = false
        case .running:
            path.addArc(center: CGPoint(x: 6, y: 6), radius: Icon.sticker / 3, startAngle: .degrees(-90), endAngle: .degrees(180), clockwise: false)
        case .failed:
            path = Path.svg("M3 3L9 9M9 3L3 9")
        case .done:
            path = Path.svg("M2 6.5L5 9.5L10 2.5")
        }
        if stroked { path = path.strokedPath(StrokeStyle(lineWidth: Stroke.accent)) }
        return path.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / Icon.sticker, y: rect.height / Icon.sticker))
    }
}

/// A square sticker: a glyph cell, then the word and (on a run) the time; approval ends in hard ink and magenta stripes.
/// `showsWord` off keeps the cell, the time and the stripes (a narrow sidebar). A badge is the cell alone, a little shorter.
public struct Sticker: View {
    let state: StickerState
    let time: String?
    let showsWord: Bool
    let isBadge: Bool
    let edge: Color

    public init(_ state: StickerState, time: String? = nil, showsWord: Bool = true, isBadge: Bool = false, edge: Color = Ink.line.strong) {
        self.state = state
        self.time = time
        self.showsWord = showsWord
        self.isBadge = isBadge
        self.edge = edge
    }

    public var body: some View {
        HStack(spacing: 0) {
            StickerGlyph(state: state).fill(state.glyph)
                .frame(width: Icon.sticker, height: Icon.sticker)
                .frame(width: Size.sticker.cell)
                .frame(maxHeight: .infinity)
                .background(state.cell)
            if !isBadge {
                if showsWord || time != nil {
                    HStack(spacing: Space.xs) {
                        if showsWord { Text(state.word).typeRole(.sticker) }
                        // A run's time in yellow on ink, as in the prototype (review, 2026-11-06).
                        if let time {
                            Text(verbatim: time).typeRole(.data).monospacedDigit()
                                .foregroundStyle(state == .running ? Ink.selection : state.text)
                        }
                    }
                    .lineLimit(1).fixedSize()
                    .foregroundStyle(state.text)
                    .padding(.horizontal, Space.xs)
                    .frame(maxHeight: .infinity)
                    .background(state.fill)
                }
                if state == .approval { stripes }
            }
        }
        .padding(Stroke.hairline)
        .frame(height: isBadge ? Size.sticker.badge : Size.sticker.height)
        .edge(edge)
        .compositingGroup()  // one shadow for the sticker, not one per word
        .shadow(isBadge || state == .done ? Shadow.none : Shadow.sticker)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.spoken)
    }

    private var stripes: some View {
        HStack(spacing: Stroke.accent) {
            ForEach(0..<3, id: \.self) { _ in Rectangle().fill(state.fill).frame(width: Stroke.accent) }
        }
        .padding(.trailing, Stroke.accent)
        .background(state.cell)
    }
}
