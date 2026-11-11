import AppKit
import SwiftUI

// #76, design 18 (`design/opendesign/18-search/`): message hits in the chat list (18a and its states) and find in the
// open conversation (18c).

public extension Symbol {
    /// The search glyph: the In messages head and the find bar's field.
    static let search = "magnifyingglass"
}

public extension EnvironmentValues {
    /// ⌘F's marks for the chat row being drawn (#76): set on the rows that hold matches.
    @Entry var findMarks: FindMarks? = nil
}

/// ⌘F's query in a text (#76): every word, case-insensitive, as the relay's search reads it (a quoted phrase is one
/// word; a trailing `*` and the operators AND, OR, NOT are dropped), marked light yellow, the current one solid yellow
/// with an ink underline. A row counts only when it holds every word.
public struct FindMarks: Sendable, Equatable {
    public let words: [String]
    /// Which of the text's matches is current, from 0; nil (or past its matches) when it is in another text.
    public var current: Int?

    public init(query: String, current: Int? = nil) {
        self.init(words: Self.words(query), current: current)
    }

    init(words: [String], current: Int?) {
        self.words = words
        self.current = current
    }

    public var isEmpty: Bool { words.isEmpty }

    static func words(_ query: String) -> [String] {
        query.matches(of: /"[^"]+"|\S+/).compactMap { match in
            let token = String(match.output)
            if ["AND", "OR", "NOT"].contains(token) { return nil }
            let word = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"*")).trimmingCharacters(in: .whitespaces)
            return word.isEmpty ? nil : word
        }
    }

    /// The same words with the current match `n` matches further on: for the text after `n` matches of the row.
    public func after(_ n: Int) -> FindMarks { FindMarks(words: words, current: current.map { $0 - n }) }

    /// Every match in `text`, first to last, none overlapping (the longer word where two start together).
    func ranges(in text: String) -> [Range<String.Index>] {
        var all: [Range<String.Index>] = []
        for word in words {
            var from = text.startIndex
            while from < text.endIndex, let r = text.range(of: word, options: .caseInsensitive, range: from..<text.endIndex) {
                all.append(r)
                from = r.upperBound
            }
        }
        all.sort { $0.lowerBound != $1.lowerBound ? $0.lowerBound < $1.lowerBound : $0.upperBound > $1.upperBound }
        var kept: [Range<String.Index>] = []
        for r in all where kept.last.map({ r.lowerBound >= $0.upperBound }) ?? true { kept.append(r) }
        return kept
    }

    /// The row's matches: 0 unless its texts hold every word between them.
    public func count(in texts: [String]) -> Int {
        guard !words.isEmpty, words.allSatisfy({ w in texts.contains { $0.range(of: w, options: .caseInsensitive) != nil } })
        else { return 0 }
        return texts.reduce(0) { $0 + ranges(in: $1).count }
    }

    /// An answer's matches, counted on the parts `MarkdownView` draws (so the count is what shows).
    public func count<Extra>(in parts: [MarkdownPart<Extra>]) -> Int { count(in: parts.flatMap(Self.texts)) }

    /// A part's matches, whatever the rest of the row holds.
    func matches<Extra>(in part: MarkdownPart<Extra>) -> Int { Self.texts(part).reduce(0) { $0 + ranges(in: $1).count } }

    func count(_ text: AttributedString) -> Int { ranges(in: String(text.characters)).count }

    func count(_ item: MarkdownItem) -> Int { count(item.text) + item.children.reduce(0) { $0 + count($1) } }

    static func texts<Extra>(_ part: MarkdownPart<Extra>) -> [String] {
        switch part {
        case .prose(let text), .heading(let text): [String(text.characters)]
        case .list(let items): items.flatMap(texts)
        case .code(_, let code): [code]
        case .extra: []
        }
    }

    static func texts(_ item: MarkdownItem) -> [String] { [String(item.text.characters)] + item.children.flatMap(texts) }

    /// `text` with its matches marked.
    public func marked(_ text: AttributedString) -> AttributedString {
        var text = text
        let plain = String(text.characters)
        for (i, r) in ranges(in: plain).enumerated() {
            let range = Self.range(r, of: plain, in: text)
            text[range].swiftUI.backgroundColor = i == current ? Ink.find.current : Ink.find.match
            if i == current { text[range].swiftUI.underlineStyle = Text.LineStyle(pattern: .solid, color: Ink.text.primary) }
        }
        return text
    }

    public func marked(_ text: String) -> AttributedString { marked(AttributedString(text)) }

    /// A search hit's snippet with the relay's marks (UTF-16 ranges): the query's words light yellow, in ink.
    public static func snippet(_ text: String, marks: [NSRange]) -> AttributedString {
        var styled = AttributedString(text)
        for mark in marks {
            guard let r = Range(mark, in: text) else { continue }
            let range = Self.range(r, of: text, in: styled)
            styled[range].swiftUI.backgroundColor = Ink.find.match
            styled[range].swiftUI.foregroundColor = Ink.text.primary
        }
        return styled
    }

    /// `r` (in `plain`, the same characters as `text`) as a range of `text`.
    private static func range(_ r: Range<String.Index>, of plain: String, in text: AttributedString) -> Range<AttributedString.Index> {
        let lower = text.characters.index(text.startIndex, offsetBy: plain.distance(from: plain.startIndex, to: r.lowerBound))
        return lower..<text.characters.index(lower, offsetBy: plain.distance(from: r.lowerBound, to: r.upperBound))
    }
}

