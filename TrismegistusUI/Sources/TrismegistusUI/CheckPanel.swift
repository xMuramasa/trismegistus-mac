import SwiftUI

/// The first card of an issue waiting for Martin's check (design 10a): what Hermes asked him to look at, and the two
/// answers. Without `canAct` (a viewer device) the card shows the lines and no actions.
public struct CheckPanel: View {
    let lines: [String]
    /// `from Hermes · <comment date>`, right-aligned.
    let source: String
    let canAct: Bool
    let busy: Bool
    @Binding var note: String
    let looksGood: @MainActor () -> Void
    let notRight: @MainActor () -> Void

    public init(lines: [String], source: String, canAct: Bool, busy: Bool, note: Binding<String>,
                looksGood: @escaping @MainActor () -> Void, notRight: @escaping @MainActor () -> Void) {
        self.lines = lines
        self.source = source
        self.canAct = canAct
        self.busy = busy
        self._note = note
        self.looksGood = looksGood
        self.notRight = notRight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Ink.selection).frame(height: Stroke.mark)
            VStack(alignment: .leading, spacing: Space.m) {
                HStack(spacing: Space.s) {
                    Rectangle().fill(Ink.marker).frame(width: Size.marker, height: Size.marker)
                    Text("Needs your check").textCase(.uppercase).typeRole(.label).foregroundStyle(Ink.text.primary)
                    Spacer(minLength: Space.s)
                    Text(source).typeRole(.monoSmall).foregroundStyle(Ink.text.secondary).lineLimit(1)
                }
                if lines.isEmpty {
                    Text("No on-screen notes from Hermes; see the latest comment").typeRole(.body).foregroundStyle(Ink.text.secondary)
                } else {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line).typeRole(.body).foregroundStyle(Ink.text.primary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if canAct {
                    HStack(spacing: Space.m) {
                        EndfieldButton("Looks good", symbol: Symbol.check, kind: .primary, action: looksGood).disabled(busy)
                        EndfieldTextField("What's not right? (posted as a comment)", text: $note).disabled(busy)
                        EndfieldButton("Not right", symbol: Symbol.close, kind: .danger, action: notRight)
                            .disabled(busy || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Looks good: comments \"Confirmed on screen by Martin.\", Status Done. Not right: comments your note, reopens the issue if closed, Status Todo.")
                        .typeRole(.caption).foregroundStyle(Ink.text.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Space.l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.surface.raised)
        .shadow(Shadow.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Needs your check")
    }
}

/// An `info.circle` in the place of Dispatch: the reason it's hidden is its tooltip and accessibility label.
public struct DispatchHiddenMark: View {
    let reason: String

    public init(reason: String) { self.reason = reason }

    public var body: some View {
        Image(systemName: "info.circle")
            .typeRole(.button) // the size of the Open in browser icon beside it
            .foregroundStyle(Ink.text.secondary)
            .padding(Space.s)
            .help(reason)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(reason)
    }
}
