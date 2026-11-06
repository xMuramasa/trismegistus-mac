import CoreText
import SwiftUI

/// A type role's face, size and setting; `TypeRole.spec` (generated in Tokens.swift) has one per role.
public struct TypeSpec: Sendable {
    public let family: FontFamily
    public let size: CGFloat
    public let weight: Int
    public let tracking: CGFloat
    public let uppercase: Bool

    static let weights: [Font.Weight: Int] = [.regular: 400, .medium: 500, .semibold: 600, .bold: 700, .heavy: 800, .black: 900]

    /// The families type roles asked for since the last reset (tests: the sidebar's text uses no mono face, #65).
    nonisolated(unsafe) static var drawn: Set<FontFamily> = []

    /// The bundled face, or its `weight` sibling (one of `weights`; JetBrains Mono stops at bold).
    public func font(weight: Font.Weight? = nil) -> Font {
        Fonts.register()
        Self.drawn.insert(family)
        let face = weight.flatMap { Self.weights[$0] }.flatMap { family.faces[$0] } ?? family.faces[self.weight]!
        return .custom(face, fixedSize: size)
    }
}

/// The bundled Inter and JetBrains Mono faces (Resources/Fonts, SIL OFL 1.1).
public enum Fonts {
    private static let registered: Void = {
        for url in Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [] {
            // Fails harmlessly when the face is already registered.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registers the faces for this process, once. Every type role calls it, so views needn't.
    public static func register() { _ = registered }
}

extension View {
    /// Font, tracking and case of a type role; `weight` picks a sibling face (a tool name in semibold mono).
    public func typeRole(_ role: TypeRole, weight: Font.Weight? = nil) -> some View {
        let spec = role.spec
        return font(spec.font(weight: weight)).tracking(spec.tracking).textCase(spec.uppercase ? .uppercase : nil)
    }

    /// The 1 px square edge every Endfield surface uses.
    func edge(_ color: Color) -> some View {
        overlay(Rectangle().strokeBorder(color, lineWidth: Stroke.hairline))
    }

    /// A shadow token's colour, blur and offset.
    public func shadow(_ token: ShadowToken) -> some View {
        shadow(color: token.color, radius: token.radius, x: token.x, y: token.y)
    }
}

/// The SF Symbols the app uses, by purpose.
public enum Symbol {
    public static let check = "checkmark"
    public static let close = "xmark"
    public static let clock = "clock"
    public static let copy = "doc.on.doc"
    public static let plus = "plus"
    public static let send = "arrow.up"
    public static let stop = "stop.fill"
    public static let retry = "arrow.clockwise"
    public static let link = "link"
    public static let unpair = "personalhotspot.slash"
    public static let steer = "arrow.turn.up.right"
    public static let terminal = "apple.terminal"
    public static let list = "list.bullet"
    public static let window = "macwindow"
    public static let telegram = "paperplane.fill"
    public static let cron = "calendar"
    public static let cli = "apple.terminal"
    public static let lock = "lock.fill"
    public static let pin = "pin.fill"
    public static let chevronRight = "chevron.right"
    public static let chevronDown = "chevron.down"
    public static let chevronUp = "chevron.up"
    /// A fold control's chevron: down on a folded item, up on an open one. Navigation links keep `chevronRight`.
    public static func fold(isOpen: Bool) -> String { isOpen ? chevronUp : chevronDown }
    public static let attach = "paperclip"
    /// the chat kind tabs (the app maps each kind to one)
    public static let kindApp = "macwindow"
    public static let kindTelegram = "paperplane"
    public static let kindTerminal = "terminal"
    public static let kindOneShot = "bolt"
    public static let kindAll = "square.stack"
    public static let kindOther = "bubble.left"
    public static let more = "ellipsis.circle"
}
