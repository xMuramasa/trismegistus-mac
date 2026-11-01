import AppKit
import SwiftUI
import XCTest

@testable import TrismegistusUI

/// Renders every view to `TrismegistusUI/.build/snapshots/<Name>.png` (scale 2, on paper) for comparison with the draft.
@MainActor
final class SnapshotTests: XCTestCase {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(".build/snapshots")

    private func snap<V: View>(_ name: String, width: CGFloat = 360, @ViewBuilder _ content: () -> V) throws {
        let view = content()
            .padding(16)
            .frame(width: width + 32, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.paper)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "\(name) did not render")
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try png.write(to: Self.directory.appendingPathComponent("\(name).png"))
        XCTAssertGreaterThan(image.width, 0)
    }

    func testPaletteMatchesDraft() {
        let ns = NSColor(Theme.yellow).usingColorSpace(.sRGB)!
        XCTAssertEqual(ns.redComponent, 1, accuracy: 0.001)
        XCTAssertEqual(ns.greenComponent, 250.0 / 255, accuracy: 0.001)
        XCTAssertEqual(ns.blueComponent, 0, accuracy: 0.001)
    }

    func testSVGPathParser() {
        let box = Path.svg(GlyphData.outer).boundingRect
        XCTAssertEqual(box, CGRect(x: 2, y: 2, width: 14, height: 14))
    }

    func testGlyphImagesAreTemplates() {
        for state in GlyphState.allCases {
            let image = MenuBarGlyph.image(state)
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 22, height: 18))
        }
    }

    func testButtons() throws {
        try snap("Buttons") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    EndfieldButton("Once", symbol: Symbol.check, kind: .primary) {}
                    EndfieldButton("Session", symbol: Symbol.clock) {}
                    EndfieldButton("Deny", symbol: Symbol.close, kind: .danger) {}
                    EndfieldButton("Copy", symbol: Symbol.copy, kind: .quiet) {}
                    EndfieldButton("Pair", symbol: Symbol.link) {}.disabled(true)
                }
                HStack {
                    ForEach([Symbol.check, Symbol.close, Symbol.clock, Symbol.copy, Symbol.plus, Symbol.send, Symbol.stop, Symbol.retry], id: \.self) {
                        EndfieldButton($0, symbol: $0, kind: .quiet, iconOnly: true) {}
                    }
                }
                // Pressed look: ink fill, yellow text.
                Text("SESSION").typeRole(.button).foregroundStyle(Theme.yellow)
                    .padding(.vertical, 6).padding(.horizontal, 12).background(Theme.ink)
            }
        }
    }

    func testFields() throws {
        var focused = EndfieldTextField("Message Hermes", text: .constant("Summarize the deploy log"))
        focused.forceFocused = true
        try snap("Fields") {
            VStack(spacing: 8) {
                EndfieldTextField("Message Hermes", text: .constant(""))
                focused
                EndfieldTextField("Code", text: .constant("K7QF-2M9X-A1"), isError: true)
                EndfieldTextField("Relay", text: .constant("hermes.lab.x-muramasa.dev")).disabled(true)
                HStack {
                    Toggle("On", isOn: .constant(true)).labelsHidden().endfieldSwitch()
                    Toggle("Off", isOn: .constant(false)).labelsHidden().endfieldSwitch()
                }
            }
        }
    }

    func testStatusAndHints() throws {
        try snap("StatusReadout") {
            VStack(alignment: .leading, spacing: 8) {
                StatusReadout(.linked, detail: "hermes.lab · 18 ms")
                StatusReadout(.reconnecting, detail: "retry in 4 s")
                StatusReadout(.offline, detail: "relay unreachable")
            }
        }
        try snap("KeyHintStrip") {
            VStack(spacing: 8) {
                KeyHint("⌘↩", "send")
                KeyHintStrip([("⌘↩", "send"), ("⌘.", "stop"), ("↩", "open")])
            }
        }
        try snap("TitleRule") { TitleRule("Trismegistus-mac // Controls") }
    }

    func testSessionRows() throws {
        try snap("SessionRowView", width: 320) {
            VStack(spacing: 1) {
                SessionRowView(name: "Homelab backup check", source: .telegram, activity: "2 h")
                SessionRowView(name: "trismegistus-mac UI draft", source: .trismegistus, activity: "now", isSelected: true)
                SessionRowView(name: "Endfield gallery render", source: .trismegistus, activity: "1 min", runElapsed: "00:42")
                SessionRowView(name: "Clean build cache", source: .cli, activity: "3 min", needsApproval: true)
                SessionRowView(name: "Morning news digest", source: .cron, activity: "9 h", isReadOnly: true)
            }
            .background(Theme.rule)
        }
    }

    func testToolRows() throws {
        try snap("ToolRowView", width: 320) {
            VStack(spacing: 8) {
                ToolRowView(tool: "terminal", summary: "ls ~/Projects", duration: "0.3 s", isExpanded: .constant(false))
                ToolRowView(
                    tool: "terminal", summary: "ls ~/Projects", duration: "0.3 s",
                    output: "endfield-dotfiles\nhomelab\ntrismegistus\ntrismegistus-mac", exitCode: 0, isExpanded: .constant(true))
                ToolRowView(
                    tool: "terminal", summary: "pytest -q tests/", duration: "4.8 s", exitCode: 1, isExpanded: .constant(false))
            }
        }
        try snap("SubagentRowView", width: 320) { SubagentRowView(name: "research", toolCount: 3, duration: "8.4 s") }
        try snap("RunMarker") {
            VStack(alignment: .leading, spacing: 8) {
                RunMarker(commands: 4, duration: "6.1 s", failed: 1)
                RunMarker(commands: 1, duration: "0.3 s")
            }
        }
    }

    func testBlocks() throws {
        try snap("CodeBlockView", width: 300) {
            CodeBlockView(language: "bash", code: "cd ~/Projects/homelab/penpot\ndocker compose up -d --wait")
        }
        try snap("WorkingIndicator", width: 300) { WorkingIndicator(detail: "00:42 · 3 tools") }
        try snap("ApprovalBannerView", width: 320) {
            ApprovalBannerView(
                tool: "terminal", command: "rm -rf ~/.cache/trismegistus-build",
                explanation: "Clear the stale build cache before the release build.", onChoice: { _ in })
        }
        try snap("TerminalEntryView") {
            VStack(alignment: .leading, spacing: 12) {
                TerminalEntryView(
                    title: "12:04:31 terminal", detail: "~/Projects/homelab", command: "ls ~/Projects",
                    output: "endfield-dotfiles\nhomelab", exitCode: 0, duration: 0.3, startsFolded: false)
                TerminalEntryView(title: "12:04:40 terminal", command: "pytest -q tests/", exitCode: 1, duration: 4.8)
                TerminalEntryView(title: "12:04:50 terminal", command: "sleep 30", isRunning: true, startedAt: .now)
                TerminalEntryView(
                    title: "12:05:02 terminal", command: "seq 40",
                    output: (1...40).map(String.init).joined(separator: "\n"), exitCode: 0, duration: 1.2,
                    startsFolded: false)
            }
        }
    }

    func testTerminalOutputPreview() {
        let lines = (1...40).map(String.init)
        let preview = TerminalEntryView.preview(lines.joined(separator: "\n"))
        XCTAssertEqual(preview?.text, lines.prefix(12).joined(separator: "\n"))
        XCTAssertEqual(preview?.hidden, 28)
        XCTAssertEqual(TerminalEntryView.preview(lines.joined(separator: "\n") + "\n")?.hidden, 28)
        // Twelve lines, with or without a final newline, show in full.
        XCTAssertNil(TerminalEntryView.preview(lines.prefix(12).joined(separator: "\n")))
        XCTAssertNil(TerminalEntryView.preview(lines.prefix(12).joined(separator: "\n") + "\n"))
        XCTAssertEqual(TerminalEntryView.preview(lines.prefix(13).joined(separator: "\n"))?.hidden, 1)
    }

    func testGlyphs() throws {
        try snap("MenuBarGlyph", width: 280) {
            HStack(spacing: 20) {
                ForEach(GlyphState.allCases, id: \.self) { state in
                    Image(nsImage: MenuBarGlyph.image(state)).renderingMode(.template).scaleEffect(2)
                        .frame(width: 44, height: 36)
                }
            }
            .foregroundStyle(Theme.ink)
        }
        try snap("SourceIcons", width: 200) {
            HStack(spacing: 16) {
                SourceIcon(.trismegistus)
                SourceIcon(.telegram)
                SourceIcon(.cron)
                SourceIcon(.cli)
            }
            .foregroundStyle(Theme.ink)
        }
    }
}
