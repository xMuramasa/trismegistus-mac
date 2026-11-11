import SwiftUI

// #74, design 16 (`design/opendesign/16-qol/`): an answer's thinking (16a) and the effort pill (16d).

/// `∴ THINKING · 4 STEPS ⌄` in an answer's chip row, before the commands chip, in its style (`.chip`); framed in ink
/// while its panel is open. `∴` (U+2234) is the system font's: Inter has none.
public struct ThinkingChip: View {
    let steps: Int
    @Binding var isOpen: Bool

    public init(steps: Int, isOpen: Binding<Bool>) {
        self.steps = steps
        self._isOpen = isOpen
    }

    public var body: some View {
        Button { isOpen.toggle() } label: {
            HStack(spacing: Space.s) {
                Text(verbatim: "∴").font(.system(size: Icon.m, weight: .semibold)).accessibilityHidden(true)
                Text(verbatim: "Thinking · \(steps) \(steps == 1 ? "step" : "steps")").typeRole(.controlLabel).monospacedDigit()
                    .lineLimit(1)
                Image(systemName: isOpen ? Symbol.chevronUp : Symbol.chevronDown).font(.system(size: Icon.xxs, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Ink.text.primary)
            .padding(.horizontal, Space.s)
            .frame(height: Size.cardHeader)
            .fixedSize()
            .rounded(Radius.control, fill: isOpen ? Ink.surface.raised : Ink.surface.control, edge: isOpen ? Ink.line.strong : Ink.line.rule)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? "Open" : "Folded")
    }
}

/// The unfolded thinking (`.thk`): one row per step, in order, split by `step` hairlines: its number, the thought (folded
/// to 3 lines with an underlined `more`), and what it led to (`→ terminal · ls`, `→ answer`).
public struct ThinkingPanel: View {
    public struct Step: Sendable, Equatable {
        public var thought: String
        /// nil: the step led to the answer.
        public var tool: String?
        public var detail: String

        public init(thought: String, tool: String? = nil, detail: String = "") {
            self.thought = thought
            self.tool = tool
            self.detail = detail
        }
    }

    let steps: [Step]

    public init(steps: [Step]) { self.steps = steps }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i > 0 { Rectangle().fill(Ink.line.step).frame(height: Stroke.hairline) }
                row(i + 1, step)
            }
        }
        .padding(.vertical, Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .rounded(Radius.control, fill: Ink.surface.thinking, edge: Ink.line.rule)
    }

    private func row(_ number: Int, _ step: Step) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(verbatim: number < 10 ? "0\(number)" : "\(number)").typeRole(.stepNumber).monospacedDigit()
                .foregroundStyle(Ink.text.muted)
                .frame(width: Size.thinking.number, alignment: .leading)
            FoldingThought(text: step.thought).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 0) {
                Text(verbatim: "→ ").typeRole(.caption)
                Text(verbatim: step.tool ?? "answer").typeRole(.stepTool).foregroundStyle(Ink.text.secondary)
                if step.tool != nil, !step.detail.isEmpty { Text(verbatim: " · " + step.detail).typeRole(.caption) }
            }
            .foregroundStyle(Ink.text.muted)
            .lineLimit(1)
            .fixedSize()
        }
        .padding(.horizontal, Space.m).padding(.vertical, Space.s)
        .accessibilityElement(children: .combine)
    }
}

/// A thought: 13 pt secondary at 1.45 line height, folded to `Size.thinking.lines` until its `more` is clicked.
struct FoldingThought: View {
    let text: String
    @State private var isOpen = false
    @State private var shown: CGFloat = 0
    @State private var full: CGFloat = 0

    /// The text runs past its folded lines.
    var folds: Bool { full > shown + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            thought
                .lineLimit(isOpen ? nil : Int(Size.thinking.lines))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shown = $0 }
                .background(alignment: .topLeading) {
                    thought.fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { full = $0 }
                }
            if !isOpen, folds {
                Button { isOpen = true } label: {
                    Text(verbatim: "more").underline(true, color: Ink.line.rule).typeRole(.body).foregroundStyle(Ink.text.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show the whole thought")
            }
        }
    }

    private var thought: some View {
        Text(verbatim: text).typeRole(.body).lineSpacing(Size.thinking.lineGap).foregroundStyle(Ink.text.secondary)
            .textSelection(.enabled)
    }
}

/// An answer's chip row with its thinking chip first, then `trailing` (the commands chip), and the panel under it while open.
public struct ThinkingBlock<Trailing: View>: View {
    let steps: [ThinkingPanel.Step]
    @Binding var isOpen: Bool
    let trailing: Trailing

    public init(steps: [ThinkingPanel.Step], isOpen: Binding<Bool>, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.steps = steps
        self._isOpen = isOpen
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                ThinkingChip(steps: steps.count, isOpen: $isOpen)
                trailing
            }
            if isOpen { ThinkingPanel(steps: steps) }
        }
    }
}

