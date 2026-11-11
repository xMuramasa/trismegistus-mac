import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window's chat entries as Endfield mission cards (#72, design 13 `#a3-c2`, `#a3-c-states`, renders `15b-*` and
/// `15-a3-chat-entries-states`). Writes `A3-Mission*.png` beside the other a3 snapshots.
extension WindowA3Tests {
    /// A card in its cell at the list column's width (520 less the List's 8 pt margins), as the list lays it.
    private static func cell(_ card: MissionCard, selected: Bool = false, hover: Bool = false) -> some View {
        card.missionCell(isSelected: selected).environment(\.rowHovered, hover)
            .frame(width: 504).padding(.horizontal, Space.s)
    }

    /// `#a3-c-states`, top to bottom; the tagged one shows no tags (they stay in the filter and the detail header).
    static var missionStates: some View {
        VStack(spacing: 0) {
            cell(MissionCard(name: "The briefing project", source: .trismegistus, activity: "3 h", preview: "Outline v2: 6 sections, sources linked"))
            cell(MissionCard(name: "Mage-sys", source: .trismegistus, activity: "yesterday", preview: "Migration plan: 3 tables, no downtime"), hover: true)
            cell(MissionCard(name: "Swift app", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running",
                             isSelected: true, isPinned: true, runElapsed: "00:38"), selected: true)
            cell(MissionCard(name: "Swift app — second run", source: .trismegistus, activity: "now", preview: "Checking the sidebar with cua-driver, 2 tools running", runElapsed: "04:12"))
            cell(MissionCard(name: "Android app", source: .trismegistus, activity: "2 h", preview: "Wants to run ./gradlew assembleRelease", isPinned: true, needsApproval: true))
            cell(MissionCard(name: "Workflow refiner", source: .trismegistus, activity: "2 d", preview: "Step 4 timed out after 120 s", isPinned: true, finished: .failed))
            cell(MissionCard(name: "Homepage project", source: .trismegistus, activity: "1 h", preview: "Build passes; preview deployed for review", finished: .done))
            cell(MissionCard(name: "Trismegistus", source: .trismegistus, activity: "1 h", preview: "Relay handshake passes on macbook, pixel and ipad", isPinned: true))
            cell(MissionCard(name: "Morning news digest", source: .cron, activity: "9 h", preview: "07:00 digest: 12 items, 3 flagged for you", isReadOnly: true))
            cell(MissionCard(name: "xMuramasa/homelab#1: Add the Trismegistus relay", source: .trismegistus, activity: "1 h", preview: "Relay config drafted, PR waiting for your review"))
        }
    }

