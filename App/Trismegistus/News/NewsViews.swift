import AppKit
import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The popover's one News row standing in for the daily feed runs: newspaper icon, the latest edition's title and
/// age, the edition count. Same shape as SessionRowView, which only knows the four session sources.
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

    var body: some View {
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(feed.items.first?.edition.title ?? "News").typeRole(.headline).foregroundStyle(Ink.text.primary).lineLimit(1)
                HStack(spacing: Space.s) {
                    Image(systemName: Self.symbol).font(.system(size: Icon.m)).accessibilityLabel("News")
                    Image(systemName: Symbol.lock).font(.system(size: Icon.s))
                    Text(detail).typeRole(.monoSmall).lineLimit(1)
                }
                .foregroundStyle(Ink.text.muted)
            }
            Spacer(minLength: Space.s)
            Text("News").typeRole(.label).foregroundStyle(Ink.text.primary)
            if isSelected {
                Image(systemName: Symbol.chevronRight).font(.system(size: Icon.s)).foregroundStyle(Ink.text.primary)
            }
        }
        .padding(.horizontal, Space.m)
        .frame(height: Size.row)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The News section's sidebar: `NEWS // n`, the filter, the editions newest first under a heading per day, one row
/// per edition (title, then feed and time).
struct NewsSidebar: View {
    @Binding var selection: String?
    var filterFocus: FocusState<Bool>.Binding

    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        let needle = filter.trimmingCharacters(in: .whitespaces)
        let items = (model.news?.items ?? []).filter { item in
            needle.isEmpty || [item.edition.title, item.edition.tag].contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        VStack(spacing: 0) {
            SidebarHeader(title: "News // \(model.news?.items.count ?? 0)", prompt: "Filter editions", filter: $filter,
                          focus: filterFocus)
            if model.news == nil {
                SidebarNote(text: "Not connected.")
            } else if model.news?.items.isEmpty == true {
                SidebarNote(text: "No editions yet.")
            }
            List(selection: $selection) {
                ForEach(NewsView.days(items), id: \.date) { day in
                    SectionLabel(title: NewsView.dayTitle(day.date)).sidebarRow()
                    ForEach(day.items) { item in
                        let time = item.publishedAt?.formatted(date: .omitted, time: .shortened)
                        SidebarRow(title: item.edition.title, meta: [item.edition.tag, time].compactMap(\.self).joined(separator: " · "),
                                   isSelected: selection == item.id)
                            .tag(item.id).sidebarRow()
                    }
                }
            }
            .sidebarList()
        }
    }
}

/// The News section's detail: the selected edition, with the reader-unreachable line over it.
struct NewsDetail: View {
    @Binding var selection: String?

    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.news?.items ?? []
        VStack(spacing: 0) {
            if model.news?.readerError != nil { NewsUnreachable() }
            if let item = items.first(where: { $0.id == selection }) {
                ScrollView {
                    EditionView(item: item)
                        .frame(maxWidth: Size.chatColumn, alignment: .leading)
                        .padding(Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(item.id)
            } else {
                SectionEmpty(symbol: NewsRowView.symbol, text: items.isEmpty ? "The daily news runs show up here when one finishes." : "No edition selected")
            }
        }
        .background(Ink.surface.window)
        .task { await model.news?.refreshEditions() }
        .onChange(of: items.map(\.id), initial: true) { _, ids in
            if !ids.isEmpty { selection = WindowSection.kept(selection, in: ids) }
        }
    }
}

/// The News conversation, read-only (the popover's News page): editions newest first under a heading per day, each
/// with its feed tag, title, lead and stories (collapsed to headline and one line until clicked).
struct NewsView: View {
    @Environment(AppModel.self) private var model

    private var days: [(date: String, items: [NewsFeed.Item])] { Self.days(model.news?.items ?? []) }

    /// Newest day first.
    static func days(_ items: [NewsFeed.Item]) -> [(date: String, items: [NewsFeed.Item])] {
        Dictionary(grouping: items, by: \.edition.editionDate)
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.news?.readerError != nil { NewsUnreachable() }
            editions
        }
        .background(Ink.surface.window)
        .task { await model.news?.refreshEditions() }
    }

    private var editions: some View {
        Group {
            if days.isEmpty {
                VStack(spacing: Space.s) {
                    Image(systemName: NewsRowView.symbol).font(.system(size: Icon.empty)).foregroundStyle(Ink.mark.empty)
                    Text("No editions yet").typeRole(.label).foregroundStyle(Ink.text.primary)
                    Text("The daily news runs show up here when one finishes.").typeRole(.callout).foregroundStyle(Ink.text.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Space.m) {
                        ForEach(days, id: \.date) { day in
                            Text(Self.dayTitle(day.date)).typeRole(.label).foregroundStyle(Ink.text.secondary)
                                .padding(.top, Space.xs)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(day.items) { EditionView(item: $0) }
                        }
                    }
                    .padding(Space.l)
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

/// One line over the editions already fetched, which stay.
private struct NewsUnreachable: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: Icon.m)).accessibilityHidden(true)
            Text("Can't reach the news reader. Showing what was loaded.").typeRole(.callout).lineLimit(1)
            Spacer(minLength: Space.s)
            EndfieldButton("Retry", symbol: Symbol.retry, kind: .quiet, iconOnly: true) {
                Task { await model.news?.refreshEditions() }
            }
        }
        .foregroundStyle(Ink.text.secondary)
        .padding(.horizontal, Space.l).padding(.vertical, Space.s)
        .background(Ink.surface.sunken)
    }
}

