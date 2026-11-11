import SwiftUI
import XCTest

@testable import TrismegistusUI

/// Search (#76, design 18 in `design/opendesign/18-search/`): the hit cards (18a), the find bar and the marks in the
/// transcript (18c), and the states sheet. Writes `A3-Search*.png` beside the other a3 snapshots.
extension WindowA3Tests {
    /// A card in its cell at the list column's width, as the list lays it.
    private static func cell(_ card: MissionCard, selected: Bool = false) -> some View {
        card.missionCell(isSelected: selected).frame(width: 504).padding(.horizontal, Space.s)
    }

    private static func hit(_ name: String, _ time: String, _ hits: Int, _ snippet: String, source: SessionSource = .trismegistus,
                            pinned: Bool = false, selected: Bool = false) -> some View {
        let marks = snippet.ranges(of: /(?i)android/).map { NSRange($0, in: snippet) }
        return cell(MissionCard(name: name, source: source, activity: time, preview: snippet, isSelected: selected, isPinned: pinned,
                                hits: hits, marks: marks), selected: selected)
    }

    /// 18a, the list column for `android`: the title match under Conversations, then In messages and its hit cards.
    static var hitList: some View {
        VStack(spacing: 0) {
            MissionGroupHead(title: "Conversations", count: 1, symbol: Symbol.kindOther, isFirst: true).frame(width: 504).padding(.horizontal, Space.s)
            cell(MissionCard(name: "Android app", source: .trismegistus, activity: "6 d", preview: "Phone check list for the S21: pairing, chat, approvals"))
            SearchGroupHead(detail: "8 conversations").frame(width: 504).padding(.horizontal, Space.s)
            hit("Workflow refiner", "15:44", 5, "…plus Docker images for Swift, Gradle/JDK and the Android build. Not installed: Rust, Elixir, Deno, Java, or any C compiler…")
            hit("Swift app", "13:43", 11, "…trismegistus#28 (P1): push notifications to the Android app through ntfy. The Android app has its own items waiting for a…", pinned: true)
            hit("Android app", "6 d", 9, "…a hidden phone the size of your S21 FE, using the Android 37 image Android Studio had already installed. Your own…", selected: true)
            hit("Daily news", "7 d", 2, "…Google ships Android 17 QPR2 to Pixels; Samsung's One UI 9 beta adds…", source: .cron)
        }
    }

    func testHitCards() throws {
        let card = MissionCard(name: "a", source: .trismegistus, activity: "15:44", preview: "x", hits: 5)
        XCTAssertEqual(fitting(card.frame(width: 500)).height, Size.mission.hitHeight, "a hit card is 72 pt")
        XCTAssertEqual(card.hitCount, "5 hits")
        XCTAssertEqual(MissionCard(name: "a", source: .cron, activity: "now", hits: 1).hitCount, "1 hit")
        XCTAssertNil(MissionCard(name: "a", source: .cron, activity: "now").hitCount, "a list card has no count")
        XCTAssertEqual(MissionCard(name: "Swift app", source: .trismegistus, activity: "13:43", preview: "the Android app", hits: 11).spoken,
                       "Swift app, 13:43, 11 hits, the Android app")

        let head = Size.missionHead.first + Size.missionHead.height + Size.missionHead.after - Size.statePill.rise
        let pitch = Size.statePill.rise + Size.mission.height + MissionCard.below
        let between = Size.missionHead.between - MissionCard.below + Size.missionHead.height + Size.missionHead.after - Size.statePill.rise
        let hitPitch = Size.statePill.rise + Size.mission.hitHeight + MissionCard.below
        XCTAssertEqual(fitting(SearchGroupHead(detail: "8 conversations").frame(width: 504)).height, between, "the mission head's room")
        let shot = try shot("Search18a", width: 520, height: head + pitch + between + 4 * hitPitch + Space.s, ground: Ink.surface.sidebarSolid) { Self.hitList }
        let firstHit = head + pitch + between + Size.statePill.rise

        // In messages' yellow square with the search glyph, like the other heads.
        let square = head + pitch + Size.missionHead.between - MissionCard.below + (Size.missionHead.height - Size.missionHead.mark) / 2
        XCTAssertTrue(shot.isColor(Space.m + 1.5, square + 3, Ink.selection, tolerance: 0.06), "In messages' yellow square \(shot.rgb(Space.m + 1.5, square + 3))")

        // The hit card: 72 pt, the query's words light yellow in the two-line preview, the time over the count at the right.
        let left = Size.mission.inset, right = 520 - Size.mission.inset
        XCTAssertTrue(shot.isColor(left + 2.25, firstHit + Size.mission.hitHeight - 4, Ink.line.contour, tolerance: 0.06), "the bar runs 72 pt")
        XCTAssertFalse(shot.isColor(300, firstHit + Size.mission.hitHeight + 4, Ink.mission.card, tolerance: 0.005), "and stops there")
        let preview = CGRect(x: left + Size.mission.column + Space.m, y: firstHit + 24, width: 380, height: 40)
        XCTAssertTrue(contains(shot, in: preview) { $0[0] > 0.95 && $0[1] > 0.9 && (0.3...0.55).contains($0[2]) }, "a marked word, yellow at 60 %")
        XCTAssertTrue(contains(shot, in: CGRect(x: preview.minX, y: firstHit + 42, width: 380, height: 16)) { $0[2] < 0.5 },
                      "the preview's second line")
        let side = CGRect(x: right - Size.mission.hitColumn, y: firstHit + 10, width: Size.mission.hitColumn - Size.mission.sideInset, height: 52)
        XCTAssertTrue(shot.contains(Ink.text.secondary, in: side.insetBy(dx: 0, dy: 0), tolerance: 0.15), "the time and the count")
        XCTAssertFalse(shot.contains(Ink.line.contour, in: CGRect(x: right - 24, y: firstHit + 56, width: 14, height: 10), tolerance: 0.01),
                       "no hatch on a hit card")

        // The opened hit (18c): selected, the yellow wash from the left.
        let selected = firstHit + 2 * hitPitch
        let wash = shot.rgb(left + 30, selected + 60)
        XCTAssertTrue(wash[0] > 0.9 && wash[2] < 0.6, "the selected hit's wash \(wash)")
    }

