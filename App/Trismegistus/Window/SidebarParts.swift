import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The top of a section's sidebar (09f): `TITLE // n` with an icon-only action, the light filter field (⌘K), then
/// whatever the section adds (pickers, tags, a refusal).
struct SidebarHeader<Trailing: View, Extra: View>: View {
    let title: String
    let prompt: String
    @Binding var filter: String
    let focus: FocusState<Bool>.Binding
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        VStack(spacing: Space.m) {
            HStack(spacing: Space.s) {
                Text(title).typeRole(.label).foregroundStyle(Ink.text.onSidebarSecondary).lineLimit(1)
                Spacer(minLength: Space.s)
                trailing()
            }
            // Every section's header the same height, with or without its button.
            .frame(height: Size.control)
            EndfieldTextField(prompt, text: $filter, ground: Ink.surface.window, focus: focus)
            extra()
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }
}

extension SidebarHeader where Extra == EmptyView {
    init(title: String, prompt: String, filter: Binding<String>, focus: FocusState<Bool>.Binding,
         @ViewBuilder trailing: @escaping () -> Trailing) {
        self.init(title: title, prompt: prompt, filter: filter, focus: focus, trailing: trailing, extra: { EmptyView() })
    }
}

extension SidebarHeader where Trailing == EmptyView, Extra == EmptyView {
    init(title: String, prompt: String, filter: Binding<String>, focus: FocusState<Bool>.Binding) {
        self.init(title: title, prompt: prompt, filter: filter, focus: focus, trailing: { EmptyView() }, extra: { EmptyView() })
    }
}

extension View {
    /// A sidebar `List`: keyboard selection as before, no ground of its own.
    func sidebarList() -> some View { listStyle(.plain).scrollContentBackground(.hidden) }

    /// A row of a sidebar list, edge to edge. Every row sets `listRowBackground`: it replaces the row view's ground,
    /// where macOS draws its selection highlight (a thin blue line showed past the rows otherwise).
    func sidebarRow() -> some View {
        listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Ink.surface.sidebar)
    }
}

/// A one-line caption where a sidebar list is empty or still loading.
struct SidebarNote: View {
    let text: String

    var body: some View {
        Text(text).typeRole(.caption).foregroundStyle(Ink.text.onSidebarSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Space.l).padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A sidebar row: title, then one meta line, with marks on the right.
struct SidebarRow<Marks: View>: View {
    let title: String
    let meta: String
    let isSelected: Bool
    var titleLines = 1
    @ViewBuilder var marks: (RowInk) -> Marks

    @Environment(\.onSidebar) private var onSidebar

    var body: some View {
        let ink = RowInk(onSidebar: onSidebar, isSelected: isSelected)
        HStack(spacing: Space.s) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).typeRole(.headline).foregroundStyle(ink.title).lineLimit(titleLines)
                Text(meta).typeRole(.monoSmall).foregroundStyle(ink.meta).lineLimit(1)
            }
            Spacer(minLength: Space.s)
            marks(ink)
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
        .rowGround(isSelected: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SidebarRow where Marks == EmptyView {
    init(title: String, meta: String, isSelected: Bool, titleLines: Int = 1) {
        self.init(title: title, meta: meta, isSelected: isSelected, titleLines: titleLines, marks: { _ in EmptyView() })
    }
}

/// A detail's empty state: the section's symbol and one line.
struct SectionEmpty: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: symbol).font(.system(size: Icon.empty)).foregroundStyle(Ink.mark.empty)
            Text(text).typeRole(.caption).foregroundStyle(Ink.text.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.surface.window)
    }
}
