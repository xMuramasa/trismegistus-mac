import Foundation

/// An estimate of how much of the model's context window a conversation fills, like the Hermes CLI's status bar.
/// Hermes' API doesn't expose the live token count, so it is calibrated from the history (2026-10-31, two app
/// conversations: 42,959 chars → 38,924 tokens, 83,276 → 54,491, within ~1%).
public struct ContextEstimate: Equatable, Sendable {
    /// System prompt, tools and memory: a fresh conversation's first call was 22,584–22,952 tokens.
    public static let baseTokens = 22_400
    public static let tokensPerCharacter = 0.385
    /// A screenshot costs far more than its text; added per image part the history shows.
    public static let tokensPerImage = 1_600
    /// Hermes compresses at this share of the window (`compression.threshold`).
    public static let compressionThreshold = 0.5

    /// Characters the model sees: message content, tool call arguments and tool results.
    public private(set) var characters = 0
    public private(set) var images = 0
    /// Messages the estimate holds: the offset of the next page to fetch.
    public var count = 0

    public init() {}

    public init(history: [HistoryMessage]) {
        add(history)
        count = history.count
    }

    /// Adds messages; the caller keeps `count`.
    public mutating func add(_ messages: [HistoryMessage]) {
        for m in messages {
            let (text, pictures) = Self.measure(m.content)
            characters += text + m.toolCalls.reduce(0) { $0 + ($1.arguments?.count ?? 0) + $1.name.count }
            images += pictures
        }
    }

    public var tokens: Int {
        Self.baseTokens + Int((Double(characters) * Self.tokensPerCharacter).rounded()) + images * Self.tokensPerImage
    }

    /// The estimate as the meter shows it: to the nearest thousand (`22K`, not `22.4K`), since it is only an estimate.
    public var label: String { Self.format((tokens + 500) / 1_000 * 1_000) }

    /// Share of `window` used, rounded; nil without a window. Not capped: past 100 means the estimate overshoots.
    public func percent(of window: Int?) -> Int? {
        window.map { Int((Double(tokens) / Double($0) * 100).rounded()) }
    }

    public enum Band: Sendable, Equatable { case normal, warn, bad, critical }

    /// The CLI's bands by percent used: under 50 normal, 50–80 warn, over 80 bad, 95 and over critical.
    public static func band(percent: Int) -> Band {
        percent >= 95 ? .critical : percent > 80 ? .bad : percent >= 50 ? .warn : .normal
    }

    /// Whether Hermes compresses the history at the next call.
    public func isCompressing(window: Int?) -> Bool {
        window.map { Double(tokens) >= Double($0) * Self.compressionThreshold } ?? false
    }

    /// Segments filled of `width` for a percent, as the CLI rounds them.
    public static func filled(percent: Int, width: Int = 10) -> Int {
        Int((Double(max(0, min(100, percent))) / 100 * Double(width)).rounded())
    }

    /// `128K`, `1M`, `1.5M`, as `_format_context_length` in Hermes' banner.
    public static func format(_ tokens: Int) -> String {
        for (unit, div) in [("M", 1_000_000.0), ("K", 1_000.0)] where Double(tokens) >= div {
            let value = Double(tokens) / div
            let rounded = value.rounded()
            return abs(value - rounded) < 0.05 ? "\(Int(rounded))\(unit)" : String(format: "%.1f%@", value, unit)
        }
        return String(tokens)
    }

    /// A message's text length and image parts. Multimodal content comes as a JSON array of parts; base64 image data
    /// is not text the model reads, so only text parts count.
    private static func measure(_ content: String) -> (characters: Int, images: Int) {
        guard content.hasPrefix("["), content.contains("image"),
              let parts = try? Wire.decode([JSONValue].self, from: Data(content.utf8)) else { return (content.count, 0) }
        var characters = 0, images = 0
        for part in parts {
            guard case .object(let o) = part else { continue }
            if case .string(let type) = o["type"], type.contains("image") {
                images += 1
            } else if case .string(let text) = o["text"] {
                characters += text.count
            }
        }
        return (characters, images)
    }
}

/// Context window lengths from Hermes' own table (`agent/model_metadata.py`, `DEFAULT_CONTEXT_LENGTHS`), for the models
/// the relay lists (Anthropic, Claude subscription, GitHub Copilot). Longest key first, as Hermes matches.
public enum ContextWindow {
    private static let table: [(key: String, length: Int)] = [
        ("claude-fable", 1_000_000), ("claude-opus-5", 1_000_000), ("claude-sonnet-5", 1_000_000),
        ("claude-opus-4-8", 1_000_000), ("claude-opus-4.8", 1_000_000), ("claude-opus-4-7", 1_000_000),
        ("claude-opus-4.7", 1_000_000), ("claude-opus-4-6", 1_000_000), ("claude-opus-4.6", 1_000_000),
        ("claude-sonnet-4-6", 1_000_000), ("claude-sonnet-4.6", 1_000_000), ("claude", 200_000),
        ("gpt-5.6-luna", 1_050_000), ("gpt-5.6-terra", 1_050_000), ("gpt-5.6-sol", 1_050_000), ("gpt-5.5", 1_050_000),
        ("gpt-5.4-nano", 400_000), ("gpt-5.4-mini", 400_000), ("gpt-5.4", 1_050_000), ("gpt-5.3-codex-spark", 128_000),
        ("gpt-5.1-chat", 128_000), ("gpt-5", 400_000), ("gpt-4.1", 1_047_576), ("gpt-4", 128_000), ("gemini", 1_048_576),
    ].sorted { $0.key.count > $1.key.count }

    /// The window for a model id (`[1m]` = 1M, a `vendor/` prefix is ignored); nil when unknown.
    public static func length(for model: String?) -> Int? {
        guard var id = model?.lowercased(), !id.isEmpty else { return nil }
        if id.contains("[1m]") { return 1_000_000 }
        id = String(id.split(separator: "/").last ?? "")
        return table.first { id.contains($0.key) }?.length
    }
}