    func testMissionCardsInEveryState() throws {
        let pitch = Size.statePill.rise + Size.mission.height + MissionCard.below
        let heights = (0..<10).map { $0 == 2 ? pitch + Space.s : pitch }
        let shot = try flat("MissionCards", width: 520, height: heights.reduce(0, +), ground: Ink.surface.sidebarSolid) { Self.missionStates }
        let tops = heights.indices.map { heights[..<$0].reduce(0, +) + Size.statePill.rise }
        let left = Size.mission.inset, right = 520 - Size.mission.inset, mid = Size.mission.height / 2

        // 56 pt, 12 pt apart, 10 pt in from the list's sides; the selected cell 8 pt deeper for its shadow.
        XCTAssertEqual(fitting(MissionCard(name: "a", source: .trismegistus, activity: "now").frame(width: 500)).height, Size.mission.height)
        XCTAssertEqual(fitting(MissionCard(name: "a", source: .trismegistus, activity: "now").missionCell().frame(width: 504)).height, pitch)
        XCTAssertEqual(pitch, Size.mission.height + Size.mission.gap)
        XCTAssertTrue(shot.isColor(left - 1, tops[0] + mid, Ink.surface.sidebarSolid, tolerance: 0.02), "10 pt in")
        XCTAssertTrue(shot.isColor(right + 1, tops[0] + mid, Ink.surface.sidebarSolid, tolerance: 0.02), "10 pt in on the right")

        // The 3 pt bar at the left edge in the state's colour, contour with none.
        let bars: [Color] = [Ink.line.contour, Ink.line.contour, Ink.selection, Ink.selection, Ink.marker, Ink.status.error, Ink.status.ok,
                             Ink.line.contour, Ink.line.contour, Ink.line.contour]
        for (i, bar) in bars.enumerated() {
            XCTAssertTrue(shot.isColor(left + 2.25, tops[i] + mid, bar, tolerance: 0.06), "card \(i): its bar \(shot.rgb(left + 2.25, tops[i] + mid))")
            XCTAssertFalse(shot.isColor(left + 4, tops[i] + mid + 20, bar, tolerance: 0.02), "card \(i): 3 pt")
        }

        // Idle: white at 90 % over the list, a rule hairline; the contour triangle, the rule divider, the hatch.
        XCTAssertLessThan(shot.light(420, tops[0] + mid), shot.light(420, tops[1] + mid) - 0.003, "idle is 90 % white, hover white")
        XCTAssertTrue(shot.contains(Ink.line.contour, in: CGRect(x: left + Size.mission.triangleLeft, y: tops[0] + Size.mission.triangleTop, width: Size.mission.triangleWidth, height: 6)), "the triangle")
        XCTAssertTrue(shot.isColor(left + Size.mission.column + 0.5, tops[0] + mid, Ink.line.rule, tolerance: 0.04), "the divider")
        XCTAssertFalse(shot.isColor(left + Size.mission.column + 0.5, tops[0] + 6, Ink.line.rule, tolerance: 0.02), "a 22 pt divider")
        let hatch = CGRect(x: right - Size.mission.sideInset - Size.mission.hatchWidth, y: tops[0] + Size.mission.height - Size.mission.sideBottom - Size.mission.hatchHeight,
                           width: Size.mission.hatchWidth, height: Size.mission.hatchHeight)
        XCTAssertTrue(shot.contains(Ink.line.contour, in: hatch), "the hatch under the age")

        // Hovered: white with a contour edge.
        XCTAssertTrue(shot.isColor(420, tops[1] + mid, Ink.surface.raised, tolerance: 0.01), "hover is white")
        XCTAssertTrue(shot.isColor(300, tops[1] + 0.5, Ink.line.contour, tolerance: 0.06), "hover's contour edge \(shot.rgb(300, tops[1] + 0.5))")

        // Selected: the ink frame, the yellow wash from the left gone by 150 pt, the ink divider.
        let sel = tops[2]
        XCTAssertLessThan(shot.light(300, sel + 0.75), 0.3, "the ink frame")
        XCTAssertLessThan(shot.light(300, sel - 0.25), 0.8, "its 0.5 pt ring outside")
        let wash = shot.rgb(left + 30, sel + 50)
        XCTAssertTrue(wash[0] > 0.9 && wash[2] < 0.6, "the yellow wash \(wash)")
        let past = shot.rgb(left + 200, sel + 50)
        XCTAssertTrue(past[2] > 0.85, "white past the wash \(past)")
        XCTAssertLessThan(shot.light(left + Size.mission.column + 0.5, sel + mid), shot.light(left + Size.mission.column + 0.5, tops[0] + mid) - 0.05, "the divider in ink")

        // The state pill on the top edge, its top 10 pt above the card, 10 pt in from the right.
        func pill(_ i: Int) -> CGRect { CGRect(x: right - Size.statePill.inset - 60, y: tops[i] - Size.statePill.rise, width: 60, height: Size.statePill.rise - 2) }
        XCTAssertTrue(shot.contains(Ink.selection, in: pill(3)), "RUN's yellow pill")
        XCTAssertTrue(shot.contains(Ink.text.primary, in: pill(3).insetBy(dx: 0, dy: -4), tolerance: 0.15), "RUN's ink ring and time")
        XCTAssertTrue(shot.contains(Ink.marker, in: pill(4)), "APPROVAL's magenta pill")
        XCTAssertTrue(shot.contains(Ink.status.error, in: pill(5).insetBy(dx: -20, dy: -6), tolerance: 0.1), "FAILED's red cross")
        XCTAssertTrue(shot.contains(Ink.status.ok, in: pill(6).insetBy(dx: -20, dy: -6), tolerance: 0.1), "DONE's green check")
        XCTAssertTrue(shot.contains(Ink.selection, in: pill(2)), "the selected run's pill")
        XCTAssertFalse(shot.isColor(right - Size.statePill.inset + 2, tops[3] - 5, Ink.selection, tolerance: 0.1), "10 pt in from the right")
        for i in [0, 1, 7, 8, 9] {
            XCTAssertFalse(shot.contains(Ink.selection, in: pill(i)) || shot.contains(Ink.marker, in: pill(i)), "card \(i): no pill")
        }
        XCTAssertEqual(fitting(StatePill(state: .running, time: "00:38")).height, Size.statePill.height)
        let widths = ["00:11", "00:88", "11:11", "59:00"].map { fitting(StatePill(state: .running, time: $0)).width }
        XCTAssertEqual(Set(widths).count, 1, "tabular figures: \(widths)")
    }

