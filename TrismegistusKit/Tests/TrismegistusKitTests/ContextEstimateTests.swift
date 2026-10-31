import Foundation
import Testing
@testable import TrismegistusKit

private func message(_ id: Int, _ content: String, calls: [String] = []) throws -> HistoryMessage {
    var object: [String: JSONValue] = ["id": .number(Double(id)), "role": .string("user"), "content": .string(content)]
    if !calls.isEmpty {
        object["tool_calls"] = .array(calls.map { .object(["function": .object(["name": .string("terminal"), "arguments": .string($0)])]) })
    }
    return try Wire.decode(HistoryMessage.self, from: Wire.encode(JSONValue.object(object)))
}

/// A message of `n` characters.
private func text(_ n: Int) throws -> HistoryMessage { try message(1, String(repeating: "x", count: n)) }

@Suite struct ContextEstimateTests {
    @Test func realConversation() throws {
        // app-session.json: 23 messages, 3,462 characters of content, tool call names and arguments.
        let e = ContextEstimate(history: try appSession())
        #expect(e.count == 23 && e.characters == 3_462 && e.images == 0)
        #expect(e.tokens == 22_400 + 1_333)
        #expect(e.percent(of: 1_000_000) == 2)
        #expect(e.percent(of: nil) == nil)
    }

    @Test func calibrationPoints() throws {
        var e = ContextEstimate()
        e.add([try text(42_959)])
        #expect(abs(Double(e.tokens) / 38_924 - 1) < 0.01)
        var big = ContextEstimate()
        big.add([try text(83_276)])
        #expect(abs(Double(big.tokens) / 54_491 - 1) < 0.01)
    }

    @Test func addingTheNewMessagesGivesTheSameAsAll() throws {
        let all = try appSession()
        var e = ContextEstimate(history: Array(all.prefix(10)))
        e.add(Array(all.dropFirst(10)))
        #expect(e.characters == ContextEstimate(history: all).characters)
    }

    @Test func imagePartsCountApartFromTheirData() throws {
        let content = #"[{"type":"text","text":"look"},{"type":"image_url","image_url":{"url":"data:image/png;base64,AAAA"}}]"#
        var e = ContextEstimate()
        e.add([try message(1, content), try message(2, "[not json image")])
        #expect(e.images == 1 && e.characters == 4 + 15)
        #expect(e.tokens == 22_400 + 7 + 1_600)
    }

    @Test func toolCallArgumentsCount() throws {
        var e = ContextEstimate()
        e.add([try message(1, "", calls: ["ls -la"])])
        #expect(e.characters == "terminal".count + 6)
    }

    @Test func windowLookup() {
        #expect(ContextWindow.length(for: "claude-opus-5-5") == 1_000_000)
        #expect(ContextWindow.length(for: "claude-sonnet-5-5") == 1_000_000)
        #expect(ContextWindow.length(for: "claude-fable-5-1") == 1_000_000)
        #expect(ContextWindow.length(for: "anthropic/claude-opus-4.7") == 1_000_000)
        #expect(ContextWindow.length(for: "claude-haiku-4-5") == 200_000)
        #expect(ContextWindow.length(for: "claude-3-5-sonnet[1m]") == 1_000_000)
        #expect(ContextWindow.length(for: "Claude-Opus-4-7[1M]") == 1_000_000)
        #expect(ContextWindow.length(for: "gpt-5.4-mini") == 400_000)
        #expect(ContextWindow.length(for: "gpt-5.4") == 1_050_000)
        #expect(ContextWindow.length(for: "gemini-3-pro") == 1_048_576)
        #expect(ContextWindow.length(for: "mystery-model") == nil)
        #expect(ContextWindow.length(for: nil) == nil && ContextWindow.length(for: "") == nil)
    }

    @Test func bands() {
        #expect(ContextEstimate.band(percent: 0) == .normal && ContextEstimate.band(percent: 49) == .normal)
        #expect(ContextEstimate.band(percent: 50) == .warn && ContextEstimate.band(percent: 80) == .warn)
        #expect(ContextEstimate.band(percent: 81) == .bad && ContextEstimate.band(percent: 94) == .bad)
        #expect(ContextEstimate.band(percent: 95) == .critical && ContextEstimate.band(percent: 140) == .critical)
    }

    @Test func barAndCompression() throws {
        #expect(ContextEstimate.filled(percent: 46) == 5 && ContextEstimate.filled(percent: 2) == 0)
        #expect(ContextEstimate.filled(percent: 100) == 10 && ContextEstimate.filled(percent: 180) == 10)
        var e = ContextEstimate()
        e.add([try text(1_300_000)]) // 22,400 + 500,500 tokens
        #expect(e.isCompressing(window: 1_000_000) && !e.isCompressing(window: nil))
        #expect(!ContextEstimate().isCompressing(window: 1_000_000))
    }

    @Test func formatting() {
        #expect(ContextEstimate.format(22_000) == "22K" && ContextEstimate.format(92_000) == "92K")
        #expect(ContextEstimate.format(22_400) == "22.4K") // the CLI's own rounding
        #expect(ContextEstimate(history: []).label == "22K") // the estimate rounds to the thousand
        #expect(ContextEstimate.format(128_000) == "128K" && ContextEstimate.format(1_000_000) == "1M")
        #expect(ContextEstimate.format(1_500_000) == "1.5M")
        #expect(ContextEstimate.format(1_048_576) == "1M" && ContextEstimate.format(950) == "950")
        #expect(ContextEstimate.format(487_000) == "487K" && ContextEstimate.format(1_500) == "1.5K")
    }
}