    /// The states sheet's left column: searching, one character, nothing says it, the helper down, more than 50.
    func testSearchStates() throws {
        struct Sheet: View {
            var body: some View {
                VStack(alignment: .leading, spacing: 0) {
                    SearchGroupHead(detail: "… conversations", isFirst: true)
                    SearchNote("Searching messages…")
                    SearchNote("Type one more character to search inside messages.")
                    SearchGroupHead(detail: "0 conversations")
                    SearchNote("No message in any conversation says “zebra”.")
                    SearchGroupHead(detail: "— conversations")
                    SearchNote("Searching inside messages needs the agents helper on optiplex.", command: "systemctl --user start trismegistus-agents")
                    SearchNote("Showing the newest 50 matches. Add a word to narrow it.")
                    HStack { Spacer(); SearchSpinner() }.padding(Space.m)
                }
                .frame(width: 504).padding(.horizontal, Space.s)
            }
        }
        let shot = try shot("SearchStates", width: 520, height: 420, ground: Ink.surface.sidebarSolid) { Sheet() }
        // The helper's line in ink, its command under it in secondary.
        let helper = SearchNote("Searching inside messages needs the agents helper on optiplex.", command: "systemctl --user start trismegistus-agents")
        let plain = SearchNote("Searching messages…")
        XCTAssertGreaterThan(fitting(helper.frame(width: 504)).height, fitting(plain.frame(width: 504)).height + 12, "the command on its own line")
        XCTAssertTrue(shot.contains(Ink.text.primary, in: CGRect(x: 22, y: 0, width: 480, height: 420), tolerance: 0.1), "ink text")
        XCTAssertTrue(shot.isColor(Space.m + 1.5, Size.missionHead.first + 6, Ink.selection, tolerance: 0.06), "the first head's square")
    }

    /// A find bar in a host that owns its focus.
    private struct Bar: View {
        @State var query: String
        let status: FindBar.Status
        @FocusState private var focused: Bool

        var body: some View {
            var bar = FindBar(query: $query, status: status, focus: $focused, onPrevious: {}, onNext: {}, onClose: {})
            bar.forceFocused = true
            return bar
        }
    }

    func testFindBar() throws {
        XCTAssertEqual(fitting(Bar(query: "", status: .empty).frame(width: 720)).height, Size.find.bar)
        let rows: [(String, FindBar.Status)] = [("", .empty), ("emulator", .matches(current: 1, total: 4)), ("zebra", .none),
                                                ("android", .loading), ("android", .matches(current: 3, total: 9))]
        let shot = try shot("SearchFindBar", width: 720, height: CGFloat(rows.count) * (Size.find.bar + Space.s)) {
            VStack(spacing: Space.s) {
                ForEach(rows.indices, id: \.self) { i in Bar(query: rows[i].0, status: rows[i].1) }
            }
        }
        func top(_ i: Int) -> CGFloat { CGFloat(i) * (Size.find.bar + Space.s) }
        // White at 88 % with a rule hairline under it; the field's ink edge; the count left of the arrows.
        XCTAssertTrue(shot.isColor(600, top(0) + Size.find.bar - 0.5, Ink.line.rule, tolerance: 0.05), "the rule under the bar")
        let fieldTop = top(1) + (Size.find.bar - Size.control) / 2
        XCTAssertLessThan(shot.light(Space.l + 100, fieldTop + 0.5), 0.3, "the field's ink edge while focused")
        let count = CGRect(x: Space.l + Size.find.field + Space.s, y: top(2) + 12, width: Size.find.count, height: 20)
        XCTAssertTrue(shot.contains(Ink.status.error, in: count, tolerance: 0.12), "No matches in terminal red")
        XCTAssertFalse(shot.contains(Ink.status.error, in: count.offsetBy(dx: 0, dy: top(1) - top(2)), tolerance: 0.12), "1 of 4 is grey")
        XCTAssertEqual(FindBar.count(.matches(current: 3, total: 9)), "3 of 9")
        XCTAssertEqual(FindBar.count(.loading), "Loading earlier messages…")
        XCTAssertEqual(FindBar.count(.empty), "")
    }