/// The header's dropdown pills (`.pill`): the model's and the effort's (`∴ High`). Control height, pill corners, white
/// with a rule hairline (on steel: clear with a light outline). `placeholder` (`∴ Default`, nothing chosen) is secondary.
public struct PillLabel: View {
    let text: String
    let glyph: String?
    let placeholder: Bool
    @Environment(\.onSteel) private var onSteel

    public init(_ text: String, glyph: String? = nil, placeholder: Bool = false) {
        self.text = text
        self.glyph = glyph
        self.placeholder = placeholder
    }

    public var body: some View {
        HStack(spacing: Space.xs) {
            if let glyph { Text(verbatim: glyph).font(.system(size: Icon.therefore, weight: .semibold)).accessibilityHidden(true) }
            if !text.isEmpty {
                Text(verbatim: text).typeRole(.callout).lineLimit(1)
                    .foregroundStyle(placeholder ? (onSteel ? Ink.text.onDark.opacity(Opacity.secondaryOnDark) : Ink.text.secondary) : (onSteel ? Ink.text.onDark : Ink.text.primary))
            }
            Image(systemName: Symbol.chevronDown).font(.system(size: Icon.xs, weight: .semibold))
        }
        .foregroundStyle(onSteel ? Ink.text.onDark : Ink.text.primary)
        .padding(.leading, Space.m).padding(.trailing, Space.s).frame(height: Size.control)
        .rounded(Radius.pill, fill: onSteel ? .clear : Ink.surface.raised, edge: onSteel ? Ink.line.outlineOnDark : Ink.line.rule)
        .contentShape(Rectangle())
    }
}

/// The conversation header's narrow-window rule (#74): the title keeps `Size.thinking.titleMin`. First the context meter
/// shows only its percentage (stage 1), then the model pill drops its `claude-` (stage 2), then the effort pill shows only
/// its glyph, the level in its tooltip and menu (stage 3, Hermes' call at review: at the 1180 pt window stage 2 left the
/// title ~22 pt). Nothing hides; past stage 3 the title takes what is left (~85 pt at 1180). Fed the header's width and the trailing part's at the current stage, it steps one stage at a time and
/// remembers each stage's width to step back when the window widens.
public struct HeaderFit: Sendable, Equatable {
    public private(set) var stage = 0
    private var widths: [Int: CGFloat] = [:]

    public init() {}

    public var meterCompact: Bool { stage >= 1 }
    public var modelShort: Bool { stage >= 2 }
    public var effortShort: Bool { stage >= 3 }

    /// What the header spends besides its title and trailing part: its insets, the avatar and the gaps after both.
    public static let chrome = Space.xxl + Size.avatar.header + 2 * Space.m + Space.l

    public static func titleRoom(width: CGFloat, trailing: CGFloat) -> CGFloat { width - chrome - trailing }

    public mutating func fit(width: CGFloat, trailing: CGFloat) {
        widths[stage] = trailing
        if Self.titleRoom(width: width, trailing: trailing) < Size.thinking.titleMin {
            if stage < 3 { stage += 1 }
        } else if stage > 0, let wider = widths[stage - 1], Self.titleRoom(width: width, trailing: wider) >= Size.thinking.titleMin {
            stage -= 1
        }
    }

    /// The model's label at this stage: without `claude-` at stage 2.
    public func model(_ label: String) -> String {
        modelShort && label.hasPrefix("claude-") ? String(label.dropFirst("claude-".count)) : label
    }
}

/// `DetailHeader` with the narrow-window rule: `trailing` gets the fit to apply and is measured with it.
public struct FittedHeader<Mark: View, Title: View, Subtitle: View, Trailing: View>: View {
    let mark: Mark
    let title: Title
    let subtitle: Subtitle
    let trailing: (HeaderFit) -> Trailing
    @State private var fit = HeaderFit()
    @State private var width: CGFloat = 0
    @State private var trailingWidth: CGFloat = 0

    public init(
        @ViewBuilder mark: () -> Mark, @ViewBuilder title: () -> Title, @ViewBuilder subtitle: () -> Subtitle,
        @ViewBuilder trailing: @escaping (HeaderFit) -> Trailing
    ) {
        self.mark = mark()
        self.title = title()
        self.subtitle = subtitle()
        self.trailing = trailing
    }

    public var body: some View {
        DetailHeader { mark } title: { title } subtitle: { subtitle } trailing: {
            HStack(spacing: Space.s) { trailing(fit) }
                // The stage is in the reading so a stage that changes nothing still reports, and the next one is tried.
                .onGeometryChange(for: [CGFloat].self) { [stage = fit.stage] in [$0.size.width, CGFloat(stage)] } action: {
                    trailingWidth = $0[0]
                    refit()
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
            width = $0
            refit()
        }
    }

    private func refit() {
        if width > 0, trailingWidth > 0 { fit.fit(width: width, trailing: trailingWidth) }
    }
}