/// ⌘F's bar under the title rule (#76, design 18c): 44 pt across the detail, white at 88 % with a rule hairline under
/// it: the field (search glyph, the query, a clear button) up to 320 pt, the count (`3 of 9`, `No matches` in terminal
/// red, `Loading earlier messages…`), previous and next, and `esc close` at the right. While the field has the focus ↩
/// steps on, ⇧↩ back and Esc closes.
public struct FindBar: View {
    public enum Status: Sendable, Equatable {
        /// Nothing typed.
        case empty
        case matches(current: Int, total: Int)
        case none
        /// A search hit older than the loaded messages: the earlier ones are on their way.
        case loading
    }

    @Binding var query: String
    let status: Status
    let focus: FocusState<Bool>.Binding
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onClose: () -> Void
    var forceFocused = false // snapshots: focus can't be set from outside

    public init(
        query: Binding<String>, status: Status, focus: FocusState<Bool>.Binding, onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void, onClose: @escaping () -> Void
    ) {
        self._query = query
        self.status = status
        self.focus = focus
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onClose = onClose
    }

    var count: String { Self.count(status) }

    static func count(_ status: Status) -> String {
        switch status {
        case .empty: ""
        case .matches(let current, let total): "\(current) of \(total)"
        case .none: "No matches"
        case .loading: "Loading earlier messages…"
        }
    }

    private var stepping: Bool { if case .matches = status { true } else { false } }

    public var body: some View {
        // The keys go to the bar only while its field has the focus: Return in the composer stays a newline there.
        let keys = focus.wrappedValue
        HStack(spacing: Space.s) {
            field.frame(maxWidth: Size.find.field)
            Text(verbatim: count).typeRole(.callout).monospacedDigit()
                .foregroundStyle(status == .none ? Ink.status.error : Ink.text.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(minWidth: Size.find.count, alignment: .leading)
                .accessibilityLabel(count)
            Button(action: onPrevious) { IconCell(symbol: Symbol.chevronUp) }
                .buttonStyle(.plain).disabled(!stepping)
                .keyboardShortcut(keys ? KeyboardShortcut(.return, modifiers: .shift) : nil)
                .help("Previous ⇧↩").accessibilityLabel("Previous match")
            Button(action: onNext) { IconCell(symbol: Symbol.chevronDown) }
                .buttonStyle(.plain).disabled(!stepping)
                .keyboardShortcut(keys ? KeyboardShortcut(.return, modifiers: []) : nil)
                .help("Next ↩").accessibilityLabel("Next match")
            Spacer(minLength: 0)
            Button(action: onClose) {
                HStack(spacing: Space.xs) {
                    KeyCap("esc")
                    Text("close").typeRole(.callout).foregroundStyle(Ink.text.secondary)
                }
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(keys ? .cancelAction : nil)
            .help("Close (Esc)").accessibilityLabel("Close find")
        }
        .padding(.horizontal, Space.l)
        .frame(height: Size.find.bar)
        .background(Ink.find.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline) }
    }

    private var field: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: Symbol.search).font(.system(size: Icon.m)).foregroundStyle(Ink.text.secondary)
                .accessibilityHidden(true)
            TextField("Find in conversation", text: $query, prompt: Text("Find in conversation").foregroundStyle(Ink.text.secondary))
                .textFieldStyle(.plain).typeRole(.message).foregroundStyle(Ink.text.primary)
                .focused(focus)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: Symbol.close).font(.system(size: Icon.xxs, weight: .bold)).foregroundStyle(Ink.text.secondary)
                        .frame(width: Size.find.clear, height: Size.find.clear)
                        .background(Ink.surface.sunken, in: Circle())
                }
                .buttonStyle(.plain).help("Clear").accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, Space.s)
        .frame(height: Size.control)
        .rounded(Radius.control, fill: Ink.surface.raised, edge: focus.wrappedValue || forceFocused ? Ink.line.strong : Ink.line.rule)
    }
}

