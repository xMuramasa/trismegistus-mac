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

public enum MarkdownBlocks {
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
