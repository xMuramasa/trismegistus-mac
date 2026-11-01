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
