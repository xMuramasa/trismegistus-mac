import SwiftUI

/// One list item, its text styled by `MarkdownText.styled`. Plain values: the app maps TrismegistusKit's parsed Markdown
/// to these.
public struct MarkdownItem: Sendable {
    public enum Marker: Sendable {
        case bullet
        case number(Int)
        case task(done: Bool)
    }

    let marker: Marker
    let text: AttributedString
    let children: [MarkdownItem]

    public init(_ marker: Marker, text: AttributedString, children: [MarkdownItem] = []) {
        self.marker = marker
        self.text = text
        self.children = children
    }
}

/// One block of `MarkdownView`. `Extra` is what the caller draws itself (a table, an image).
public enum MarkdownPart<Extra> {
    case prose(AttributedString)
    case heading(AttributedString)
    case list([MarkdownItem])
    case code(language: String?, text: String)
    case extra(Extra)
}
extension MarkdownPart: Sendable where Extra: Sendable {}

public enum MarkdownText {
    private static var url: Regex<Substring> { /https?:\/\/[^\s<>()\[\]`]+/ }

    /// Inline Markdown as `Text` shows it: bold in the semibold face, inline code as a sunken mono chip, bare URLs as
    /// blue mono links (`.tint(Ink.text.link)` on the `Text`). Line breaks stay as written. `role` is the text's role
    /// (the window's chat answers in `message`, #71): bold and code take its size.
    public static func styled(_ markdown: String, role: TypeRole = .body) -> AttributedString {
        let source = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
        var styled = AttributedString()
        for run in source.runs {
            var attributes = run.attributes
            let intent = run.inlinePresentationIntent ?? []
            let text = String(source[run.range].characters)
            if intent.contains(.stronglyEmphasized) { attributes.swiftUI.font = role.spec.font(weight: .semibold) }
            attributes.inlinePresentationIntent = intent.subtracting([.stronglyEmphasized, .code])
            if intent.contains(.code) {
                if text.wholeMatch(of: url) != nil, let link = URL(string: text) {
                    styled += linked(text, link, attributes)
                } else {
                    styled += chip(text, attributes, role: role)
                }
            } else if let link = run.link {
                styled += text.hasPrefix("http") ? linked(text, link, attributes) : AttributedString(text, attributes: attributes)
            } else {
                styled += linkingURLs(text, attributes)
            }
        }
        return styled
    }

    /// shortcut: the chip's sides are no-break spaces in its background (≈4 pt), so a selection across a chip copies
    /// them; a `TextRenderer` could draw real padding if that ever bothers anyone. No-break: a line can't end between a
    /// side and its code, which left a lone grey box at a line's end (three-per-em spaces break).
    static let chipSide = "\u{00A0}"

    private static func chip(_ code: String, _ attributes: AttributeContainer, role: TypeRole) -> AttributedString {
        var attributes = attributes
        attributes.swiftUI.backgroundColor = Ink.surface.sunken
        var side = attributes
        side.swiftUI.font = role.spec.font()
        // Inter on sunken (#68): mono is for code blocks and the terminal drawer. shortcut: square, not #71's radius 3
        // (a background attribute can't be rounded); a `TextRenderer` could draw the corners if they ever matter.
        attributes.swiftUI.font = role.spec.font()
        return AttributedString(chipSide, attributes: side) + AttributedString(code, attributes: attributes)
            + AttributedString(chipSide, attributes: side)
    }

    private static func linked(_ text: String, _ url: URL, _ attributes: AttributeContainer) -> AttributedString {
        var attributes = attributes
        attributes.link = url
        return AttributedString(text, attributes: attributes)
    }

    /// `text` with its URLs linked; a sentence's closing punctuation stays out of the link.
    private static func linkingURLs(_ text: String, _ attributes: AttributeContainer) -> AttributedString {
        var styled = AttributedString()
        var rest = text[...]
        while let match = rest.firstMatch(of: url) {
            let found = match.output.reversed().drop { ".,;:!?'\"".contains($0) }.reversed()
            let end = rest.index(match.range.lowerBound, offsetBy: found.count)
            guard let link = URL(string: String(rest[match.range.lowerBound..<end])) else { break }
            styled += AttributedString(String(rest[..<match.range.lowerBound]), attributes: attributes)
            styled += linked(String(rest[match.range.lowerBound..<end]), link, attributes)
            rest = rest[end...]
        }
        return styled + AttributedString(String(rest), attributes: attributes)
    }
}

/// Parsed Markdown as views: blocks 12 apart (4 from a paragraph or heading to what it leads), lists with a hanging
/// indent, read-only task boxes. `extra` draws the caller's own blocks. Styled ahead of time, so a caller can cache parts.
public struct MarkdownView<Extra, ExtraView: View>: View {
    let parts: [MarkdownPart<Extra>]
    /// The role of the prose and the items: `body`, or `message` in the window's chat (#71).
    let role: TypeRole
    /// Between a paragraph's lines: 2 pt makes the body role's 18 pt line; a job's prompt reads at 20 pt (4).
    let lineGap: CGFloat
    let extra: (Extra) -> ExtraView

    public init(
        _ parts: [MarkdownPart<Extra>], role: TypeRole = .body, lineGap: CGFloat = Space.xxs,
        @ViewBuilder extra: @escaping (Extra) -> ExtraView
    ) {
        self.parts = parts
        self.role = role
        self.lineGap = lineGap
        self.extra = extra
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(parts.indices, id: \.self) { i in
                block(parts[i]).padding(.top, i == parts.startIndex ? 0 : gap(after: parts[i - 1], before: parts[i]))
            }
        }
    }

    private func gap(after previous: MarkdownPart<Extra>, before part: MarkdownPart<Extra>) -> CGFloat {
        switch (previous, part) {
        case (.prose, .list), (.heading, .list), (.heading, .prose): Space.xs
        default: Space.m
        }
    }

    @ViewBuilder private func block(_ part: MarkdownPart<Extra>) -> some View {
        switch part {
        case .prose(let text):
            MarkdownLine(text: text, role: role, gap: lineGap)
        case .heading(let text):
            MarkdownLine(text: text, role: .headline, gap: lineGap).accessibilityAddTraits(.isHeader)
        case .list(let items):
            MarkdownList(items: items, role: role, gap: lineGap)
        case .code(let language, let code):
            CodeBlockView(language: language, code: code)
        case .extra(let value):
            extra(value)
        }
    }
}

/// A paragraph, a heading or an item's text. 2 pt between lines makes the body role's 18 pt line.
private struct MarkdownLine: View {
    let text: AttributedString
    var role = TypeRole.body
    var color = Ink.text.primary
    var gap = Space.xxs

    var body: some View {
        // fixedSize: in an HStack with a marker a lazy chat can measure the item at one line and truncate it with "…".
        Text(text)
            .typeRole(role).lineSpacing(gap).foregroundStyle(color).tint(Ink.text.link).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownList: View {
    let items: [MarkdownItem]
    var nested = false
    var role = TypeRole.body
    var gap = Space.xxs
    /// #71 (`.skin-a3 .hermes ul li::before`): bullets are `secondary` squares at every depth.
    @Environment(\.hairlineControls) private var hairline

    var body: some View {
        // Task rows sit further apart: their boxes need the air.
        VStack(alignment: .leading, spacing: items.allSatisfy(\.isTask) ? Space.xs : Space.xxs) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                VStack(alignment: .leading, spacing: Space.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        marker(item.marker).frame(minWidth: item.indent, alignment: .leading)
                        MarkdownLine(text: item.text, role: role, color: item.isDone ? Ink.text.secondary : Ink.text.primary, gap: gap)
                    }
                    if !item.children.isEmpty {
                        MarkdownList(items: item.children, nested: true, role: role, gap: gap).padding(.leading, item.indent)
                    }
                }
            }
        }
    }

    /// A shape centred on the first line of the item's text: an invisible line carries the baseline and the height.
    private func onFirstLine(_ shape: some View) -> some View {
        Text(verbatim: " ").typeRole(role).hidden().overlay(alignment: .leading) { shape }
    }

    @ViewBuilder private func marker(_ marker: MarkdownItem.Marker) -> some View {
        switch marker {
        case .bullet:
            onFirstLine(
                Rectangle().fill(hairline ? Ink.text.secondary : nested ? Ink.surface.raised : Ink.text.primary)
                    .frame(width: Size.bullet, height: Size.bullet).edge(hairline ? .clear : Ink.text.primary)
            )
            .accessibilityHidden(true)
        case .number(let n):
            Text(verbatim: "\(n)").typeRole(role).monospacedDigit().foregroundStyle(Ink.text.secondary).padding(.trailing, Space.xs)
        case .task(let done):
            onFirstLine(TaskBox(done: done))
        }
    }
}

/// Read-only: a task is ticked on GitHub, not here.
/// A read-only task box: the Markdown task lists and the Needs check list.
struct TaskBox: View {
    let done: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(done ? Ink.surface.inverse : Ink.surface.raised).edge(Ink.text.primary)
            if done {
                Image(systemName: Symbol.check).font(.system(size: Icon.s, weight: .bold)).foregroundStyle(Ink.surface.raised)
            }
        }
        .frame(width: Size.taskBox, height: Size.taskBox)
        .accessibilityLabel(done ? "Done" : "Not done")
    }
}

extension MarkdownItem {
    fileprivate var isTask: Bool { if case .task = marker { true } else { false } }
    fileprivate var isDone: Bool { if case .task(true) = marker { true } else { false } }

    /// The hanging indent: the marker's column.
    fileprivate var indent: CGFloat {
        switch marker {
        case .bullet: Space.l
        case .number: Space.xl
        case .task: Size.taskBox + Space.s
        }
    }
}

#Preview("Markdown") {
    let parts: [MarkdownPart<Int>] = [
        .prose(MarkdownText.styled("Run `cua-driver stop` and see **this** at https://github.com/xMuramasa.")),
        .list([
            MarkdownItem(.bullet, text: MarkdownText.styled("**#41, sections:** all switch"), children: [MarkdownItem(.bullet, text: MarkdownText.styled("nested"))]),
            MarkdownItem(.bullet, text: MarkdownText.styled("second")),
        ]),
        .heading(MarkdownText.styled("Then")),
        .list([MarkdownItem(.task(done: true), text: MarkdownText.styled("done")), MarkdownItem(.task(done: false), text: MarkdownText.styled("open"))]),
    ]
    return MarkdownView(parts) { _ in EmptyView() }.padding().frame(width: 360).background(Ink.surface.window)
}
