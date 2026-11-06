import AppKit
import CoreText
import XCTest

@testable import TrismegistusUI

/// The type roles draw in the bundled Inter and JetBrains Mono, never a fallback (#33).
final class FontTests: XCTestCase {
    func testEveryFaceIsBundledAndRegistered() throws {
        Fonts.register()
        for family in FontFamily.allCases {
            for (weight, name) in family.faces {
                let font = try XCTUnwrap(NSFont(name: name, size: 12), "\(name) (\(weight)) isn't registered")
                XCTAssertEqual(font.fontName, name)
                XCTAssertEqual(CTFontCopyFamilyName(font) as String, family.rawValue, name)
            }
        }
    }

    /// B2's ExtraBold and Black (#65): Inter has them, JetBrains Mono doesn't, so a heavy sibling of a mono role stays
    /// on the role's own face.
    func testInterHasExtraBoldAndBlack() throws {
        Fonts.register()
        XCTAssertEqual(FontFamily.ui.faces[800], "Inter-ExtraBold")
        XCTAssertEqual(FontFamily.ui.faces[900], "Inter-Black")
        XCTAssertNil(FontFamily.mono.faces[800])
        XCTAssertNil(FontFamily.mono.faces[900])
        XCTAssertEqual(TypeSpec.weights[.heavy], 800)
        XCTAssertEqual(TypeSpec.weights[.black], 900)
        for name in ["Inter-ExtraBold", "Inter-Black"] {
            let font = try XCTUnwrap(NSFont(name: name, size: 14), name)
            XCTAssertEqual(font.fontName, name)
        }
        _ = TypeRole.mono.spec.font(weight: .black)  // no face at 900: must not crash
    }

    func testEveryRoleResolvesToItsFamily() throws {
        for role in TypeRole.allCases {
            let spec = role.spec
            let name = try XCTUnwrap(spec.family.faces[spec.weight], "\(role): no face at \(spec.weight)")
            _ = spec.font()  // registers, as a view would
            let font = try XCTUnwrap(NSFont(name: name, size: spec.size), "\(role): \(name)")
            XCTAssertEqual(CTFontCopyFamilyName(font) as String, spec.family.rawValue, "\(role)")
        }
    }
}
