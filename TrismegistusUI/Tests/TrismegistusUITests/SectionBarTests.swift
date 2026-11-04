import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The window's sections (#41, #57): order, shortcuts and where each keeps its selection.
final class SectionBarTests: XCTestCase {
    func testOrderShortcutsAndTooltips() {
        XCTAssertEqual(WindowSection.allCases, [.chat, .github, .agents, .jobs, .commands])
        XCTAssertEqual(WindowSection.allCases.map(\.key.character), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(WindowSection.chat.help, "Chat (⌘1)")
        XCTAssertEqual(WindowSection.commands.help, "Commands (⌘5)")
    }

    func testEachSectionKeepsItsOwnSelection() {
        let keys = WindowSection.allCases.map(\.selectionKey)
        XCTAssertEqual(Set(keys).count, keys.count)
        // Chat keeps the key the window used before sections, so the open conversation survives the update.
        XCTAssertEqual(WindowSection.chat.selectionKey, "window.selectedSession")
        XCTAssertEqual(WindowSection.jobs.selectionKey, "window.selection.jobs")
        XCTAssertFalse(keys.contains("window.section"))
    }

    /// `window.section` may still hold "news": with the raw value gone `@AppStorage` falls back to Chat.
    func testStoredNewsSectionIsGone() {
        XCTAssertNil(WindowSection(rawValue: "news"))
    }

    func testKeptSelection() {
        XCTAssertEqual(WindowSection.kept("b", in: ["a", "b"]), "b")
        XCTAssertEqual(WindowSection.kept("gone", in: ["a", "b"]), "a")
        XCTAssertEqual(WindowSection.kept(nil, in: ["a"]), "a")
        XCTAssertNil(WindowSection.kept("a", in: []))
    }
}
