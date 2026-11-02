import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window's sections (#41): order, shortcuts, where each keeps its selection, and where an opened id lands.
final class SectionBarTests: XCTestCase {
    func testOrderShortcutsAndTooltips() {
        XCTAssertEqual(WindowSection.allCases, [.chat, .github, .news, .agents, .jobs, .commands])
        XCTAssertEqual(WindowSection.allCases.map(\.key.character), ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(WindowSection.chat.help, "Chat (⌘1)")
        XCTAssertEqual(WindowSection.commands.help, "Commands (⌘6)")
    }

    func testEachSectionKeepsItsOwnSelection() {
        let keys = WindowSection.allCases.map(\.selectionKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        // Chat keeps the key the window used before sections, so the open conversation survives the update.
        XCTAssertEqual(WindowSection.chat.selectionKey, "window.selectedSession")
        XCTAssertEqual(WindowSection.jobs.selectionKey, "window.selection.jobs")
        XCTAssertFalse(keys.contains("window.section"))
    }

    func testOpeningLandsInChatOrNews() {
        XCTAssertEqual(WindowSection.opening("20261101_120000_ab12", newsID: "trismegistus.news"), .chat)
        XCTAssertEqual(WindowSection.opening("trismegistus.news", newsID: "trismegistus.news"), .news)
    }

    func testKeptSelection() {
        XCTAssertEqual(WindowSection.kept("b", in: ["a", "b"]), "b")
        XCTAssertEqual(WindowSection.kept("gone", in: ["a", "b"]), "a")
        XCTAssertEqual(WindowSection.kept(nil, in: ["a"]), "a")
        XCTAssertNil(WindowSection.kept("a", in: []))
    }
}
