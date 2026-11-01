import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// The roles added in #36 resolve to exactly what the views composed by hand before (no visible change).
final class InkRoleTests: XCTestCase {
    private func rgba(_ color: Color) throws -> [CGFloat] {
        let c = try XCTUnwrap(NSColor(color).usingColorSpace(.sRGB))
        return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
    }

    private func assertSame(_ role: Color, _ before: Color, _ name: String) throws {
        let (a, b) = (try rgba(role), try rgba(before))
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 0.0001, name) }
    }

    func testStatusRolesAreTheBrightPaletteColours() throws {
        try assertSame(Ink.status.warn, Palette.yellow, "status.warn")
        try assertSame(Ink.status.bad, Palette.red, "status.bad")
    }

    func testLineRolesAreOnSteelAtTheirOpacities() throws {
        try assertSame(Ink.line.onDark, Ink.text.onDark.opacity(Opacity.ruleOnDark), "line.onDark")
        try assertSame(Ink.line.outlineOnDark, Ink.text.onDark.opacity(Opacity.outlineOnDark), "line.outlineOnDark")
        XCTAssertEqual(try rgba(Ink.line.onDark)[3], 0.12, accuracy: 0.0001)
        XCTAssertEqual(try rgba(Ink.line.outlineOnDark)[3], 0.5, accuracy: 0.0001)
    }
}
