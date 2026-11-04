import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The inline styling of `MarkdownView`'s text (#58). The blocks' layout is in `.build/snapshots/MarkdownView.png`.
final class MarkdownViewTests: XCTestCase {
    private func runs(_ markdown: String) -> [(text: String, link: URL?, chip: Bool)] {
        let styled = MarkdownText.styled(markdown)
        return styled.runs.map { (String(styled[$0.range].characters), $0.link, $0.swiftUI.backgroundColor != nil) }
    }

    func testPlainTextStaysAsWritten() {
        XCTAssertEqual(String(MarkdownText.styled("a\nb").characters), "a\nb")
        XCTAssertEqual(runs("just text").map(\.text), ["just text"])
    }

    func testInlineCodeIsAChip() {
        let code = runs("run `cua-driver stop` now").filter(\.chip)
        XCTAssertEqual(code.map(\.text).joined().trimmingCharacters(in: .whitespaces), "cua-driver stop")
    }

    func testBareURLIsALinkAndLeavesTheFullStopOut() {
        let link = runs("see https://example.test/a?b=1. Then").first { $0.link != nil }
        XCTAssertEqual(link?.text, "https://example.test/a?b=1")
        XCTAssertEqual(link?.link, URL(string: "https://example.test/a?b=1"))
    }

    func testURLInBackticksIsALinkNotAChip() {
        XCTAssertEqual(runs("`https://example.test/x`").first?.link, URL(string: "https://example.test/x"))
        XCTAssertFalse(runs("`https://example.test/x`").contains(where: \.chip))
    }

    func testNamedLinkKeepsItsWords() {
        let link = runs("[the issue](https://example.test/1)").first { $0.link != nil }
        XCTAssertEqual(link?.text, "the issue")
    }

    func testAURLInsideCodeWithOtherTextStaysCode() {
        XCTAssertFalse(runs("`curl https://example.test`").contains { $0.link != nil })
    }

    /// `Text` has to draw the attribute: the chip's ground is on screen, not only in the string.
    @MainActor func testTheChipsGroundIsDrawn() throws {
        let host = NSHostingView(rootView: Text(MarkdownText.styled("`chip`")).padding(Space.m).background(Ink.surface.raised))
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let sunken = try XCTUnwrap(NSColor(Ink.surface.sunken).usingColorSpace(.sRGB))
        var found = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), abs(c.redComponent - sunken.redComponent) < 0.02 { found += 1 }
            }
        }
        XCTAssertGreaterThan(found, 100)
    }

    func testBoldDropsItsIntentForTheFace() {
        let styled = MarkdownText.styled("**lead:** rest")
        XCTAssertTrue(styled.runs.allSatisfy { ($0.inlinePresentationIntent ?? []).isEmpty })
        XCTAssertNotNil(styled.runs.first?.swiftUI.font)
    }
}
