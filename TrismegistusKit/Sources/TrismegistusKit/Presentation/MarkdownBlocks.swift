import Foundation

public enum MarkdownBlock: Sendable, Equatable {
    /// Markdown for `AttributedString(markdown:)`.
    case prose(String)
    /// `language` is the first word of the fence's info string.
    case code(language: String?, text: String)
    /// A GitHub-style pipe table. Cells are inline Markdown; every row has as many cells as the header.
    case table(header: [String], rows: [[String]], alignments: [Alignment])
    /// Hermes' `MEDIA:<absolute path>` line: a file of its to show as an image.
    case image(path: String)

    public enum Alignment: Sendable, Equatable { case leading, center, trailing }
}

/// One part of `MarkdownBlocks.document`: a `MarkdownBlock` (one paragraph in a `.prose`), or what prose holds beyond that.
public enum MarkdownElement: Sendable, Equatable {
    case block(MarkdownBlock)
    /// `#` to `###`; `text` is inline Markdown.
    case heading(level: Int, text: String)
    /// Bulleted, numbered or task items (the marker is per item: GitHub mixes tasks and bullets).
    case list([MarkdownListItem])
}

/// One item of a `MarkdownElement.list`. `text` is inline Markdown; `children` is the one nested level (deeper items
/// land in it too).
public struct MarkdownListItem: Sendable, Equatable {
    public enum Marker: Sendable, Equatable {
        case bullet
        case number(Int)
        case task(done: Bool)
    }

    public var marker: Marker
    public var text: String
    public var children: [MarkdownListItem]

    public init(_ marker: Marker, _ text: String, children: [MarkdownListItem] = []) {
        self.marker = marker
        self.text = text
        self.children = children
    }
}

