import SwiftUI

/// A toggle chip: ink when on (yellow label), plain when off; on steel its label is light. With `hairlineControls`
/// (#69) a thin-edged `control` button, sunken with a secondary edge when on.
public struct FilterChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    /// Stretch to the width offered (a half of a segmented row) instead of hugging the label.
    var fills = false
    let action: () -> Void

    public init(title: String, symbol: String, isOn: Bool, fills: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.isOn = isOn
        self.fills = fills
        self.action = action
    }

    @Environment(\.onSteel) private var onSteel
    @Environment(\.hairlineControls) private var hairline

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                // Never wrap: a narrow pane squeezed the labels into one letter column ("COM/MAN/DS").
                Text(title).textCase(.uppercase).lineLimit(1).fixedSize()
                Image(systemName: symbol)
            }
            .typeRole(hairline ? .controlLabel : .button)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: hairline ? Size.control : nil)
            .modifier(Face(isOn: isOn, hairline: hairline, onSteel: onSteel))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private struct Face: ViewModifier {
        let isOn: Bool
        let hairline: Bool
        let onSteel: Bool

        func body(content: Content) -> some View {
            if hairline {
                content.foregroundStyle(Ink.text.primary)
                    .rounded(Radius.control, fill: isOn ? Ink.surface.sunken : Ink.surface.raised, edge: isOn ? Ink.text.secondary : Ink.line.rule)
            } else {
                content.foregroundStyle(isOn ? Ink.selection : onSteel ? Ink.text.onDark : Ink.text.primary)
                    .background(isOn ? Ink.surface.inverse : .clear)
            }
        }
    }
}

/// One part of a segmented control in the list column (#69, `.seg`): an icon with an optional count, the name as its
/// tooltip and accessibility label; secondary on white, the chosen one ink with a 2 pt yellow underline. They go in a
/// `Segmented`.
public struct SegmentTab: View {
    let title: String
    let symbol: String
    let count: Int?
    let isOn: Bool
    let action: () -> Void

    public init(title: String, symbol: String, count: Int? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.count = count
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: symbol).font(.system(size: Icon.section))
                if let count { Text(verbatim: "\(count)").typeRole(.callout, weight: .semibold).monospacedDigit() }
            }
            .frame(maxWidth: .infinity, minHeight: Size.control)
            .foregroundStyle(isOn ? Ink.text.primary : Ink.text.secondary)
            .background(Ink.surface.raised)
            .overlay(alignment: .bottom) { if isOn { Rectangle().fill(Ink.selection).frame(height: Stroke.accent) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(count.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The segmented control (`.seg`): `SegmentTab`s side by side in `control` corners, a rule hairline around and between
/// them.
public struct Segmented<Tabs: View>: View {
    let tabs: Tabs

    public init(@ViewBuilder tabs: () -> Tabs) { self.tabs = tabs() }

    public var body: some View {
        Group(subviews: tabs) { tabs in
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    if i > 0 { Rectangle().fill(Ink.line.rule).frame(width: Stroke.hairline) }
                    tabs[i]
                }
            }
            // The dividers would take all the height offered.
            .fixedSize(horizontal: false, vertical: true)
        }
        .rounded(Radius.control, fill: Ink.surface.raised, edge: Ink.line.rule)
    }
}
