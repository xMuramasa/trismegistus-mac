import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The priority as a sunken tag (#69, `.ptag`): ink word, `tag` corners.
struct PriorityMark: View {
    let priority: String

    var body: some View {
        Text(priority).typeRole(.tag).foregroundStyle(Ink.text.primary)
            .padding(.horizontal, Space.xs).padding(.vertical, Space.xxs)
            .rounded(Radius.tag, fill: Ink.surface.sunken)
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
        .rounded(Radius.control, fill: Ink.surface.sectionCard, edge: Ink.line.rule)
        .padding(Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Markdown as the chat renders an answer (`MarkdownView`: headings, read-only task boxes, URLs as links), pipe tables
/// as `MarkdownTableView`. HTML in the text and the cells is dropped (`stripHTML`).
struct GitHubMarkdown: View {
    let text: String

    var body: some View {
        MarkdownView(MarkdownPart.parse(text, clean: MarkdownBlocks.stripHTML)) { block in
            switch block {
            case .table(let header, let rows, let alignments):
                MarkdownTableView(header: header, rows: rows, alignments: alignments, clean: MarkdownBlocks.stripHTML)
            case .image(let path):
                // Hermes' image line; an issue body has no session to fetch it from.
                Text("MEDIA:" + path).typeRole(.body).foregroundStyle(Ink.text.primary).textSelection(.enabled)
            case .prose, .code:
                EmptyView() // `parse` makes parts of these
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
        // CappedWidth, not .frame(maxWidth:): in the horizontal scroll view a frame reports the unwrapped line's height and
        // a wrapped cell overlapped the next row.
        return CappedWidth(max: Size.chatColumn / 3) {
            Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
                .typeRole(role).foregroundStyle(color).textSelection(.enabled)
                .multilineTextAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
        }
        .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
        .gridColumnAlignment(alignment == .trailing ? .trailing : alignment == .center ? .center : .leading)
    }
}
