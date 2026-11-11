import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// Run alerts (#66): the menu bar glyph's cross and check, and Settings' Notifications table.
@MainActor
final class RunAlertTests: XCTestCase {
    /// The glyph drawn at 1x into a 22×18 bitmap; the alpha of pixel (x, y) from the top left.
    private func alpha(_ state: GlyphState, _ x: Int, _ y: Int) throws -> CGFloat {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 22, pixelsHigh: 18, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        MenuBarGlyph.image(state).draw(in: NSRect(x: 0, y: 0, width: 22, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        return rep.colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    func testFailedAndDoneMarkTheGlyphByShape() throws {
        // Top right, where the approval dot sits: the cross and the check draw there, idle and a run leave it empty.
        for state in [GlyphState.failed, .done, .approval] {
            XCTAssertGreaterThan(try alpha(state, 19, 4), 0, "\(state) marks the top right")
        }
        for state in [GlyphState.idle, .running, .disconnected] {
            XCTAssertEqual(try alpha(state, 19, 4), 0, "\(state) leaves the top right empty")
        }
        // The cross reaches the top left of the mark's corner; the check doesn't: two shapes, not one.
        XCTAssertGreaterThan(try alpha(.failed, 17, 1), 0)
        XCTAssertEqual(try alpha(.done, 17, 1), 0)
        // The mark itself is the idle one.
        XCTAssertGreaterThan(try alpha(.failed, 4, 10), 0)
        XCTAssertGreaterThan(try alpha(.done, 4, 10), 0)
    }

    private struct Table: View {
        @State var banners = [true, true, false]
        @State var sounds = ["Default", "Glass", "None"]
        var played: (String) -> Void = { _ in }

        var body: some View {
            NotificationTable(rows: ["Approval requests", "Run finished", "Run failed"].enumerated().map { i, title in
                NotificationTable.Row(id: title, title: title, banner: $banners[i], sound: $sounds[i])
            }, onPlay: played)
            .padding(Space.l)
            .frame(width: Size.settings.width)
            .background(Ink.surface.window)
        }
    }

    func testTheNotificationTableFitsTheSettingsWindow() throws {
        let host = NSHostingView(rootView: Table())
        host.appearance = NSAppearance(named: .aqua)
        host.frame.size = host.fittingSize
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, Size.settings.width, "no column pushes the window wider")
        // The head's words fit their columns (BANNER was cut to "BANN…" at 44 pt).
        for (word, column) in [("Banner", Size.settings.banner), ("Sound", Size.settings.sound)] {
            XCTAssertLessThanOrEqual(NSHostingView(rootView: Text(word).typeRole(.label)).fittingSize.width, column, "\(word) fits its column")
        }
        // Head, three rows with their rules, the foot bar, the two captions: well within the window with the other sections.
        let table = Size.settings.head + 3 * (Size.settings.row + Stroke.hairline) + Size.settings.foot
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, table + 2 * Space.l)
        XCTAssertLessThan(host.fittingSize.height, Size.settings.height / 2)
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: SnapshotTests.directory, withIntermediateDirectories: true)
        try png.write(to: SnapshotTests.directory.appendingPathComponent("SettingsNotifications.png"))
    }

    func testTheSoundMenuHasNoneDefaultAndTheFourteenSystemSounds() {
        XCTAssertEqual(NotificationTable.systemSounds.count, 14)
        XCTAssertEqual(Set(NotificationTable.systemSounds).count, 14)
        XCTAssertFalse(NotificationTable.systemSounds.contains(NotificationTable.none))
        XCTAssertFalse(NotificationTable.systemSounds.contains(NotificationTable.standard))
        XCTAssertTrue(NotificationTable.systemSounds.contains("Glass") && NotificationTable.systemSounds.contains("Basso"))
    }
}