    func testSpokenMissionCard() {
        let card = MissionCard(name: "Android app", source: .trismegistus, activity: "2 h", isReadOnly: true, isPinned: true, needsApproval: true)
        XCTAssertEqual(card.spoken, "Android app, approval waiting, 2 h, read-only, pinned")
        XCTAssertEqual(MissionCard(name: "Swift app", source: .trismegistus, activity: "now", runElapsed: "00:38", needsApproval: true).state, .approval, "approval wins")
        XCTAssertEqual(MissionCard(name: "Swift app", source: .trismegistus, activity: "now", runElapsed: "00:38", finished: .done).state, .running, "a run wins over done")
    }

    func testChatGroupHeads() throws {
        let heads = VStack(spacing: 0) {
            InProgressHead()
            MissionGroupHead(title: "Pinned", count: 2, symbol: Symbol.pinOutline)
            MissionGroupHead(title: "Conversations", count: 9, symbol: Symbol.kindOther, isFirst: true)
        }
        .frame(width: 504).padding(.horizontal, Space.s)
        let progress = Size.missionHead.first + Size.missionHead.progress + Size.missionHead.afterProgress - Size.statePill.rise
        let pinned = Size.missionHead.between - MissionCard.below + Size.missionHead.height + Size.missionHead.after - Size.statePill.rise
        let first = Size.missionHead.first + Size.missionHead.height + Size.missionHead.after - Size.statePill.rise
        XCTAssertEqual(fitting(InProgressHead().frame(width: 504)).height, progress)
        XCTAssertEqual(fitting(MissionGroupHead(title: "Pinned", count: 2, symbol: Symbol.pinOutline).frame(width: 504)).height, pinned)
        XCTAssertEqual(fitting(MissionGroupHead(title: "Pinned", count: 2, symbol: Symbol.pinOutline, isFirst: true).frame(width: 504)).height, first)
        let shot = try flat("MissionHeads", width: 520, height: progress + pinned + first, ground: Ink.surface.sidebarSolid) { heads }
        let inset = Space.m

        // In progress: a contour hairline to the label's left, the label at the right, the yellow bracket with its ink edge.
        let line = Size.missionHead.first + Size.missionHead.progress / 2
        XCTAssertTrue(shot.contains(Ink.line.contour, in: CGRect(x: 100, y: line - 1, width: 200, height: 2), tolerance: 0.03), "In progress's hairline")
        XCTAssertTrue(shot.contains(Ink.text.secondary, in: CGRect(x: 380, y: line - 6, width: 120, height: 12), tolerance: 0.12), "the label at the right")
        XCTAssertTrue(shot.contains(Ink.selection, in: CGRect(x: 520 - inset - Size.missionHead.bracketWidth, y: line - 7, width: Size.missionHead.bracketWidth, height: 14)), "the yellow bracket")
        XCTAssertLessThan(shot.light(520 - inset + 0.5, line), 0.4, "its ink edge")

        // Pinned: the 22 pt yellow square with an ink ring, the label in ink, the hairline from the label to the edge.
        let square = progress + Size.missionHead.between - MissionCard.below + (Size.missionHead.height - Size.missionHead.mark) / 2
        XCTAssertTrue(shot.isColor(inset + 1.5, square + 3, Ink.selection, tolerance: 0.06), "the yellow square \(shot.rgb(inset + 1.5, square + 3))")
        XCTAssertTrue(shot.isColor(inset + Size.missionHead.mark - 1.5, square + Size.missionHead.mark - 3, Ink.selection, tolerance: 0.06), "22 pt")
        XCTAssertLessThan(shot.light(inset - 0.5, square + 11), 0.4, "its ink ring")
        XCTAssertTrue(shot.contains(Ink.text.primary, in: CGRect(x: inset + Size.missionHead.mark + 4, y: square, width: 80, height: 22), tolerance: 0.15), "the label")
        let rule = progress + pinned - 0.5
        XCTAssertTrue(shot.isColor(300, rule, Ink.line.contour, tolerance: 0.04), "the hairline under the head")
        XCTAssertFalse(shot.isColor(inset + 10, rule, Ink.line.contour, tolerance: 0.02), "from the label's start")
    }

