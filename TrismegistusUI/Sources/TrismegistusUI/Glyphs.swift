import AppKit
import SwiftUI

extension Path {
    /// Absolute SVG path data with M, H, V, L and Z only (all the glyphs need).
    static func svg(_ d: String) -> Path {
        var spaced = ""
        for ch in d {
            if ch.isLetter { spaced += " \(ch) " } else { spaced.append(ch) }
        }
        let tokens = spaced.split(whereSeparator: { $0 == " " || $0 == "," })
        var path = Path()
        var cur = CGPoint.zero
        var i = 0
        func num() -> CGFloat {
            defer { i += 1 }
            return CGFloat(Double(tokens[i]) ?? 0)
        }
        while i < tokens.count {
            let command = tokens[i]
            i += 1
            switch command {
            case "M":
                cur = CGPoint(x: num(), y: num())
                path.move(to: cur)
            case "L":
                cur = CGPoint(x: num(), y: num())
                path.addLine(to: cur)
            case "H":
                cur.x = num()
                path.addLine(to: cur)
            case "V":
                cur.y = num()
                path.addLine(to: cur)
            case "Z":
                path.closeSubpath()
            default:
                break
            }
        }
        return path
    }
}

/// SVG path data scaled from its `box` into the shape's rect.
struct SVGShape: Shape {
    let d: String
    let box: CGSize

    func path(in rect: CGRect) -> Path {
        Path.svg(d).applying(
            CGAffineTransform(translationX: rect.minX, y: rect.minY)
                .scaledBy(x: rect.width / box.width, y: rect.height / box.height))
    }
}

enum GlyphData {
    static let outer = "M2 2H12L16 6V16H2Z"
    static let t = "M5 5H12V7H9.5V13H7.5V7H5Z"
    static let mark = outer + " " + t
    static let bars = ["M18 10H19.5V16H18Z", "M20.5 5H22V16H20.5Z"]
    static let sourceMark = "M1.5 1.5H9.5L12.5 4.5V12.5H1.5Z M4 4H9.75V5.75H7.75V10.5H6V5.75H4Z"
    /// The box `sourceMark` is drawn in.
    static let sourceBox = CGSize(width: 14, height: 14)
    /// The menu bar glyph's outline stroke (disconnected) and approval dot.
    static let outlineWidth: CGFloat = 1.5
    static let approvalDot = CGRect(x: 16.5, y: 1, width: 5, height: 5)
}

/// The T mark of the Trismegistus source (14×14, template-friendly: draws in the foreground color).
public struct TMark: View {
    public init() {}

    public var body: some View {
        SVGShape(d: GlyphData.sourceMark, box: GlyphData.sourceBox)
            .fill(style: FillStyle(eoFill: true))
            .frame(width: Icon.l, height: Icon.l)
    }
}

/// Where a session comes from; drawn as an icon.
public enum SessionSource: Sendable {
    case trismegistus, telegram, cron, cli
}

public struct SourceIcon: View {
    let source: SessionSource

    public init(_ source: SessionSource) { self.source = source }

    public var body: some View {
        Group {
            switch source {
            case .trismegistus: TMark()
            case .telegram: Image(systemName: Symbol.telegram)
            case .cron: Image(systemName: Symbol.cron)
            case .cli: Image(systemName: Symbol.cli)
            }
        }
        .font(.system(size: Icon.m))
        .frame(width: Icon.l, height: Icon.l)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch source {
        case .trismegistus: "Trismegistus"
        case .telegram: "Telegram"
        case .cron: "Cron"
        case .cli: "CLI"
        }
    }
}

public enum GlyphState: CaseIterable, Sendable {
    case disconnected, idle, running, approval
}

/// The menu bar glyph as a template `NSImage` (22×18 pt): outline when disconnected, solid mark when idle, bars for
/// a run in progress, a dot for an approval waiting. State is shape, never color.
public enum MenuBarGlyph {
    public static let size = NSSize(width: 22, height: 18)

    public static func image(_ state: GlyphState) -> NSImage {
        let image = NSImage(size: size, flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            if state == .disconnected {
                ctx.addPath(Path.svg(GlyphData.outer).cgPath)
                ctx.setLineWidth(GlyphData.outlineWidth)
                ctx.strokePath()
                ctx.addPath(Path.svg(GlyphData.t).cgPath)
                ctx.fillPath()
            } else {
                ctx.addPath(Path.svg(GlyphData.mark).cgPath)
                ctx.fillPath(using: .evenOdd)
            }
            if state == .running {
                for bar in GlyphData.bars {
                    ctx.addPath(Path.svg(bar).cgPath)
                    ctx.fillPath()
                }
            }
            if state == .approval {
                ctx.fillEllipse(in: GlyphData.approvalDot)
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

#Preview("Glyphs") {
    HStack(spacing: 16) {
        ForEach(GlyphState.allCases, id: \.self) { state in
            Image(nsImage: MenuBarGlyph.image(state)).renderingMode(.template)
        }
        SourceIcon(.trismegistus)
        SourceIcon(.telegram)
        SourceIcon(.cron)
        SourceIcon(.cli)
    }
    .foregroundStyle(Ink.text.primary)
    .padding().background(Ink.surface.window)
}
