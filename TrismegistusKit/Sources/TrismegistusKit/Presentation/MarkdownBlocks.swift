import Foundation

public enum MarkdownBlock: Sendable, Equatable {
    /// Markdown for `AttributedString(markdown:)`.
    case prose(String)
    /// `language` is the first word of the fence's info string.
    case code(language: String?, text: String)
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
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { blocks.append(.prose(text)) }
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
            } else {
                prose.append(line)
            }
        }
        if let f = open { flushCode(f) } else { flushProse() }
        return blocks
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
