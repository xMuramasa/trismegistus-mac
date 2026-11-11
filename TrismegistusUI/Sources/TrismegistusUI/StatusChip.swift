import SwiftUI

/// A short status word (#57, `.chip`): label type on a kind's fill. With `hairlineControls` (#69, `.rtag`) a light chip
/// with a rule hairline, `tag` corners and a 2 pt bar in the kind's colour at its left edge, the word in ink.
public struct StatusChip: View {
    public enum Kind: Sendable {
        case ok, warn, err, neutral, update
    }

    let text: String
    let kind: Kind
    @Environment(\.hairlineControls) private var hairline

    public init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    private var ink: (fill: Color, text: Color) {
        switch kind {
        case .ok: (Ink.status.online, Ink.text.primary)
        case .warn: (Ink.surface.darkPanel, Ink.status.warn)
        case .err: (Ink.status.bad, Ink.text.primary)
        case .neutral: (Ink.surface.sunken, Ink.text.secondary)
        case .update: (Ink.surface.raised, Ink.text.link)
        }
    }

    /// The bar's colour in the hairline chip.
    private var bar: Color {
        switch kind {
        case .ok: Ink.status.ok
        case .warn: Ink.selection
        case .err: Ink.status.error
        case .neutral: Ink.text.muted
        case .update: Ink.text.link
        }
    }

    public var body: some View {
        if hairline {
            Text(verbatim: text).typeRole(.tag).foregroundStyle(Ink.text.primary).lineLimit(1).fixedSize()
                .padding(.leading, Stroke.accent + Space.xs).padding(.trailing, Space.xs)
                .frame(minHeight: Size.sticker.height)
                .background(Ink.surface.raised)
                .overlay(alignment: .leading) { Rectangle().fill(bar).frame(width: Stroke.accent) }
                .clipShape(RoundedRectangle(cornerRadius: Radius.tag, style: .continuous))
                .edge(Ink.line.rule, radius: Radius.tag)
        } else {
            let ink = ink
            Text(verbatim: text).typeRole(.label).foregroundStyle(ink.text).lineLimit(1).fixedSize()
                .padding(.horizontal, Space.xs)
                .frame(minHeight: Size.chip)
                .background(ink.fill)
                .overlay { if kind == .update { Rectangle().strokeBorder(Ink.text.link, lineWidth: Stroke.hairline) } }
        }
    }
}

/// A failed command's `exit N` (#57, `.exit`): terminal-red on raised, so it reads on the orange card header; with
/// `hairlineControls` (#69) the red word alone, in Inter.
public struct ExitChip: View {
    let code: Int
    @Environment(\.hairlineControls) private var hairline

    public init(_ code: Int) { self.code = code }

    public var body: some View {
        Text(verbatim: "exit \(code)").typeRole(hairline ? .caption : .monoSmall).foregroundStyle(Ink.status.error).lineLimit(1).fixedSize()
            .padding(.horizontal, hairline ? 0 : Space.xs)
            .frame(minHeight: Size.chip)
            .background(hairline ? .clear : Ink.surface.raised)
    }
}
