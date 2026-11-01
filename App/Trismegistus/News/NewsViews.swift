import AppKit
import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The one News row standing in for the daily feed runs: newspaper icon, the latest edition's title and age, the
/// edition count. Same shape as SessionRowView, which only knows the four session sources.
struct NewsRowView: View {
    nonisolated static let id = "trismegistus.news"
    static let symbol = "newspaper"

    let feed: NewsFeed
    let isSelected: Bool
    let now: Date

    private var detail: String {
        let count = feed.items.count
        let age = PopoverFormat.ago(feed.items.first?.publishedAt, now: now)
        return "\(age) · \(count) \(count == 1 ? "edition" : "editions") · read-only"
    }

    @Environment(\.sunkenRows) private var sunken

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(feed.items.first?.edition.title ?? "News").typeRole(.headline).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: Self.symbol).font(.system(size: 11)).accessibilityLabel("News")
                    Image(systemName: Symbol.lock).font(.system(size: 10))
                    Text(detail).typeRole(.monoSmall).lineLimit(1)
                }
                .foregroundStyle(sunken ? Theme.secondary : Theme.muted)
            }
            Spacer(minLength: 8)
            Text("News").typeRole(.label).foregroundStyle(Theme.ink)
            if isSelected {
                Image(systemName: Symbol.chevronRight).font(.system(size: 10)).foregroundStyle(Theme.ink)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The News conversation, read-only: editions newest first under a heading per day, each with its feed tag, title,
/// lead and stories (collapsed to headline and one line until clicked).
struct NewsView: View {
    @Environment(AppModel.self) private var model

    private var days: [(date: String, items: [NewsFeed.Item])] {
        Dictionary(grouping: model.news?.items ?? [], by: \.edition.editionDate)
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.news?.readerError != nil { unreachable }
            editions
        }
        .background(Theme.paper)
        .task { await model.news?.refreshEditions() }
    }

    /// One line over the editions already fetched, which stay.
    private var unreachable: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).accessibilityHidden(true)
            Text("Can't reach the news reader. Showing what was loaded.").typeRole(.callout).lineLimit(1)
            Spacer(minLength: 8)
            EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) {
                Task { await model.news?.refreshEditions() }
            }
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .background(Theme.sunken)
    }

    private var editions: some View {
        Group {
            if days.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: NewsRowView.symbol).font(.system(size: 28)).foregroundStyle(Theme.borderInactive)
                    Text("No editions yet").typeRole(.label).foregroundStyle(Theme.ink)
                    Text("The daily news runs show up here when one finishes.").typeRole(.callout).foregroundStyle(Theme.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(days, id: \.date) { day in
                            Text(Self.dayTitle(day.date)).typeRole(.label).foregroundStyle(Theme.secondary)
                                .padding(.top, 4)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(day.items) { EditionView(item: $0) }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    /// "Saturday 31 October" from `2026-10-31` (a calendar date: no time zone shifts it).
    static func dayTitle(_ date: String) -> String {
        let utc = TimeZone(identifier: "UTC")!
        guard let day = try? Date(date, strategy: Date.ISO8601FormatStyle(timeZone: utc).year().month().day()) else { return date }
        return day.formatted(Date.FormatStyle(timeZone: utc).weekday(.wide).day().month(.wide))
    }
}

/// A popover page: back (‹ and esc), the News title, NewsView.
struct NewsPage: View {
    let onBack: @MainActor () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                EndfieldButton("Back", symbol: "chevron.left", kind: .quiet, iconOnly: true, shortcut: .cancelAction, action: onBack)
                VStack(alignment: .leading, spacing: 2) {
                    TitleRule("News").lineLimit(1)
                    let count = model.news?.items.count ?? 0
                    Text("\(model.news?.reader == nil ? "Cron" : "Reader") · \(count) \(count == 1 ? "edition" : "editions") · read-only")
                        .typeRole(.monoSmall).foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            NewsView()
            KeyHintStrip([("esc", "back")])
        }
    }
}

/// A reader edition shows its summary until `load` brings the whole one (fetched when it first scrolls into view).
private struct EditionView: View {
    let item: NewsFeed.Item

    @Environment(AppModel.self) private var model

    private var full: NewsEdition? { model.news?.edition(for: item) }
    private var edition: NewsEdition { full ?? item.edition }

    /// Consecutive stories of one section (they come in reading order).
    private var sections: [(id: String, stories: [NewsEdition.Story])] {
        var out: [(id: String, stories: [NewsEdition.Story])] = []
        for story in edition.stories {
            if out.last?.id == story.section { out[out.count - 1].stories.append(story) } else { out.append((story.section, [story])) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(edition.tag).typeRole(.label).foregroundStyle(Theme.paper)
                    .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.ink)
                Spacer(minLength: 8)
                if let at = item.publishedAt {
                    Text(at.formatted(date: .omitted, time: .shortened)).typeRole(.monoSmall).foregroundStyle(Theme.muted)
                }
            }
            Text(edition.title).typeRole(.title).foregroundStyle(Theme.ink)
            if !edition.lead.isEmpty {
                Text(edition.lead).typeRole(.body).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if full == nil {
                let count = item.edition.storyCount
                Text("\(count) \(count == 1 ? "story" : "stories") · loading").typeRole(.monoSmall).foregroundStyle(Theme.muted)
            }
            if !edition.markets.isEmpty { markets }
            ForEach(sections, id: \.id) { section in
                Text(edition.sectionTitle(section.id)).typeRole(.label).foregroundStyle(Theme.muted).padding(.top, 4)
                VStack(spacing: 1) {
                    ForEach(section.stories.indices, id: \.self) { StoryView(story: section.stories[$0], edition: edition) }
                }
                .background(Theme.rule)
            }
            if !edition.gaps.isEmpty {
                NewsField(label: "Gaps", text: edition.gaps.map { "– \($0)" }.joined(separator: "\n")).padding(.top, 4)
            }
        }
        .textSelection(.enabled)
        .padding(14)
        .background(Theme.raised)
        .overlay(Rectangle().strokeBorder(Theme.rule, lineWidth: 1))
        // Again after a retry clears the error.
        .task(id: model.news?.readerError == nil) { await model.news?.load(item.id) }
    }

    private var markets: some View {
        let items = edition.markets.map { m in [m.name, m.value, m.change].compactMap(\.self).joined(separator: " ") }
        let asOf = edition.marketsAsOf.map { " (\($0))" } ?? ""
        return NewsField(label: "Markets" + asOf, text: items.joined(separator: " · "), mono: true)
    }
}

private struct StoryView: View {
    let story: NewsEdition.Story
    let edition: NewsEdition

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: isExpanded ? Symbol.chevronDown : Symbol.chevronRight)
                        .font(.system(size: 8, weight: .bold)).frame(width: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(story.headline).typeRole(.headline).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !story.cves.isEmpty {
                            Text(story.cves.joined(separator: " · ")).typeRole(.monoSmall).foregroundStyle(Theme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !isExpanded {
                            Text(story.summary).typeRole(.callout).foregroundStyle(Theme.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if story.favorite {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.ink)
                            .help("Starred in the news reader").accessibilityLabel("Starred")
                    }
                    if story.isUpdate {
                        Text("update").typeRole(.label).foregroundStyle(Theme.secondary)
                    }
                    if let v = story.verification, v != "confirmed" {
                        Text(v).typeRole(.label).foregroundStyle(Theme.secondary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
            .accessibilityHint(isExpanded ? "Collapse the story" : "Expand the story")
            if isExpanded { full.padding(.horizontal, 26).padding(.bottom, 12) }
        }
        .background(Theme.raised)
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(story.summary).typeRole(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            if let action = story.action {
                NewsField(label: "Action", text: action)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Rectangle().fill(Theme.yellow).frame(width: 3) }
            }
            ForEach(story.details.indices, id: \.self) { NewsField(label: story.details[$0].label, text: story.details[$0].text) }
            if !story.coverage.isEmpty {
                NewsField(label: "Coverage", text: story.coverage.map { c in
                    let outlets = c.covered ? (c.outlets.isEmpty ? "covered" : c.outlets.joined(separator: ", ")) : "not covered"
                    return "\(NewsEdition.groupTitle(c.group)): \(outlets)"
                }.joined(separator: "\n"))
            }
            if !story.framing.isEmpty {
                NewsField(label: "Framing", text: story.framing.map { "\(NewsEdition.groupTitle($0.group)): \($0.text)" }.joined(separator: "\n"))
            }
            if let blindspot = story.blindspot { NewsField(label: "Blindspot", text: blindspot) }
            if !story.sources.isEmpty { sources }
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Sources").typeRole(.label).foregroundStyle(Theme.muted)
            ForEach(story.sources.indices, id: \.self) { i in
                let source = story.sources[i]
                if let url = source.url {
                    // Only http(s): the Kit drops any other URL from the answer.
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: 4) {
                            Text(source.outlet)
                            Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .typeRole(.callout).foregroundStyle(Theme.blue)
                    .help(url.absoluteString)
                    .accessibilityHint("Opens in the browser")
                } else {
                    Text(source.outlet).typeRole(.callout).foregroundStyle(Theme.secondary)
                }
            }
        }
    }
}

/// A caps label over a block of text.
private struct NewsField: View {
    let label: String
    let text: String
    var mono = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).typeRole(.label).foregroundStyle(Theme.muted)
            Text(text).typeRole(mono ? .monoSmall : .callout).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
