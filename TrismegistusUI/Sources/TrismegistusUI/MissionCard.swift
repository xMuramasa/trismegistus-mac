import SwiftUI

/// A conversation in the window's chat list as an Endfield mission card (#72, design 13 #a3-c2 and #a3-c-states; it
/// replaced #69's `SessionRowView` card there, the popover keeps its rows): 56 pt, white at 90 % with a rule hairline
/// and `control` corners, a 3 pt bar at the left edge in the state's colour (contour with none); the source glyph in a
/// contour triangle, a divider, the title (14 pt, 500; 600 with a state or selected) with the pin, the preview with the
/// lock; the age over a short hatch at the right; the state as a pill half over the top edge. No tags and no index.
/// Hover: white with a contour edge and a soft shadow. Selected: an ink frame, a yellow wash from the left and faint
/// stripes. Lay it in `missionCell`, which leaves the pill its room above.
public struct MissionCard: View {
    let name: String
    let source: SessionSource
    let activity: String
    let preview: String?
    let isSelected: Bool
    let isReadOnly: Bool
    let isPinned: Bool
    let runElapsed: String?
    let needsApproval: Bool
    /// FAILED or DONE, once the run alerts exist (#66); approval and a run win over it.
    let finished: StickerState?

    public init(
        name: String, source: SessionSource, activity: String, preview: String? = nil, isSelected: Bool = false,
        isReadOnly: Bool = false, isPinned: Bool = false, runElapsed: String? = nil, needsApproval: Bool = false,
        finished: StickerState? = nil
    ) {
        self.name = name
        self.source = source
        self.activity = activity
        self.preview = preview
        self.isSelected = isSelected
        self.isReadOnly = isReadOnly
        self.isPinned = isPinned
        self.runElapsed = runElapsed
        self.needsApproval = needsApproval
        self.finished = finished
    }

    @Environment(\.rowHovered) private var isHovered

