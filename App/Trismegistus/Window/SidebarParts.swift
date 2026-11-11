import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The top of a section's list column (#68): the list header with the title centred and the section's own actions at
/// the right, the filter field (⌘K), then whatever the section adds (pickers, tags, a refusal).
struct SidebarHeader<Trailing: View, Extra: View>: View {
    let title: String
    let prompt: String
    @Binding var filter: String
    let focus: FocusState<Bool>.Binding
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        VStack(spacing: Space.s) {
            ListHeader(title: title) { EmptyView() } trailing: { trailing() }
                .padding(.horizontal, -Space.l)
            SidebarFilter(prompt, text: $filter, focus: focus)
            extra()
        }
        .padding(.horizontal, Space.l).padding(.bottom, Space.m)
    }
}

/// A list column's filter field with its ⌘K key cap, its right edge pulled in so the soft shadow has the same margin as
/// the rest of the column.
/// `busy` (#76): a spinner in place of the key cap while the chat list searches inside messages.
struct SidebarFilter: View {
    let prompt: String
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    var busy = false

    init(_ prompt: String, text: Binding<String>, focus: FocusState<Bool>.Binding, busy: Bool = false) {
        self.prompt = prompt
        self._text = text
        self.focus = focus
        self.busy = busy
    }

    var body: some View {
        EndfieldTextField(prompt, text: $text, focus: focus, hint: busy ? nil : "⌘K")
            .overlay(alignment: .trailing) { if busy { SearchSpinner().padding(.trailing, Space.s) } }
            .padding(.trailing, Space.xs)
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
