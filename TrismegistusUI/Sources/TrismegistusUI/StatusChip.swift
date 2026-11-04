import SwiftUI

/// A short status word (#57, `.chip`): label type on a kind's fill.
public struct StatusChip: View {
    public enum Kind: Sendable {
        case ok, warn, err, neutral, update
    }

    let text: String
    let kind: Kind

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

    public var body: some View {
        let ink = ink
        Text(verbatim: text).typeRole(.label).foregroundStyle(ink.text).lineLimit(1).fixedSize()
            .padding(.horizontal, Space.xs)
            .frame(minHeight: Size.chip)
            .background(ink.fill)
            .overlay { if kind == .update { Rectangle().strokeBorder(Ink.text.link, lineWidth: Stroke.hairline) } }
    }
}

/// A failed command's `exit N` (#57, `.exit`): terminal-red on raised, so it reads on the orange card header.
public struct ExitChip: View {
    let code: Int

    public init(_ code: Int) { self.code = code }

    public var body: some View {
        Text(verbatim: "exit \(code)").typeRole(.monoSmall).foregroundStyle(Ink.status.error).lineLimit(1).fixedSize()
            .padding(.horizontal, Space.xs)
            .frame(minHeight: Size.chip)
            .background(Ink.surface.raised)
    }
}