    private static let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)

    /// Approval wins over the run it holds up.
    var state: StickerState? { needsApproval ? .approval : runElapsed != nil ? .running : finished }

    /// What VoiceOver reads.
    var spoken: String {
        ([name, state?.spoken, activity, isReadOnly ? "read-only" : nil, isPinned ? "pinned" : nil] as [String?])
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public var body: some View {
        // Semibold is for a state and the selection: a quiet card stays at 500.
        let strong = state != nil || isSelected
        HStack(spacing: 0) {
            emblem
            Rectangle().fill(isSelected ? Ink.mission.dividerSelected : Ink.line.rule)
                .frame(width: Stroke.hairline, height: Size.mission.divider)
                .padding(.trailing, Space.m)
            VStack(alignment: .leading, spacing: Space.xxs) {
                HStack(spacing: Size.mission.textGap) {
                    Text(name).typeRole(.missionTitle, weight: strong ? .semibold : nil).foregroundStyle(Ink.text.primary).lineLimit(1)
                    if isPinned { Image(systemName: Symbol.pinOutline).font(.system(size: Icon.sticker)).foregroundStyle(Ink.text.secondary) }
                }
                HStack(spacing: Size.mission.textGap) {
                    if isReadOnly { Image(systemName: Symbol.lockOutline).font(.system(size: Icon.m)) }
                    Text(preview ?? "").typeRole(.callout).lineLimit(1)
                }
                .foregroundStyle(Ink.text.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Size.mission.sideGap) {
                Text(activity).typeRole(.caption).monospacedDigit().foregroundStyle(Ink.text.secondary).lineLimit(1).fixedSize()
                Hatch.across(Size.mission.hatchPitch).stroke(Ink.line.contour, lineWidth: Stroke.selection)
                    .frame(width: Size.mission.hatchWidth, height: Size.mission.hatchHeight).clipped()
                    .accessibilityHidden(true)
            }
            .padding(.trailing, Size.mission.sideInset).padding(.bottom, Size.mission.sideBottom)
            .frame(minWidth: Size.mission.column, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(height: Size.mission.height)
        .background { ground }
        .overlay { edge }
        .overlay(alignment: .topTrailing) {
            if let state {
                StatePill(state: state, time: runElapsed)
                    .offset(y: -Size.statePill.rise)
                    .padding(.trailing, Size.statePill.inset)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The contour triangle with the source glyph in its upper part; ink at 28 % and an ink glyph when selected.
    private var emblem: some View {
        ZStack(alignment: .topLeading) {
            MissionTriangle().stroke(isSelected ? Ink.mission.emblemSelected : Ink.line.contour, lineWidth: Stroke.emblem)
                .frame(width: Size.mission.triangleWidth, height: Size.mission.triangleHeight)
                .padding(.leading, Size.mission.triangleLeft).padding(.top, Size.mission.triangleTop)
            glyph.foregroundStyle(isSelected ? Ink.text.primary : Ink.text.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: -Size.mission.glyphRise)
        }
        .frame(width: Size.mission.column, height: Size.mission.height)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var glyph: some View {
        switch source {
        case .trismegistus: Text(verbatim: "T").typeRole(.callout, weight: .semibold)
        case .telegram: Image(systemName: Symbol.kindTelegram).font(.system(size: Icon.mission))
        case .cli: Image(systemName: Symbol.kindTerminal).font(.system(size: Icon.mission))
        case .cron: Image(systemName: Symbol.clock).font(.system(size: Icon.mission))
        }
    }

    private var bar: Color {
        switch state {
        case .running: Ink.selection
        case .approval: Ink.marker
        case .failed: Ink.status.error
        case .done: Ink.status.ok
        case nil: Ink.line.contour
        }
    }

    /// The fill with its shadow (on the fill alone: on a stack it is one per child), the selection's wash and stripes,
    /// and the state's bar, inside the corners.
    private var ground: some View {
        ZStack(alignment: .leading) {
            Self.shape.fill(isSelected || isHovered ? Ink.surface.raised : Ink.mission.card)
                .shadow(isSelected ? Shadow.missionSelected : isHovered ? Shadow.missionHover : Shadow.none)
            Group {
                if isSelected {
                    Hatch.across(Size.mission.stripePitch).stroke(Ink.mission.stripe, lineWidth: Stroke.hairline)
                    LinearGradient(stops: [.init(color: Ink.mission.wash, location: 0),
                                           .init(color: Ink.mission.washMid, location: Size.mission.washMid / Size.mission.wash),
                                           .init(color: Ink.mission.washMid.opacity(0), location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: Size.mission.wash)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Rectangle().fill(bar).frame(width: Stroke.mark).frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(Self.shape)
        }
    }

    /// A rule hairline; contour under the pointer; selected a 1.5 pt ink frame with a 0.5 pt ink ring outside it.
    @ViewBuilder private var edge: some View {
        if isSelected {
            ZStack {
                Self.shape.strokeBorder(Ink.line.strong, lineWidth: Stroke.selection)
                Self.shape.stroke(Ink.line.strong, lineWidth: Stroke.hairline)
            }
        } else {
            Self.shape.strokeBorder(isHovered ? Ink.line.contour : Ink.line.rule, lineWidth: Stroke.hairline)
        }
    }
}

public extension View {
    /// A mission card's cell in the list column (#72): 10 pt in from the column's sides (macOS keeps 8 of them), the
    /// pill's room above the card and the rest of the 12 pt gap under it (a `List` clips each row); the selected card's
    /// cell is 8 pt taller under it for its shadow.
    func missionCell(isSelected: Bool = false) -> some View {
        padding(.horizontal, Size.mission.inset - Space.s)
            .padding(.top, Size.statePill.rise)
            .padding(.bottom, MissionCard.below + (isSelected ? Space.s : 0))
            .background { SelectionMargins(isSelected: isSelected) }
    }
}

extension MissionCard {
    /// What a cell leaves under its card: the 12 pt gap less the pill's room above the next one.
    static let below = Size.mission.gap - Size.statePill.rise
}

/// The state on a mission card's top edge: 19 pt, radius 10, a soft shadow. RUN yellow with an ink ring, the clock and
/// the run's time; APPROVAL magenta with ink text; FAILED and DONE white with a red cross or a green check.
struct StatePill: View {
    let state: StickerState
    let time: String?

    private static let shape = RoundedRectangle(cornerRadius: Radius.statePill, style: .continuous)

    var body: some View {
        HStack(spacing: Size.statePill.gap) {
            if state == .running {
                Image(systemName: Symbol.clock).font(.system(size: Icon.sticker, weight: .semibold))
                Text(verbatim: time ?? "").typeRole(.statePill).monospacedDigit()
            } else {
                StickerGlyph(state: state).fill(state == .approval ? Ink.text.primary : state.mark)
                    .frame(width: Size.sticker.glyph, height: Size.sticker.glyph)
                Text(state.word).typeRole(.statePill)
            }
        }
        .foregroundStyle(Ink.text.primary)
        .lineLimit(1).fixedSize()
        .padding(.leading, Size.statePill.leading).padding(.trailing, Size.statePill.trailing)
        .frame(height: Size.statePill.height)
        .background {
            Self.shape.fill(state == .running ? Ink.selection : state == .approval ? Ink.marker : Ink.surface.raised)
                .shadow(Shadow.statePill)
        }
        .overlay {
            if state == .running { Self.shape.inset(by: -Stroke.hairline).strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline) }
        }
        .accessibilityHidden(true)
    }
}

/// The emblem's triangle, point down: the prototype's `M3 4h18l-9 16z` on a 24 pt grid, fitted into the rect.
struct MissionTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        let grid: CGFloat = 24
        let scale = min(rect.width, rect.height) / grid
        let x = rect.midX - grid * scale / 2, y = rect.midY - grid * scale / 2
        return Path { p in
            p.move(to: CGPoint(x: x + 3 * scale, y: y + 4 * scale))
            p.addLine(to: CGPoint(x: x + 21 * scale, y: y + 4 * scale))
            p.addLine(to: CGPoint(x: x + 12 * scale, y: y + 20 * scale))
            p.closeSubpath()
        }
    }
}

#Preview("Mission cards") {
    VStack(spacing: 0) {
        MissionCard(name: "The briefing project", source: .trismegistus, activity: "3 h", preview: "Outline v2: 6 sections, sources linked").missionCell()
        MissionCard(name: "Swift app", source: .trismegistus, activity: "now", preview: "Checking the sidebar", isSelected: true, isPinned: true, runElapsed: "00:38").missionCell(isSelected: true)
        MissionCard(name: "Android app", source: .telegram, activity: "2 h", preview: "Wants to run ./gradlew assembleRelease", needsApproval: true).missionCell()
        MissionCard(name: "Morning news digest", source: .cron, activity: "9 h", preview: "07:00 digest", isReadOnly: true, finished: .done).missionCell()
    }
    .frame(width: 520).background(Ink.surface.sidebarSolid)
}
