import SwiftUI

/// The head of every detail (#57, `.band` + `.title-rule`): the steel band, at least a row tall, with an optional leading
/// mark and the title in white, the mono subtitle on-steel, the readings and actions on the right; Endfield's 4 pt title
/// rule under it, no hairline. Content in the band sees `onSteel`.
public struct DetailHeader<Mark: View, Title: View, Subtitle: View, Trailing: View>: View {
    let mark: Mark
    let title: Title
    let subtitle: Subtitle
    let trailing: Trailing

    public init(
        @ViewBuilder mark: () -> Mark, @ViewBuilder title: () -> Title, @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.mark = mark()
        self.title = title()
        self.subtitle = subtitle()
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.l) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.s) {
                        mark
                        title.typeRole(.title).foregroundStyle(Ink.text.onBand).accessibilityAddTraits(.isHeader)
                    }
                    subtitle.typeRole(.monoSmall)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: Space.s) { trailing }.fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(Ink.text.onDark)
            .environment(\.onSteel, true)
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .frame(minHeight: Size.row)
            .background { LinearGradient(colors: [Ink.bar.middle, Ink.bar.end], startPoint: .leading, endPoint: .trailing) }
            SegmentRule((Size.titleRule.magenta, Size.titleRule.yellow, Size.titleRule.green), height: Size.titleRule.height, stretches: true)
        }
    }
}

public extension DetailHeader where Mark == EmptyView {
    init(@ViewBuilder title: () -> Title, @ViewBuilder subtitle: () -> Subtitle, @ViewBuilder trailing: () -> Trailing) {
        self.init(mark: { EmptyView() }, title: title, subtitle: subtitle, trailing: trailing)
    }
}