    /// 18c's transcript: every match light yellow, the current one solid with an ink underline, its message with the
    /// 3 pt yellow edge; a user message with marks keeps its box.
    func testMarksInTheTranscript() throws {
        let answer: [MarkdownPart<Int>] = [
            .prose(MarkdownText.styled("A hidden phone the size of your S21 FE, using the Android 37 image Android Studio had already installed.", role: .message)),
            .code(language: "bash", text: "$ emulator -avd android_37"),
        ]
        let words = FindMarks(query: "android")
        XCTAssertEqual(words.count(in: answer), 3, "two in the prose, one in the code")
        let shot = try shot("Search18c", width: 600, height: 260) {
            VStack(alignment: .leading, spacing: Space.xl) {
                MarkdownView(answer, role: .message) { _ in EmptyView() }
                    .padding(.horizontal, Space.m)
                    .findEdge(FindMarks(query: "android", current: 1))
                    .environment(\.findMarks, FindMarks(query: "android", current: 1))
                FindableUserText("does it run the android 36 image too?")
                    .environment(\.findMarks, FindMarks(query: "android"))
            }
            .environment(\.hairlineControls, true)
            .padding(Space.l)
        }
        let all = CGRect(x: 0, y: 0, width: 600, height: 260)
        XCTAssertTrue(contains(shot, in: all) { $0[0] > 0.95 && $0[1] > 0.9 && $0[2] < 0.1 }, "the current match, solid yellow")
        XCTAssertTrue(contains(shot, in: all) { $0[0] > 0.95 && $0[1] > 0.9 && (0.3...0.55).contains($0[2]) }, "the others light yellow")
        XCTAssertTrue(shot.isColor(Space.l + 1, Space.l + 8, Ink.find.current, tolerance: 0.05), "the message's yellow edge \(shot.rgb(Space.l + 1, Space.l + 8))")
        let user = CGRect(x: Space.l, y: 170, width: 560, height: 70)
        XCTAssertTrue(contains(shot, in: user) { $0[0] > 0.95 && (0.3...0.55).contains($0[2]) }, "your message's match")
        XCTAssertFalse(shot.isColor(Space.l + 1, 200, Ink.find.current, tolerance: 0.05), "no edge without the current match")
    }

    func testFindMatchingRules() {
        XCTAssertEqual(FindMarks.words(#"Android "image too" emul* AND NOT x"#), ["Android", "image too", "emul", "x"])
        let marks = FindMarks(query: "android image")
        XCTAssertEqual(marks.count(in: ["Android 37 image, android 36"]), 3, "case-insensitive, every occurrence")
        XCTAssertEqual(marks.count(in: ["Android only"]), 0, "every word must be there")
        XCTAssertEqual(marks.count(in: ["android", "an image"]), 2, "across the row's texts")
        XCTAssertEqual(FindMarks(query: "an and").count(in: ["android"]), 1, "overlapping words mark once")
        XCTAssertTrue(FindMarks(query: "  ").isEmpty)
        // The current match is counted from the row's first: a part after 2 matches has it at 0.
        XCTAssertEqual(FindMarks(query: "a", current: 2).after(2).current, 0)
        let marked = FindMarks(query: "an", current: 1).marked("an an an")
        let currentRuns = marked.runs.filter { $0.attributes.swiftUI.underlineStyle != nil }
        XCTAssertEqual(currentRuns.count, 1, "one current match")
        XCTAssertEqual(String(marked.characters[currentRuns[0].range]), "an")
        XCTAssertEqual(marked.characters.distance(from: marked.startIndex, to: currentRuns[0].range.lowerBound), 3, "the second one")
        let snippet = FindMarks.snippet("…the Android app", marks: [NSRange(location: 5, length: 7)])
        XCTAssertEqual(snippet.runs.filter { $0.attributes.swiftUI.backgroundColor != nil }.map { String(snippet.characters[$0.range]) }, ["Android"],
                       "the relay's UTF-16 marks, past the ellipsis")
    }

    /// Some pixel in the box passes `test` (its sRGB components).
    private func contains(_ shot: Shot, in box: CGRect, _ test: ([CGFloat]) -> Bool) -> Bool {
        stride(from: box.minX, to: box.maxX, by: 0.5).contains { x in stride(from: box.minY, to: box.maxY, by: 0.5).contains { y in test(shot.rgb(x, y)) } }
    }
}
