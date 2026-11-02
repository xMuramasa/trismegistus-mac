import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The priority as an ink tag, like a news edition's feed tag.
struct PriorityMark: View {
    let priority: String

    var body: some View {
        Text(priority).typeRole(.label).foregroundStyle(Ink.surface.window)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xxs).background(Ink.surface.inverse)
            .accessibilityLabel("Priority \(priority)")
    }
}

/// `not_configured`: what the relay needs.
struct SetupNote: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("GitHub is not set up").typeRole(.label).foregroundStyle(Ink.text.primary)
            Text(text).typeRole(.callout).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            Text("GITHUB_TOKEN=… in the relay's .env, then restart the relay. The token needs read and write access to the owner's issues and the Work project.")
                .typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(Space.l)
        .frame(maxWidth: Size.chatColumn, alignment: .leading)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Markdown as the chat renders an answer: prose with inline styles (line breaks kept as written), fenced code as
/// `CodeBlockView`, pipe tables as `MarkdownTableView`. HTML in the prose and the cells is dropped (`stripHTML`).
struct GitHubMarkdown: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .prose(let s):
                    let s = MarkdownBlocks.stripHTML(s)
                    Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
                        .typeRole(.body).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                case .table(let header, let rows, let alignments):
                    MarkdownTableView(header: header, rows: rows, alignments: alignments, clean: MarkdownBlocks.stripHTML)
                case .image(let path):
                    // Hermes' image line; an issue body has no session to fetch it from.
                    Text("MEDIA:" + path).typeRole(.body).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A Markdown pipe table (`MarkdownBlock.table`): a header row in the label role, hairline rules, cells that size to
/// their text up to a third of the chat column and wrap past it; a wide table scrolls sideways.
struct MarkdownTableView: View {
    let header: [String]
    let rows: [[String]]
    let alignments: [MarkdownBlock.Alignment]
    /// Cell text is run through this first (GitHub text drops its HTML).
    var clean: (String) -> String = { $0 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                rule
                GridRow { ForEach(header.indices, id: \.self) { cell(header[$0], column: $0, role: .label, color: Ink.text.secondary) } }
                rule
                ForEach(rows.indices, id: \.self) { r in
                    GridRow { ForEach(header.indices, id: \.self) { cell(rows[r][$0], column: $0, role: .body, color: Ink.text.primary) } }
                    rule
                }
            }
        }
    }

    private var rule: some View {
        Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline).gridCellColumns(header.count)
    }

    private func cell(_ text: String, column: Int, role: TypeRole, color: Color) -> some View {
        let text = clean(text)
        let alignment = alignments[column]
        return Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            .typeRole(role).foregroundStyle(color).textSelection(.enabled)
            .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .frame(maxWidth: Size.chatColumn / 3, alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
    }
}
