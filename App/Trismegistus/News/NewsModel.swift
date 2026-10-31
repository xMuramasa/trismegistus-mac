import SwiftUI
import TrismegistusKit

extension View {
    /// Folds the feed runs of every new session list into the News conversation. Not `task(id:)`: a list arriving
    /// mid-refresh must not cancel the fetches the refresh hands it to.
    func refreshesNews(_ model: AppModel) -> some View {
        onChange(of: model.sessions, initial: true) { _, sessions in
            Task { await model.news?.refresh(sessions) }
        }
    }
}

/// A row of the popover list or the window sidebar: a conversation, or the one News row.
enum ConversationListRow<Item: Identifiable>: Identifiable where Item.ID == String {
    case item(Item)
    case news

    var id: String {
        switch self {
        case .item(let item): item.id
        case .news: NewsRowView.id // in selections; not a Hermes session id
        }
    }

    /// The items with the feed runs replaced by one News row, where the first of them was.
    static func folding(_ items: [Item], news: Set<String>) -> [Self] {
        var shown = false
        return items.compactMap { item in
            guard news.contains(item.id) else { return .item(item) }
            defer { shown = true }
            return shown ? nil : .news
        }
    }
}