public enum MarkdownBlocks {
    /// `parse`, with each prose block split into paragraphs, headings and lists.
    public static func document(_ markdown: String) -> [MarkdownElement] {
        parse(markdown).flatMap { block -> [MarkdownElement] in
            guard case .prose(let text) = block else { return [.block(block)] }
            return elements(text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline))
        }
    }

    /// Task items ticked and in all, nested ones included (GitHub's header shows it).
    public static func taskProgress(_ elements: [MarkdownElement]) -> (done: Int, total: Int) {
        var items: [MarkdownListItem] = elements.flatMap { element -> [MarkdownListItem] in
            if case .list(let items) = element { items } else { [] }
        }
        items += items.flatMap(\.children)
        let tasks = items.compactMap { item -> Bool? in
            if case .task(let done) = item.marker { done } else { nil }
        }
        return (tasks.filter { $0 }.count, tasks.count)
    }

    /// Splits an answer at ``` and ~~~ fences (CommonMark rules: up to 3 spaces of indent, the closing fence is the same
    /// character and at least as long). An unterminated fence runs to the end. Indented code and ~~~ inside prose lines
    /// that do not start a fence stay prose.
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var open: Fence?

        func flushProse() {
            blocks += proseAndTables(prose)
            prose = []
        }
        func flushCode(_ f: Fence) {
            blocks.append(.code(language: f.language, text: code.joined(separator: "\n")))
            code = []
        }

        // "\r\n" is a single Character in Swift and isNewline, so CRLF splits like LF.
        for line in markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if let f = open {
                if f.closes(line) {
                    flushCode(f)
                    open = nil
                } else {
                    code.append(f.stripIndent(line))
                }
            } else if let f = Fence(opening: line) {
                flushProse()
                open = f
            } else if let path = mediaPath(line) {
                flushProse()
                blocks.append(.image(path: path))
            } else {
                prose.append(line)
            }
        }
        if let f = open { flushCode(f) } else { flushProse() }
        return blocks
    }

    /// GitHub text without its HTML: comments dropped, `<br>` a line break, every other tag removed with its text kept
    /// (`<sub>` too: plain text). `<https://…>` autolinks and a bare `<` stay. Apply to prose only: a code block's
    /// `<div>` is content. shortcut: also strips a tag inside inline `code`, upgrade if that shows.
    public static func stripHTML(_ text: String) -> String {
        text.replacing(/(?s)<!--.*?-->/, with: "")
            .replacing(/<br\s*\/?>/.ignoresCase(), with: "\n")
            .replacing(/<\/?[A-Za-z][A-Za-z0-9-]*(?:\s[^<>]*)?\/?>/, with: "")
    }

    /// The path of a line that is only `MEDIA:<absolute path>`, optionally in backticks.
    private static func mediaPath(_ line: Substring) -> String? {
        var t = line.trimmingCharacters(in: .whitespaces)[...]
        if t.count > 2, t.hasPrefix("`"), t.hasSuffix("`") { t = t.dropFirst().dropLast() }
        guard t.hasPrefix("MEDIA:") else { return nil }
        let path = t.dropFirst(6).trimmingCharacters(in: .whitespaces)
        return path.hasPrefix("/") ? path : nil
    }

    private static func proseBlock(_ lines: [Substring]) -> [MarkdownBlock] {
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
        return text.trimmingCharacters(in: .whitespaces).isEmpty ? [] : [.prose(text)]
    }

    /// The prose lines with the pipe tables split out: a header row with a `---` delimiter row under it (same number
    /// of cells), then rows up to a blank line or a line without a pipe.
    private static func proseAndTables(_ lines: [Substring]) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var plain: [Substring] = []
        var i = 0
        while i < lines.count {
            if i + 1 < lines.count, lines[i].contains("|"), let alignments = alignments(lines[i + 1]) {
                let header = cells(lines[i])
                if header.count == alignments.count {
                    blocks += proseBlock(plain)
                    plain = []
                    var rows: [[String]] = []
                    i += 2
                    while i < lines.count, lines[i].contains("|") {
                        var row = Array(cells(lines[i]).prefix(header.count))
                        row += Array(repeating: "", count: header.count - row.count)
                        rows.append(row)
                        i += 1
                    }
                    blocks.append(.table(header: header, rows: rows, alignments: alignments))
                    continue
                }
            }
            plain.append(lines[i])
            i += 1
        }
        return blocks + proseBlock(plain)
    }

    /// Prose lines as paragraphs (a blank line ends one), headings and lists.
    private static func elements(_ lines: [Substring]) -> [MarkdownElement] {
        var elements: [MarkdownElement] = []
        var plain: [Substring] = []
        func flush() {
            elements += plain.split { $0.allSatisfy(\.isWhitespace) }.map { .block(.prose($0.joined(separator: "\n"))) }
            plain = []
        }
        var i = 0
        while i < lines.count {
            if let heading = heading(lines[i]) {
                flush()
                elements.append(heading)
                i += 1
            } else if let item = ListLine(lines[i]), item.indent <= 3, item.canInterrupt(plain.last) {
                flush()
                elements.append(.list(listItems(lines, at: &i, first: item)))
            } else {
                plain.append(lines[i])
                i += 1
            }
        }
        flush()
        return elements
    }

    /// `# Title` to `### Title`, up to 3 spaces of indent; a closing run of `#` goes. `#49` and `####` stay prose.
    private static func heading(_ line: Substring) -> MarkdownElement? {
        let indent = line.prefix { $0 == " " }.count
        let rest = line.dropFirst(indent)
        let level = rest.prefix { $0 == "#" }.count
        guard indent <= 3, (1...3).contains(level), rest.dropFirst(level).first?.isWhitespace == true else { return nil }
        var text = rest.dropFirst(level).trimmingCharacters(in: .whitespaces)
        let closing = text.reversed().prefix { $0 == "#" }.count
        if text.dropLast(closing).last?.isWhitespace != false { text = text.dropLast(closing).trimmingCharacters(in: .whitespaces) }
        return text.isEmpty ? nil : .heading(level: level, text: text)
    }

    /// The list starting at `lines[i]`; leaves `i` on the first line after it. Items at least 2 further in than the
    /// first are nested (one level: deeper ones join it). A plain line belongs to the item before it: right under it,
    /// or after blank lines when indented. Blank lines before another item keep the list going. A change between
    /// numbered and bulleted ends the list; numbers count up from the first, as CommonMark's do.
    private static func listItems(_ lines: [Substring], at i: inout Int, first: ListLine) -> [MarkdownListItem] {
        var items: [MarkdownListItem] = []
        func addText(_ text: String, separator: String) {
            let last = items.count - 1
            if items[last].children.isEmpty {
                items[last].text += separator + text
            } else {
                items[last].children[items[last].children.count - 1].text += separator + text
            }
        }
        while i < lines.count {
            let line = lines[i]
            if line.allSatisfy(\.isWhitespace) {
                guard let next = lines[i...].firstIndex(where: { !$0.allSatisfy(\.isWhitespace) }) else { break }
                let indent = lines[next].prefix { $0 == " " }.count
                if let item = ListLine(lines[next]), item.isNumbered == first.isNumbered || indent >= first.indent + 2 {
                    i = next
                } else if indent >= first.indent + 2 {
                    addText(lines[next].trimmingCharacters(in: .whitespaces), separator: "\n\n")
                    i = next + 1
                } else {
                    break
                }
            } else if heading(line) != nil || isThematicBreak(line) {
                break
            } else if let item = ListLine(line) {
                if item.indent >= first.indent + 2, !items.isEmpty {
                    items[items.count - 1].children.append(item.listItem(after: items[items.count - 1].children.last))
                } else if item.isNumbered == first.isNumbered {
                    items.append(item.listItem(after: items.last))
                } else {
                    break
                }
                i += 1
            } else {
                addText(line.trimmingCharacters(in: .whitespaces), separator: "\n")
                i += 1
            }
        }
        return items
    }

    /// `---`, `***`, `- - -`: reads like a list marker but is a rule.
    private static func isThematicBreak(_ line: Substring) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        guard marks.count >= 3, let c = marks.first, "-*_".contains(c) else { return false }
        return marks.allSatisfy { $0 == c }
    }

    /// A line that opens a list item: `- `, `* `, `+ ` or `12. `, `12) ` with text after it (`-1` and `--flag` don't).
    private struct ListLine {
        var indent: Int
        /// nil on a bullet.
        var number: Int?
        var marker: MarkdownListItem.Marker
        var text: String

        var isNumbered: Bool { number != nil }

        init?(_ line: Substring) {
            guard !MarkdownBlocks.isThematicBreak(line) else { return nil }
            indent = line.prefix { $0 == " " }.count
            let rest = line.dropFirst(indent)
            var body: Substring
            if let c = rest.first, "-*+".contains(c) {
                body = rest.dropFirst()
            } else {
                let digits = rest.prefix { $0.isASCII && $0.isNumber }
                guard (1...9).contains(digits.count), let n = Int(digits), let c = rest.dropFirst(digits.count).first, ".)".contains(c)
                else { return nil }
                number = n
                body = rest.dropFirst(digits.count + 1)
            }
            guard body.first == " " || body.first == "\t" else { return nil }
            body = body.drop { $0 == " " || $0 == "\t" }
            guard !body.allSatisfy(\.isWhitespace) else { return nil }
            marker = number.map(MarkdownListItem.Marker.number) ?? .bullet
            text = String(body)
            if number == nil, text.count > 4, text.hasPrefix("["), Array(text.prefix(4))[2...] == ["]", " "],
                let tick = text.dropFirst().first, " xX".contains(tick)
            {
                marker = .task(done: tick != " ")
                text = String(text.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            }
        }

        /// CommonMark: right under a paragraph line only a bullet or a `1.` opens a list (`1986. was a year` stays).
        func canInterrupt(_ previous: Substring?) -> Bool {
            guard let previous, !previous.allSatisfy(\.isWhitespace) else { return true }
            return number == nil || number == 1
        }

        func listItem(after previous: MarkdownListItem?) -> MarkdownListItem {
            if number != nil, case .number(let n) = previous?.marker { return MarkdownListItem(.number(n + 1), text) }
            return MarkdownListItem(marker, text)
        }
    }

    /// The cells of a row: outer pipes dropped, `\|` kept as a pipe inside a cell.
    private static func cells(_ line: Substring) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|"), !text.hasSuffix("\\|") { text.removeLast() }
        var cells = [""]
        var escaped = false
        for c in text {
            if escaped {
                cells[cells.count - 1] += c == "|" ? "|" : "\\\(c)"
            } else if c == "|" {
                cells.append("")
            } else if c != "\\" {
                cells[cells.count - 1].append(c)
            }
            escaped = !escaped && c == "\\"
        }
        if escaped { cells[cells.count - 1] += "\\" }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// The columns' alignments when `line` is a delimiter row (`| :--- | :-: | ---: |`), else nil.
    private static func alignments(_ line: Substring) -> [MarkdownBlock.Alignment]? {
        guard line.contains("-") else { return nil }
        var result: [MarkdownBlock.Alignment] = []
        for spec in cells(line) {
            let dashes = spec.drop { $0 == ":" }.reversed().drop { $0 == ":" }
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }) else { return nil }
            result.append(spec.hasSuffix(":") ? (spec.hasPrefix(":") ? .center : .trailing) : .leading)
        }
        return result
    }

    private struct Fence {
        var char: Character
        var length: Int
        var indent: Int
        var language: String?

        init?(opening line: Substring) {
            let indent = line.prefix { $0 == " " }.count
            let rest = line.dropFirst(indent)
            guard indent <= 3, let c = rest.first, c == "`" || c == "~" else { return nil }
            let run = rest.prefix { $0 == c }.count
            let info = rest.dropFirst(run).trimmingCharacters(in: .whitespaces)
            guard run >= 3, !(c == "`" && info.contains("`")) else { return nil }
            char = c
            length = run
            self.indent = indent
            language = info.split(whereSeparator: \.isWhitespace).first.map(String.init)
        }

        func closes(_ line: Substring) -> Bool {
            let indent = line.prefix { $0 == " " }.count
            let rest = line.dropFirst(indent)
            let run = rest.prefix { $0 == char }.count
            return indent <= 3 && run >= length && rest.dropFirst(run).allSatisfy { $0 == " " || $0 == "\t" }
        }

        /// Content loses up to as many leading spaces as the opening fence had.
        func stripIndent(_ line: Substring) -> Substring {
            line.dropFirst(min(indent, line.prefix { $0 == " " }.count))
        }
    }
}
