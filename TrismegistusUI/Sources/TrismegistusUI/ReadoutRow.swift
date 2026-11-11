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
            // Never wraps: a squeezed row drops tags (`ReadoutTags`), not letters of its labels.
            Text(label).typeRole(.label).foregroundStyle(Ink.text.secondary).lineLimit(1).fixedSize()
            value.foregroundStyle(Ink.text.primary)
        }
    }
}

/// A readout cell's menu of a board field's options; picking one calls `set`. The unset value shows as "None" but
/// can't be picked ("None", not "No priority": a menu is as wide as its widest item, and the cell names the field).
/// `width` keeps a field from jumping as its value changes (Status); nil takes the menu's own width (Priority).
public struct ReadoutMenu: View {
    let label: String
    let value: String
    let options: [String]
    let width: CGFloat?
    let set: (String) -> Void

    public init(_ label: String, value: String, options: [String], width: CGFloat? = Size.readoutPicker,
                set: @escaping (String) -> Void) {
        self.label = label
        self.value = value
        self.options = options
        self.width = width
        self.set = set
    }

    public var body: some View {
        Picker(label, selection: Binding(get: { value }, set: { if !$0.isEmpty && $0 != value { set($0) } })) {
            Text(verbatim: "None").tag("")
            ForEach(options, id: \.self) { Text(verbatim: $0).tag($0) }
        }
        .labelsHidden().pickerStyle(.menu)
        .frame(width: width)
        .fixedSize(horizontal: width == nil, vertical: false)
    }
}

/// A compact frosted row of readings (#57, `.readout`, `.rostrip`; #69 frosted white): `ReadoutCell`s with a 1 pt rule
/// between them and a 1 pt rule under the row; `trailing` sits at its end (GitHub's Close issue).
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
                        // The row's free width goes to a filling cell before the spacer, or the spacer takes half.
                        .layoutPriority(cells[i].containerValues.readoutFills ? 1 : 0)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Space.l)
        .frame(maxWidth: .infinity, minHeight: Size.rowCompact)
        .background(Ink.surface.frosted)
        .overlay(alignment: .bottom) { Rectangle().fill(Ink.line.rule).frame(height: Stroke.hairline) }
    }
}

extension ContainerValues {
    /// A `ReadoutRow` cell that takes the row's free width first (the Tags cell, `readoutFills()`).
    @Entry var readoutFills = false
}

public extension View {
    /// Marks a `ReadoutRow` cell that takes the row's free width before the row's spacer does (#73: the Tags cell with
    /// `ReadoutTags(_:)` showing as many tags as fit).
    func readoutFills() -> some View { containerValue(\.readoutFills, true) }
}

public extension ReadoutRow where Trailing == EmptyView {
    init(@ViewBuilder cells: () -> Cells) {
        self.init(cells: cells, trailing: { EmptyView() })
    }
}
