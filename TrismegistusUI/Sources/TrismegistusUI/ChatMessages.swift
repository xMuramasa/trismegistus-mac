import SwiftUI

/// A turn's label, `YOU // 13:42`: tracked 10/600/0.14 em in the window (#71, `hairlineControls`), `label` in the popover.
public struct MessageLabel: View {
    let text: String
    @Environment(\.hairlineControls) private var hairline

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).typeRole(hairline ? .trackedLabel : .label).foregroundStyle(Ink.text.secondary)
    }
}

/// Your words in their box: in the window (#71, `.you`) 14 pt on white at 85 % with a rule hairline, `control` corners,
/// 8 x 12 in; in the popover 13 pt on raised, `l` corners, 12 in.
public struct UserMessageText: View {
    let text: String
    @Environment(\.hairlineControls) private var hairline

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text).typeRole(hairline ? .message : .body).foregroundStyle(Ink.text.primary).textSelection(.enabled)
            .padding(.vertical, hairline ? Space.s : Space.m).padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .rounded(hairline ? Radius.control : Radius.l, fill: hairline ? Ink.surface.message : Ink.surface.raised, edge: Ink.line.rule)
    }
}
