import SwiftUI

/// The type roles of the draft (system font; SF Mono for the mono roles).
public enum TypeRole: Sendable {
    case heading, title, headline, body, callout, caption, label, button, mono, monoSmall

    var font: Font {
        switch self {
        case .heading: .system(size: 15, weight: .bold).width(.expanded)
        case .title: .system(size: 15, weight: .semibold)
        case .headline: .system(size: 13, weight: .semibold)
        case .body: .system(size: 13)
        case .callout: .system(size: 12)
        case .caption: .system(size: 11)
        case .label: .system(size: 10, weight: .semibold)
        case .button: .system(size: 12, weight: .semibold)
        case .mono: .system(size: 12, design: .monospaced)
        case .monoSmall: .system(size: 11, design: .monospaced)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .heading: 0.6
        case .label: 0.8
        case .button: 0.3
        default: 0
        }
    }

    var uppercase: Bool { self == .heading || self == .label }
}

extension View {
    /// Font, tracking and case of a type role.
    public func typeRole(_ role: TypeRole) -> some View {
        font(role.font).tracking(role.tracking).textCase(role.uppercase ? .uppercase : nil)
    }

    /// The 1 px square edge every Endfield surface uses.
    func edge(_ color: Color) -> some View {
        overlay(Rectangle().strokeBorder(color, lineWidth: 1))
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
    public static let chevronRight = "chevron.right"
    public static let chevronDown = "chevron.down"
}

/// The window's top bar (Martin, 2026-10-31, after Arknights' in-game bars; it overrides Endfield's "no gradients"):
/// left to right Endfield `secondary` → `dark-panel` → `ink` (the Penpot library's colours).
extension Theme {
    public static let steel = Theme.secondary
    public static let steelDeep = Theme.darkPanel
    public static let steelEnd = Theme.ink
    /// Text and icons on the steel strip.
    public static let onSteel = Color(hex: 0xE9E9E9)
    /// The 1 pt rule under the strip: darker than its darkest point.
    public static let steelRule = Theme.ink
}
