import SwiftUI

/// One label + value pair of a `ReadoutRow`; the value is any view (text, a native picker, tags).
public struct ReadoutCell<Value: View>: View {
    let label: String
    let value: Value

    public init(_ label: String, @ViewBuilder value: () -> Value) {
        self.label = label
        self.value = value()
    }

    public var body: some View {
        HStack(spacing: Space.s) {
            Text(label).typeRole(.label).foregroundStyle(Ink.text.secondary)
            value.foregroundStyle(Ink.text.primary)
        }
    }
}

/// A compact raised row of readings (#57, `.readout`, `.read`): `ReadoutCell`s with a 1 pt rule between them and a 1 pt
/// rule under the row; `trailing` sits at its end (GitHub's Close issue).
public struct ReadoutRow<Cells: View, Trailing: View>: View {
    let cells: Cells
    let trailing: Trailing

    public init(@ViewBuilder cells: () -> Cells, @ViewBuilder trailing: () -> Trailing) {
        self.cells = cells()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.l) {
            Group(subviews: cells) { cells in
                ForEach(cells.indices, id: \.self) { i in
                    cells[i]
                        .padding(.leading, i == 0 ? 0 : Space.l)
                        .overlay(alignment: .leading) {
                            if i > 0 { Rectangle().fill(Ink.line.rule).frame(width: Stroke.hairline) }
                        }
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, minHeight: Size.rowCompact)
        .background(Ink.surface.raised)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline) }
    }
}

public extension ReadoutRow where Trailing == EmptyView {
    init(@ViewBuilder cells: () -> Cells) {
        self.init(cells: cells, trailing: { EmptyView() })
    }
}
