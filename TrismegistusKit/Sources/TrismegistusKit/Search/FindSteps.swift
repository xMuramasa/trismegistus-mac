/// Find in the open conversation (#76, ⌘F): the matches in transcript order, row by row, and the current one. ↩ steps
/// on and ⇧↩ back, both wrapping. The rows' counts come from the views that mark them, so the count is what shows.
public struct FindSteps: Sendable, Equatable {
    public struct Match: Sendable, Equatable, Hashable {
        /// The chat row (`ChatItem.id`).
        public var itemID: String
        /// Which of the row's matches, from 0.
        public var index: Int

        public init(itemID: String, index: Int) {
            self.itemID = itemID
            self.index = index
        }
    }

    public private(set) var matches: [Match] = []
    /// Into `matches`; nil when there are none.
    public private(set) var current: Int?

    public init() {}

    /// The matches of `counts` (each row's, in order); the current match stays where it was when it still exists, else
    /// the first is current.
    public init(counts: [(itemID: String, count: Int)], keeping old: FindSteps = FindSteps()) {
        matches = counts.flatMap { row in (0..<max(0, row.count)).map { Match(itemID: row.itemID, index: $0) } }
        current = old.match.flatMap(matches.firstIndex(of:)) ?? (matches.isEmpty ? nil : 0)
    }

    public var match: Match? { current.map { matches[$0] } }
    /// `3` of `3 of 9`.
    public var position: Int? { current.map { $0 + 1 } }
    public var total: Int { matches.count }

    public mutating func next() { step(1) }
    public mutating func previous() { step(-1) }

    private mutating func step(_ by: Int) {
        guard let current, !matches.isEmpty else { return }
        self.current = (current + by + matches.count) % matches.count
    }

    /// The row's first match becomes current (a search hit opened); false when the row has none.
    @discardableResult
    public mutating func select(itemID: String) -> Bool {
        guard let i = matches.firstIndex(where: { $0.itemID == itemID }) else { return false }
        current = i
        return true
    }

    /// The current match's index within `itemID`, nil when the current match is elsewhere.
    public func currentIndex(in itemID: String) -> Int? {
        match.flatMap { $0.itemID == itemID ? $0.index : nil }
    }
}
