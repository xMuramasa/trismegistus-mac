import AppKit
import SwiftUI

/// The Endfield paper, after endfield-dotfiles' Quickshell `Background.qml`: a sparse field of small `+` marks (no grid
/// lines, Martin's choice for the app) and topographic contour lines around a point near the lower right.
/// Deterministic, no images.
/// Fills whatever size it is given; the app draws it once per window size (see `endfieldPaper()`).
public struct EndfieldBackground: View {
    /// Distance between crosses, across and down.
    static let crossSpacing = CGSize(width: 96, height: 64)

    public init() {}

    public var body: some View {
        Canvas { context, size in
            Self.draw(&context, size)
        }
        .background(Theme.paper)
    }

    private static func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height

        // Crosses only, no grid lines (Martin, 2026-10-31): a sparse field of small, thick `+`, rows wider apart
        // across than down (his sketch: one per ~14 characters, a row every 4 lines).
        var marks = Path()
        for x in stride(from: crossSpacing.width / 2, to: w, by: crossSpacing.width) {
            for y in stride(from: crossSpacing.height / 2, to: h, by: crossSpacing.height) {
                marks.move(to: CGPoint(x: x - 4, y: y)); marks.addLine(to: CGPoint(x: x + 4, y: y))
                marks.move(to: CGPoint(x: x, y: y - 4)); marks.addLine(to: CGPoint(x: x, y: y + 4))
            }
        }
        context.stroke(marks, with: .color(Theme.ink.opacity(0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .butt))

        let cx = w * 0.78, cy = h * 0.72
        for k in 1...18 {
            let r0 = Double(k) * Double(min(w, h)) * 0.045
            var contour = Path()
            for i in 0...180 {
                let t = Double(i) / 180 * 2 * .pi
                let r = r0 * (1 + 0.10 * sin(3 * t + Double(k) * 0.35) + 0.06 * sin(5 * t - Double(k) * 0.2) + 0.04 * sin(2 * t + 1.3))
                let p = CGPoint(x: cx + r * cos(t) * 1.35, y: cy + r * sin(t))
                if i == 0 { contour.move(to: p) } else { contour.addLine(to: p) }
            }
            context.stroke(contour, with: .color(Theme.rule.opacity(k % 5 == 0 ? 0.9 : 0.55)), lineWidth: 1)
        }
    }
}

/// The background drawn once at a window size.
public struct EndfieldPaper: @unchecked Sendable {
    let image: CGImage
    let size: CGSize
    let scale: CGFloat

    /// How many times any paper was drawn (tests: toggling a pane must not redraw it).
    nonisolated(unsafe) static var renderCount = 0

    @MainActor static func render(_ size: CGSize) -> EndfieldPaper? {
        renderCount += 1
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let renderer = ImageRenderer(content: EndfieldBackground().frame(width: size.width, height: size.height))
        renderer.scale = scale
        return renderer.cgImage.map { EndfieldPaper(image: $0, size: size, scale: scale) }
    }
}

private struct PaperKey: EnvironmentKey {
    static let defaultValue: EndfieldPaper? = nil
}

extension EnvironmentValues {
    var endfieldPaper: EndfieldPaper? {
        get { self[PaperKey.self] }
        set { self[PaperKey.self] = newValue }
    }
}

public extension View {
    /// Draws the Endfield background into an image at the window's size, for `EndfieldBackdrop` views below. Put it
    /// on the window's root view. A size counts once it has held for 150 ms: a
    /// resize draws once when it settles, and panes opening or closing inside the window never redraw it (a `Canvas`
    /// redrawn on every frame is what made those toggles stutter, #28). The window opens on plain paper for the first
    /// 150 ms: a window's size changes a few times while it is created. The size is read from a `GeometryReader` in a
    /// background, which takes the offered size and never feeds back into the layout.
    func endfieldPaper() -> some View { modifier(EndfieldPaperProvider()) }
}

struct EndfieldPaperProvider: ViewModifier {
    @State private var offered: CGSize?
    @State private var paper: EndfieldPaper?

    func body(content: Content) -> some View {
        content
            .environment(\.endfieldPaper, paper)
            .background {
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) { _, size in offered = size }
                }
                .ignoresSafeArea()
            }
            .task(id: offered) {
                guard let offered, offered != paper?.size else { return }
                try? await Task.sleep(for: .milliseconds(150))
                if !Task.isCancelled { paper = EndfieldPaper.render(offered) }
            }
    }
}

/// Paper with the window's Endfield background showing through, for the detail column and its empty states. The
/// image is window-sized and placed at minus this view's global origin, so the view only picks a window of it.
public struct EndfieldBackdrop: View {
    @Environment(\.endfieldPaper) private var paper

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            Theme.paper.overlay(alignment: .topLeading) {
                if let paper {
                    Image(decorative: paper.image, scale: paper.scale)
                        .frame(width: paper.size.width, height: paper.size.height)
                        .offset(x: -origin.x, y: -origin.y)
                }
            }
            .clipped()
        }
    }
}