/// The chat list's In messages head (#76, design 18a): the mission group head with the search glyph and a word count
/// (`8 conversations`, `… conversations` while searching, `— conversations` while the helper is down).
/// shortcut: `MissionGroupHead`'s layout copied (SidebarChrome.swift is outside #76's files); fold it into
/// `MissionGroupHead` with a `detail` text when that file is next touched.
public struct SearchGroupHead: View {
    let detail: String
    let isFirst: Bool

    public init(detail: String, isFirst: Bool = false) {
        self.detail = detail
        self.isFirst = isFirst
    }

    public var body: some View {
        let square = RoundedRectangle(cornerRadius: Radius.mark, style: .continuous)
        HStack(spacing: Size.missionHead.gap) {
            Image(systemName: Symbol.search).font(.system(size: Icon.l, weight: .semibold)).foregroundStyle(Ink.text.primary)
                .frame(width: Size.missionHead.mark, height: Size.missionHead.mark)
                .background(square.fill(Ink.selection))
                .overlay(square.inset(by: -Stroke.hairline).strokeBorder(Ink.line.strong, lineWidth: Stroke.hairline))
            Text("In messages").typeRole(.missionTitle).foregroundStyle(Ink.text.primary).lineLimit(1)
            Text(verbatim: detail).typeRole(.callout).monospacedDigit().foregroundStyle(Ink.text.secondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: Size.missionHead.height)
        .padding(.top, isFirst ? Size.missionHead.first : Size.missionHead.between - MissionCard.below)
        .padding(.bottom, Size.missionHead.after - Size.statePill.rise)
        .overlay(alignment: .bottomLeading) {
            Rectangle().fill(Ink.line.contour).frame(height: Stroke.hairline)
                .padding(.leading, Size.missionHead.mark + Size.missionHead.gap)
        }
        .padding(.horizontal, Space.m - Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("In messages, \(detail)")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A line under the In messages head (#76, the states in design 18): searching, one character, nothing says it, the
/// newest 50, or the helper down (in ink) with the command that starts it.
public struct SearchNote: View {
    let text: String
    let command: String?

    public init(_ text: String, command: String? = nil) {
        self.text = text
        self.command = command
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(text).typeRole(.callout).foregroundStyle(command == nil ? Ink.text.secondary : Ink.text.primary)
            if let command { Text(verbatim: command).typeRole(.mono).foregroundStyle(Ink.text.secondary).textSelection(.enabled) }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, Size.mission.inset + Space.m).padding(.trailing, Space.m)
        .padding(.top, Space.xs).padding(.bottom, Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// While the list's filter searches inside messages: a small spinner where its ⌘K cap sits.
public struct SearchSpinner: View {
    public init() {}

    public var body: some View {
        ProgressView().controlSize(.mini).frame(width: Size.find.spinner, height: Size.find.spinner)
            .accessibilityLabel("Searching messages")
    }
}

/// Your words in their box with ⌘F's marks (`findMarks`), and the 3 pt yellow edge while the current match is in it.
/// shortcut: `UserMessageText`'s window look copied (ChatMessages.swift is outside #76's files); fold the marks into
/// `UserMessageText` when that file is next touched.
public struct FindableUserText: View {
    let text: String
    @Environment(\.findMarks) private var marks

    public init(_ text: String) { self.text = text }

    public var body: some View {
        if let marks {
            Text(marks.marked(text)).typeRole(.message).foregroundStyle(Ink.text.primary).textSelection(.enabled)
                .padding(.vertical, Space.s).padding(.horizontal, Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .rounded(Radius.control, fill: Ink.surface.message, edge: Ink.line.rule)
                .findEdge(marks)
        } else {
            UserMessageText(text)
        }
    }
}

public extension View {
    /// The 3 pt yellow edge at the left of the message holding the current match (a row's marks have a `current` only
    /// then).
    func findEdge(_ marks: FindMarks?) -> some View {
        overlay(alignment: .leading) {
            if marks?.current != nil { Rectangle().fill(Ink.find.current).frame(width: Stroke.mark) }
        }
    }
}

/// A code block holding find matches (#76): `CodeBlockView`'s window look with the marks.
/// shortcut: copied (Blocks.swift is outside #76's files); fold the marks into `CodeBlockView` when it is next touched.
struct FindableCodeBlock: View {
    let language: String?
    let code: String
    let marks: FindMarks

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                Text(language ?? "").typeRole(.trackedLabel).foregroundStyle(Ink.text.secondary)
                Spacer()
                EndfieldButton("Copy", symbol: Symbol.copy, kind: .quiet, iconOnly: true) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
            }
            ScrollView(.horizontal) {
                Text(marks.marked(CodeBlockView.highlighted(code, language: language)))
                    .typeRole(.mono).foregroundStyle(Ink.text.primary).fixedSize().textSelection(.enabled)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rounded(Radius.control, fill: Ink.surface.sunken, edge: Ink.line.rule)
    }
}