    /// `#a3-c2` in a real List: In progress on top (approval, then the run), each pill whole above its card in the
    /// card's own row, 12 pt between cards.
    func testChatListWithInProgress() throws {
        struct Column: View {
            @State var selection: String? = "swift"
            var body: some View {
                List(selection: $selection) {
                    WindowA3Tests.chatRows { id, build in build(selection == id).missionCell(isSelected: selection == id).tag(id).sidebarRow() }
                }
                .sidebarList()
                .environment(\.onSidebar, true)
            }
        }
        let shot = try shot("MissionList", width: 520, height: 900, ground: Ink.surface.sidebarSolid) { Column() }
        let bar = Size.mission.inset + 2.25
        // Card tops: the first coloured pixel of a bar is under the card's edge (a hairline, the selected one's ink frame).
        let approval = try XCTUnwrap(shot.first(Ink.marker, x: bar, ys: stride(from: CGFloat(0), to: 300, by: 0.5)), "the approval card's bar") - Stroke.hairline
        let pillX = 520 - Size.mission.inset - Size.statePill.inset - 12
        let approvalPill = try XCTUnwrap(shot.first(Ink.marker, x: pillX, ys: stride(from: CGFloat(0), to: 300, by: 0.5)), "the approval pill")
        XCTAssertEqual(approval - approvalPill, Size.statePill.rise, accuracy: 1.5, "the pill's top 10 pt above the card, not clipped")
        let run = try XCTUnwrap(shot.first(Ink.selection, x: bar, ys: stride(from: approval + 2, to: 600, by: 0.5)), "the running card's bar") - Stroke.selection
        XCTAssertEqual(run - approval, Size.mission.height + Size.mission.gap, accuracy: 1.5, "approval first, 12 pt above the run")
        let runPill = try XCTUnwrap(shot.first(Ink.selection, x: pillX, ys: stride(from: approval + Size.mission.height, to: 600, by: 0.5)), "the run's pill")
        XCTAssertEqual(run - runPill, Size.statePill.rise, accuracy: 1.5, "the run's pill above its card")
        // The List's selection highlight never shows round the selected card: its pill room left of the pill and the
        // gap under it stay the column's ground (the card's soft shadow darkens it by under 3 %; the band was 8 %).
        for (x, y) in [(CGFloat(120), run - Size.statePill.rise / 2), (CGFloat(120), run + Size.mission.height + Space.s / 2),
                       (CGFloat(4), run + Size.mission.height / 2)] {
            XCTAssertTrue(shot.isColor(x, y, Ink.surface.sidebarSolid, tolerance: 0.035), "the ground at (\(x), \(y)), not a selection band")
        }
        // Pinned's yellow square under the selected card's deeper cell.
        let square = try XCTUnwrap(shot.first(Ink.selection, x: Space.m + 2, ys: stride(from: run + Size.mission.height + 2, to: 800, by: 0.5)), "Pinned's square")
        let expected = Size.mission.height + MissionCard.below + Space.s + Size.missionHead.between - MissionCard.below + (Size.missionHead.height - Size.missionHead.mark) / 2
        XCTAssertEqual(square - run, expected, accuracy: 2, "14 pt between the groups")
    }
}
