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
        let label = HStack(spacing: 6) {
            Text(summary(window: window, percent: percent))
                .typeRole(.monoSmall).foregroundStyle(color(band, text: true)).lineLimit(1).fixedSize()
            if let percent { SegmentBar(percent: percent, color: color(band, text: false)) }
        }
        .contentShape(Rectangle())
        Group {
            if !loaded {
                EmptyView()
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

    private func color(_ band: ContextEstimate.Band, text: Bool) -> Color {
        switch band {
        case .normal: text ? Theme.secondary : Theme.ink
        case .warn: text ? Theme.ink : Theme.yellow
        case .bad, .critical: Theme.red
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

/// Ten segments, the filled ones in `color`, with a tick between the fifth and sixth where Hermes compresses.
private struct SegmentBar: View {
    let percent: Int
    let color: Color

    var body: some View {
        let filled = ContextEstimate.filled(percent: percent)
        HStack(spacing: 1) {
            ForEach(0..<10, id: \.self) { i in
                Rectangle().fill(i < filled ? color : Theme.sunken)
                    .overlay(Rectangle().strokeBorder(i < filled ? Theme.ink : Theme.rule, lineWidth: 1))
                    .frame(width: 5, height: 10)
            }
        }
        .overlay { Rectangle().fill(Theme.ink).frame(width: 1, height: 16) }
        .accessibilityHidden(true)
    }
}
