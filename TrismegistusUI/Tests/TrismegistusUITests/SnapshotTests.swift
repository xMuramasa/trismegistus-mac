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
            .background(Palette.paper)
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
        let ns = NSColor(Palette.yellow).usingColorSpace(.sRGB)!
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
            for agents in [false, true] {
                let image = MenuBarGlyph.image(state, agents: agents)
                XCTAssertTrue(image.isTemplate)
                XCTAssertEqual(image.size, NSSize(width: 22, height: 18))
            }
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
                Text("SESSION").typeRole(.button).foregroundStyle(Palette.yellow)
                    .padding(.vertical, Space.s).padding(.horizontal, Space.m).background(Palette.ink)
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
            .background(Palette.rule)
        }
    }

    /// The window sidebar (09f): rows and the section bar on the grey ground, Jobs selected.
    func testSectionBar() throws {
        try snap("SectionBar", width: 260) {
            VStack(spacing: 0) {
                SessionRowView(name: "Daily AI news feed", source: .cron, activity: "14 h", isSelected: true)
                SessionRowView(name: "Daily Chile news feed", source: .cron, activity: "14 h")
                SessionRowView(name: "Endfield gallery render", source: .trismegistus, activity: "1 min", runElapsed: "00:42")
                SectionBar(selection: .constant(.jobs))
            }
            .environment(\.onSidebar, true)
            .background(Ink.surface.sidebar)
        }
    }

    /// The chat kind tabs (#48) under their header, on the 220 pt sidebar (188 pt of content), the 260 pt one (228 pt)
    /// and the popover's ground (380 pt): Telegram selected with its approval dot and a green one on Terminal; One-shots
    /// and All chosen under MORE; APP selected with the MORE mark.
    func testKindTabs() throws {
        let tabs = [KindChip(id: "app", title: "App", symbol: Symbol.kindApp, count: 4),
                    KindChip(id: "telegram", title: "Telegram", symbol: Symbol.kindTelegram, count: 4, mark: .approval),
                    KindChip(id: "terminal", title: "Terminal", symbol: Symbol.kindTerminal, count: 8, mark: .running)]
        let more = [KindChip(id: "oneshot", title: "One-shots", symbol: Symbol.kindOneShot, count: 6),
                    KindChip(id: "cron", title: "Cron", symbol: Symbol.clock, count: 0),
                    KindChip(id: "all", title: "All", symbol: Symbol.kindAll, count: 22)]
        func strips(sidebar: Bool) -> some View {
            let names = ["telegram": "Telegram", "oneshot": "One-shots", "all": "All", "app": "App"]
            let counts = ["telegram": 4, "oneshot": 6, "all": 22, "app": 4]
            return VStack(alignment: .leading, spacing: Space.m) {
                ForEach(["telegram", "oneshot", "all", "app"], id: \.self) { id in
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("\(names[id]!) // \(counts[id]!)").typeRole(.label)
                            .foregroundStyle(sidebar ? Ink.text.onSidebarSecondary : Ink.text.secondary)
                        KindTabs(tabs: tabs, more: more, moreMark: id == "app" ? .running : nil, selection: id) { _ in }
                    }
                }
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            .environment(\.onSidebar, sidebar)
            .background(sidebar ? Ink.surface.sidebar : Ink.surface.window)
        }
        // The sidebar's own padding (Space.l each side) is inside `strips`, so the widths are the sidebar's.
        try snap("KindTabs", width: 220) { strips(sidebar: true) }
        try snap("KindTabsWide", width: 260) { strips(sidebar: true) }
        try snap("KindTabsPopover", width: 380) { strips(sidebar: false) }
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

    /// The terminal pane's ground: ink with the contour lines in `sunken` (the app's pane uses opacity 0.3), cards on it.
    func testTerminalPaneGround() throws {
        try snap("TerminalPaneGround") {
            VStack(alignment: .leading, spacing: 12) {
                TerminalEntryView(title: "21:40:12 terminal", command: "git status", exitCode: 0, duration: 0.1)
                TerminalEntryView(
                    title: "21:40:15 terminal", detail: "~/Projects/homelab", command: "ls apps",
                    output: "homepage\nhindsight-ui\npenpot", exitCode: 0, duration: 0.2, startsFolded: false)
                TerminalEntryView(title: "21:41:02 read_file", command: "SPEC.md", exitCode: 0, duration: 0.0)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(height: 620)
            .background { EndfieldContours(color: Palette.sunken, opacity: 0.3).background(Palette.ink) }
            .padding(-16)
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
        try snap("MenuBarGlyph", width: 440) {
            HStack(spacing: 20) {
                ForEach(GlyphState.allCases, id: \.self) { state in
                    Image(nsImage: MenuBarGlyph.image(state)).renderingMode(.template).scaleEffect(2)
                        .frame(width: 44, height: 36)
                }
                // Background agents running: the dot at the bottom right (not with the run's bars).
                ForEach([GlyphState.idle, .approval], id: \.self) { state in
                    Image(nsImage: MenuBarGlyph.image(state, agents: true)).renderingMode(.template).scaleEffect(2)
                        .frame(width: 44, height: 36)
                }
            }
            .foregroundStyle(Palette.ink)
        }
        try snap("SourceIcons", width: 200) {
            HStack(spacing: 16) {
                SourceIcon(.trismegistus)
                SourceIcon(.telegram)
                SourceIcon(.cron)
                SourceIcon(.cli)
            }
            .foregroundStyle(Palette.ink)
        }
    }

    /// The issue header's right side with the mark, the run row alive (with Stop) and finished, and the row's triangle.
    func testIssueRun() throws {
        try snap("IssueRun", width: 640) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("xMuramasa/trismegistus-mac#50").typeRole(.monoSmall)
                    Spacer()
                    RunningMark(detail: "sonnet · 5 min")
                    EndfieldButton("Start conversation", symbol: Symbol.send, kind: .primary) {}
                }
                IssueRunRow(model: "sonnet", age: "5 min", status: "running", isAlive: true, failed: false,
                            progress: "items 1-2 done; Kit tests pass", canStop: true, isStopping: false, openTranscript: {}, stop: {})
                IssueRunRow(model: "opus", age: "2 h", status: "out of turns", isAlive: false, failed: true,
                            progress: nil, canStop: false, isStopping: false, openTranscript: {}, stop: {})
                HStack(spacing: 4) { RunningTriangle(); Text("#50").typeRole(.monoSmall) }
            }
            .foregroundStyle(Palette.ink)
        }
    }

    /// The check panel with lines and a note typed, without lines, and as a viewer sees it; the header's right side
    /// with Dispatch yellow (Start conversation plain) and with the info mark (Start conversation yellow).
    func testCheckPanelAndDispatch() throws {
        let lines = ["the grey sidebar against 09f", "⌘1–⌘6 and the six icons switch sections", "each section's list + detail"]
        try snap("CheckPanel", width: 700) {
            VStack(alignment: .leading, spacing: 16) {
                CheckPanel(lines: lines, source: "from Hermes · 2 Nov 00:48", canAct: true, busy: false,
                           note: .constant("The sidebar is still white."), looksGood: {}, notRight: {})
                CheckPanel(lines: [], source: "from Hermes · 2 Nov 00:48", canAct: true, busy: false, note: .constant(""),
                           looksGood: {}, notRight: {})
                CheckPanel(lines: lines, source: "from Hermes · 2 Nov 00:48", canAct: false, busy: false, note: .constant(""),
                           looksGood: {}, notRight: {})
            }
        }
        try snap("DispatchHeader", width: 700) {
            VStack(alignment: .trailing, spacing: 12) {
                HStack {
                    EndfieldButton("Open in browser", symbol: "arrow.up.right", kind: .quiet, iconOnly: true) {}
                    EndfieldButton("Start conversation", symbol: "bubble.left.and.text.bubble.right") {}
                    EndfieldButton("Dispatch", symbol: "play.fill", kind: .primary) {}
                }
                HStack {
                    EndfieldButton("Open in browser", symbol: "arrow.up.right", kind: .quiet, iconOnly: true) {}
                    EndfieldButton("Start conversation", symbol: "bubble.left.and.text.bubble.right", kind: .primary) {}
                    DispatchHiddenMark(reason: "Dispatch hidden: needs-design (design not agreed)")
                }
            }
        }
    }

    private func picture(_ width: CGFloat, _ height: CGFloat, _ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            color.setFill()
            rect.fill()
            NSColor.white.setFill()
            NSRect(x: rect.midX - 8, y: rect.midY - 8, width: 16, height: 16).fill()
            return true
        }
    }

    func testAttachments() throws {
        try snap("AttachmentTray") {
            AttachmentTray(items: [
                .init(id: UUID(), image: picture(1280, 800, .systemTeal), error: nil),
                .init(id: UUID(), image: picture(600, 900, .systemOrange), error: nil),
                .init(id: UUID(), image: nil, error: nil),
                .init(id: UUID(), image: nil, error: "Too large"),
            ], note: "Steers are text only: the images go with the next new message.") { _ in }
        }
        try snap("ChatImageOne") {
            ChatImageGrid(cells: [.init(id: "a", image: picture(1280, 800, .systemTeal))]) { _ in }
        }
        try snap("ChatImageGrid") {
            ChatImageGrid(cells: [
                .init(id: "a", image: picture(1280, 800, .systemTeal)),
                .init(id: "b", image: picture(600, 900, .systemOrange)),
                .init(id: "c", image: nil, pixelSize: CGSize(width: 10, height: 10)),
                .init(id: "d", image: nil, caption: "img_86942c9e70d7.jpg"),
            ]) { _ in }
        }
        XCTAssertEqual(ChatImageGrid.fitted(CGSize(width: 1280, height: 800)), CGSize(width: 320, height: 200))
        XCTAssertEqual(ChatImageGrid.fitted(CGSize(width: 600, height: 900)), CGSize(width: 160, height: 240))
        XCTAssertEqual(ChatImageGrid.fitted(CGSize(width: 100, height: 50)), CGSize(width: 100, height: 50))
        XCTAssertEqual(ChatImageGrid.fitted(nil), CGSize(width: 320, height: 240))
    }

    func testImageDrop() throws {
        let column = VStack(alignment: .leading, spacing: 12) {
            Text("You").typeRole(.label).foregroundStyle(Ink.text.secondary)
            Text("Here is the screenshot of the failing build.").typeRole(.body).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading).background(Ink.surface.raised)
            Spacer()
            Text("Message Hermes").typeRole(.body).foregroundStyle(Ink.text.muted).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading).overlay(Rectangle().strokeBorder(Ink.line.rule))
        }
        .padding(16)
        .frame(height: 320)
        for (name, feedback) in [
            ("ImageDropAccepting", ImageDropFeedback.judge(images: 3, others: 1, room: 2, limit: 4, refusal: nil, later: true)),
            ("ImageDropRejecting", ImageDropFeedback.judge(images: 0, others: 1, room: 4, limit: 4, refusal: nil, later: false)),
        ] {
            try snap(name) { column.overlay { ImageDropOverlay(feedback, open: true) } }
        }
    }
}
