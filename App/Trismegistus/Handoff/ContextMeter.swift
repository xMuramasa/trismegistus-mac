import SwiftUI
import TrismegistusKit
import TrismegistusUI

/// The conversation's context window like the Hermes CLI's status bar: `≈ 92K / 1M · 9%`, a 10-segment bar and a tick
/// where Hermes compresses (50%). Estimated from the history (`ContextEstimate`): fetched once, then only the messages
/// after the ones already counted, again when the conversation grows or a run ends. From 50% it offers the handoff.
struct ContextMeter: View {
    /// The thread's newest part: only it counts after a handoff.
    let info: SessionInfo
    let onHandOff: @MainActor () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.onSteel) private var onSteel
    @State private var estimate = ContextEstimate()
    @State private var estimateID: String?
    @State private var loaded = false

    private struct Trigger: Hashable { var id: String; var messageCount: Int?; var running: Bool }

    private var running: Bool { model.store?.sessions[info.id]?.run != nil || model.store?.overview[info.id]?.run != nil }
    private var modelID: String? {
        info.isReadOnly ? info.model : model.store?.model(for: info.id)?.model ?? info.model
    }

    var body: some View {
        let window = ContextWindow.length(for: modelID)
        let percent = estimate.percent(of: window)
        let band = percent.map(ContextEstimate.band) ?? .normal
        let compressing = estimate.isCompressing(window: window)
        let canHandOff = compressing && SessionCapabilities(info).canHandOff
        let label = HStack(spacing: Space.s) {
            Text(summary(window: window, percent: percent))
                .typeRole(.monoSmall).foregroundStyle(color(band, text: true)).lineLimit(1).fixedSize()
            if let percent { SegmentBar(percent: percent, color: color(band, text: false)) }
        }
        .contentShape(Rectangle())
        Group {
            if !loaded {
                // Not `EmptyView`: SwiftUI never runs a `.task` attached to an empty view, so the estimate never
                // loaded and the meter never showed.
                Color.clear.frame(width: 0, height: 0)
            } else if canHandOff {
                Button(action: onHandOff) { label }.buttonStyle(.plain)
            } else {
                label
            }
        }
        .help(tooltip(window: window, compressing: compressing, canHandOff: canHandOff))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(window: window, percent: percent))
        .task(id: Trigger(id: info.id, messageCount: info.messageCount, running: running)) { await load() }
    }

    private func summary(window: Int?, percent: Int?) -> String {
        guard let window, let percent else { return "≈ \(estimate.label)" }
        return "≈ \(estimate.label) / \(ContextEstimate.format(window)) · \(percent)%"
    }

    private func tooltip(window: Int?, compressing: Bool, canHandOff: Bool) -> String {
        guard let window else { return "Estimated from the history. The context window of this model isn't known." }
        let half = ContextEstimate.format(Int(Double(window) * ContextEstimate.compressionThreshold))
        var text = "Estimated from the history; Hermes compresses at 50% (\(half))."
        if compressing { text += " Hand off to start smaller." + (canHandOff ? " Click to hand off." : "") }
        return text
    }

    private func accessibility(window: Int?, percent: Int?) -> String {
        guard let window, let percent else { return "Context about \(estimate.label) tokens" }
        return "Context about \(estimate.label) of \(ContextEstimate.format(window)) tokens, \(percent) percent"
    }

    /// On the steel strip the text stays light and the bar carries the band (red text doesn't read on steel).
    private func color(_ band: ContextEstimate.Band, text: Bool) -> Color {
        if onSteel {
            return switch band {
            case .normal: text ? Ink.text.onDark.opacity(Opacity.secondaryOnDark) : Ink.text.onDark
            case .warn: text ? Ink.text.onDark : Ink.status.warn
            case .bad, .critical: text ? Ink.text.onDark : Ink.status.bad
            }
        }
        return switch band {
        case .normal: text ? Ink.text.secondary : Ink.line.strong
        case .warn: text ? Ink.text.primary : Ink.status.warn
        case .bad, .critical: Ink.text.error
        }
    }

    private func load() async {
        guard let store = model.store else { return }
        var e = estimate
        // Another conversation, or fewer messages than counted (the history was compressed): start over.
        if estimateID != info.id || (info.messageCount ?? e.count) < e.count {
            e = ContextEstimate()
            loaded = false
        }
        var failed = false
        while true {
            do {
                let page = try await store.rest.messages(info.id, offset: e.count, limit: 200)
                e.add(page.messages)
                e.count += page.count
                if page.count < 200 { break }
            } catch {
                failed = true
                break
            }
        }
        // A cancelled load (the conversation changed) leaves what was shown as it was.
        guard !Task.isCancelled else { return }
        estimate = e
        estimateID = info.id
        loaded = loaded || !failed
    }
}

/// Ten segments, the filled ones in `color`. On the steel strip the empty ones are outlines. (The tick at 50%, where
/// Hermes compresses, is gone: Martin found it noise; the tooltip still says it.)
private struct SegmentBar: View {
    let percent: Int
    let color: Color

    @Environment(\.onSteel) private var onSteel

    var body: some View {
        let filled = ContextEstimate.filled(percent: percent)
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { i in
                Rectangle().fill(i < filled ? color : onSteel ? .clear : Ink.surface.sunken)
                    .overlay(Rectangle().strokeBorder(i < filled ? Ink.line.strong : onSteel ? Ink.line.outlineOnDark : Ink.line.rule, lineWidth: Stroke.hairline))
                    .frame(width: Size.meterCell.width, height: Size.meterCell.height)
            }
        }
        .accessibilityHidden(true)
    }
}
