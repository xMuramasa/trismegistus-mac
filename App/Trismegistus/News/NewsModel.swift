import SwiftUI
import TrismegistusKit

/// The news reader setting (#24). Empty (or not an https URL) turns the reader off: News then reads the feed runs.
enum NewsSettings {
    static let readerURL = "news.readerURL"
    static let defaultReaderURL = "https://news.lab.x-muramasa.dev"

    static func reader(_ text: String) -> NewsReaderClient? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespaces)), url.scheme == "https", url.host() != nil else { return nil }
        return NewsReaderClient(baseURL: url)
    }
}

extension View {
    func refreshesNews(_ model: AppModel) -> some View { modifier(RefreshesNews(model: model)) }
}

/// Folds the feed runs of every new session list into the News conversation and refreshes the reader's editions,
/// with the reader from Settings. Not `task(id:)`: a list arriving mid-refresh must not cancel the fetches the
/// refresh hands it to.
private struct RefreshesNews: ViewModifier {
    let model: AppModel
    @AppStorage(NewsSettings.readerURL) private var readerURL = NewsSettings.defaultReaderURL

    func body(content: Content) -> some View {
        content
            .onChange(of: model.sessions, initial: true) { _, sessions in refresh(sessions) }
            .onChange(of: readerURL) { refresh(model.sessions) }
    }

    private func refresh(_ sessions: [SessionInfo]) {
        guard let news = model.news else { return }
        news.setReader(NewsSettings.reader(readerURL))
        Task { await news.refresh(sessions) }
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
