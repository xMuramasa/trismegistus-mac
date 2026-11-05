import SwiftUI

/// A toggle chip: ink when on (yellow label), plain when off; on steel its label is light.
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

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                // Never wrap: a narrow pane squeezed the labels into one letter column ("COM/MAN/DS").
                Text(title).textCase(.uppercase).lineLimit(1).fixedSize()
                Image(systemName: symbol)
            }
            .typeRole(.button)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .frame(maxWidth: fills ? .infinity : nil)
            .foregroundStyle(isOn ? Ink.selection : onSteel ? Ink.text.onDark : Ink.text.primary)
            .background(isOn ? Ink.surface.inverse : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
