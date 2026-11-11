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

    /// The bar at the tag's left edge and the glyph.
    var mark: Color {
        switch self {
        case .approval: Ink.marker
        case .running: Ink.selection
        case .failed: Ink.status.error
        case .done: Ink.status.ok
        }
    }

    /// RUN is the one dark chip; the rest are light.
    var ground: Color { self == .running ? Ink.surface.darkPanel : Ink.surface.raised }
    var edge: Color { self == .running ? Ink.surface.darkPanel : Ink.line.rule }
    var text: Color { self == .running ? Ink.text.onPanel : Ink.text.primary }
}

/// The state's shape, so a tag never relies on colour: diamond, ring, cross, check, on a 12 pt grid.
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

/// A state tag (#69, design 13 #a3, replacing B2's sticker): 18 pt, a light chip with a rule hairline and `tag` corners,
/// a 2 pt bar in the state's colour at its left edge, the small coloured glyph, then the word in tracked caps. RUN is the
/// dark-panel chip with a yellow bar, ring and time. `showsWord` off keeps the glyph and the time; a badge is the glyph
/// alone (the panel's rows), 16 pt.
public struct Sticker: View {
    let state: StickerState
    let time: String?
    let showsWord: Bool
    let isBadge: Bool

    public init(_ state: StickerState, time: String? = nil, showsWord: Bool = true, isBadge: Bool = false) {
        self.state = state
        self.time = time
        self.showsWord = showsWord
        self.isBadge = isBadge
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tag, style: .continuous)
        HStack(spacing: 0) {
            StickerGlyph(state: state).fill(state.mark)
                .frame(width: Size.sticker.glyph, height: Size.sticker.glyph)
                .frame(width: isBadge ? Size.sticker.badgeCell : Size.sticker.cell)
            if !isBadge, showsWord || time != nil {
                HStack(spacing: Space.xs) {
                    if showsWord { Text(state.word).typeRole(.tag).foregroundStyle(state.text) }
                    if let time { Text(verbatim: time).typeRole(.tag).monospacedDigit().foregroundStyle(state.mark) }
                }
                .lineLimit(1).fixedSize()
                .padding(.trailing, Space.s)
            }
        }
        .padding(.leading, Stroke.accent)
        .frame(height: isBadge ? Size.sticker.badge : Size.sticker.height)
        .background(state.ground)
        .overlay(alignment: .leading) { Rectangle().fill(state.mark).frame(width: Stroke.accent) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(state.edge, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.spoken)
    }
}