/// A popover page: back (‹ and esc), the News title, NewsView.
struct NewsPage: View {
    let onBack: @MainActor () -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.m) {
                EndfieldButton("Back", symbol: "chevron.left", kind: .quiet, iconOnly: true, shortcut: .cancelAction, action: onBack)
                VStack(alignment: .leading, spacing: Space.xxs) {
                    TitleRule("News").lineLimit(1)
                    let count = model.news?.items.count ?? 0
                    Text("\(model.news?.reader == nil ? "Cron" : "Reader") · \(count) \(count == 1 ? "edition" : "editions") · read-only")
                        .typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
            NewsView()
            KeyHintStrip([("esc", "back")])
        }
    }
}

/// A reader edition shows its summary until `load` brings the whole one (fetched when it first scrolls into view).
struct EditionView: View {
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
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text(edition.tag).typeRole(.label).foregroundStyle(Ink.surface.window)
                    .padding(.horizontal, Space.s).padding(.vertical, Space.xxs).background(Ink.surface.inverse)
                Spacer(minLength: Space.s)
                if let at = item.publishedAt {
                    Text(at.formatted(date: .omitted, time: .shortened)).typeRole(.monoSmall).foregroundStyle(Ink.text.muted)
                }
            }
            Text(edition.title).typeRole(.title).foregroundStyle(Ink.text.primary)
            if !edition.lead.isEmpty {
                Text(edition.lead).typeRole(.body).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if full == nil {
                let count = item.edition.storyCount
                Text("\(count) \(count == 1 ? "story" : "stories") · loading").typeRole(.monoSmall).foregroundStyle(Ink.text.muted)
            }
            if !edition.markets.isEmpty { markets }
            ForEach(sections, id: \.id) { section in
                Text(edition.sectionTitle(section.id)).typeRole(.label).foregroundStyle(Ink.text.muted).padding(.top, Space.xs)
                VStack(spacing: 1) {
                    ForEach(section.stories.indices, id: \.self) { StoryView(story: section.stories[$0], edition: edition) }
                }
                .background(Ink.line.rule)
            }
            if !edition.gaps.isEmpty {
                NewsField(label: "Gaps", text: edition.gaps.map { "– \($0)" }.joined(separator: "\n")).padding(.top, Space.xs)
            }
        }
        .textSelection(.enabled)
        .padding(Space.l)
        .background(Ink.surface.raised)
        .overlay(Rectangle().strokeBorder(Ink.line.rule, lineWidth: Stroke.hairline))
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
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: isExpanded ? Symbol.chevronDown : Symbol.chevronRight)
                        .font(.system(size: Icon.xxs, weight: .bold)).frame(width: Icon.xxs)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(story.headline).typeRole(.headline).foregroundStyle(Ink.text.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !story.cves.isEmpty {
                            Text(story.cves.joined(separator: " · ")).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !isExpanded {
                            Text(story.summary).typeRole(.callout).foregroundStyle(Ink.text.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: Space.s)
                    if story.favorite {
                        Image(systemName: "star.fill").font(.system(size: Icon.s)).foregroundStyle(Ink.text.primary)
                            .help("Starred in the news reader").accessibilityLabel("Starred")
                    }
                    if story.isUpdate {
                        Text("update").typeRole(.label).foregroundStyle(Ink.text.secondary)
                    }
                    if let v = story.verification, v != "confirmed" {
                        Text(v).typeRole(.label).foregroundStyle(Ink.text.secondary)
                    }
                }
                .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Ink.text.primary)
            .accessibilityHint(isExpanded ? "Collapse the story" : "Expand the story")
            if isExpanded { full.padding(.horizontal, Space.xxxl).padding(.bottom, Space.m) }
        }
        .background(Ink.surface.raised)
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(story.summary).typeRole(.body).foregroundStyle(Ink.text.primary).fixedSize(horizontal: false, vertical: true)
            if let action = story.action {
                NewsField(label: "Action", text: action)
                    .padding(.leading, Space.s)
                    .overlay(alignment: .leading) { Rectangle().fill(Ink.selection).frame(width: Stroke.mark) }
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
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Sources").typeRole(.label).foregroundStyle(Ink.text.muted)
            ForEach(story.sources.indices, id: \.self) { i in
                let source = story.sources[i]
                if let url = source.url {
                    // Only http(s): the Kit drops any other URL from the answer.
                    Button { NSWorkspace.shared.open(url) } label: {
                        HStack(spacing: Space.xs) {
                            Text(source.outlet)
                            Image(systemName: "arrow.up.right").font(.system(size: Icon.xs, weight: .semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .typeRole(.callout).foregroundStyle(Ink.text.link)
                    .help(url.absoluteString)
                    .accessibilityHint("Opens in the browser")
                } else {
                    Text(source.outlet).typeRole(.callout).foregroundStyle(Ink.text.secondary)
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
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(label).typeRole(.label).foregroundStyle(Ink.text.muted)
            Text(text).typeRole(mono ? .monoSmall : .callout).foregroundStyle(Ink.text.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
