import Foundation
import Testing
@testable import TrismegistusKit

@Suite struct ConversationKindTests {
    @Test func everySourceHasItsKind() {
        #expect(ConversationKind(source: "api_server") == .app)
        #expect(ConversationKind(source: "telegram") == .telegram)
        #expect(ConversationKind(source: "cli") == .terminal)
        #expect(ConversationKind(source: "tui") == .terminal)
        #expect(ConversationKind(source: "oneshot") == .oneShot)
        #expect(ConversationKind(source: "cron") == .cron)
    }

    @Test func anUnknownSourceKeepsItsName() {
        #expect(ConversationKind(source: "discord") == .other("discord"))
        #expect(ConversationKind(source: "discord").name == "discord")
        #expect(ConversationKind(source: nil) == .other("unknown"))
        #expect(ConversationKind(source: "") == .other("unknown"))
        #expect(ConversationKind.other("discord").isInMore)
        #expect(ConversationKind.tabs.allSatisfy { !$0.isInMore })
    }

    @Test func rawValuesRoundTrip() {
        for kind in [ConversationKind.app, .telegram, .terminal, .oneShot, .cron, .other("slack"), .all] {
            #expect(ConversationKind(rawValue: kind.rawValue) == kind)
        }
        #expect(ConversationKind(rawValue: "") == nil)
        #expect(ConversationKind(rawValue: "source:") == nil)
    }

    @Test func includesByKindAndAllTakesEverything() {
        #expect(ConversationKind.terminal.includes("tui") && ConversationKind.terminal.includes("cli"))
        #expect(!ConversationKind.terminal.includes("api_server"))
        #expect(ConversationKind.all.includes("discord") && ConversationKind.all.includes(nil))
    }

    @Test func emptyTextNamesTheKind() {
        #expect(ConversationKind.terminal.emptyText == "No conversations from the terminal")
        #expect(ConversationKind.other("discord").emptyText == "No conversations from discord")
    }
}

@Suite struct ConversationKindSummaryTests {
    typealias Item = (source: String?, attention: ConversationKind.Attention?)

    private var items: [Item] {
        [("api_server", nil), ("api_server", .running), ("telegram", nil), ("cli", nil), ("tui", .approval),
         ("oneshot", nil), ("oneshot", nil), ("discord", nil), ("matrix", .running)]
    }

    @Test func countsPerKind() {
        let summary = ConversationKind.Summary(items)
        #expect(summary[.app].count == 2)
        #expect(summary[.telegram].count == 1)
        #expect(summary[.terminal].count == 2)
        #expect(summary[.oneShot].count == 2)
        #expect(summary[.cron].count == 0)
        #expect(summary[.all].count == 9)
    }

    @Test func moreListsOneShotsCronAndTheSourcesPresentThenAll() {
        #expect(ConversationKind.Summary(items).more == [.oneShot, .cron, .other("discord"), .other("matrix"), .all])
        #expect(ConversationKind.Summary([]).more == [.oneShot, .cron, .all])
    }

    @Test func aGoneSourceFallsBackToTheApp() {
        let summary = ConversationKind.Summary(items)
        #expect(summary.resolving(.other("discord")) == .other("discord"))
        #expect(summary.resolving(.other("slack")) == .app)
        #expect([ConversationKind.cron, .telegram, .all].allSatisfy { summary.resolving($0) == $0 })
    }

    @Test func approvalBeatsRunOnAChip() {
        let summary = ConversationKind.Summary(items)
        #expect(summary[.app].attention == .running)
        #expect(summary[.terminal].attention == .approval)
        #expect(summary[.telegram].attention == nil)
        #expect(summary[.all].attention == .approval)
        let both = ConversationKind.Summary([("cli", .running), ("cli", .approval), ("cli", .running)])
        #expect(both[.terminal].attention == .approval)
    }

    @Test func moreChipShowsTheStrongestMarkAmongItsEntries() {
        #expect(ConversationKind.Summary(items).moreAttention == .running)
        // An approval on a tab doesn't light MORE; All repeats the tabs and doesn't count.
        #expect(ConversationKind.Summary([("tui", .approval)]).moreAttention == nil)
        #expect(ConversationKind.Summary([("oneshot", .approval), ("matrix", .running)]).moreAttention == .approval)
    }

    @Test func attentionFromARow() {
        #expect(ConversationKind.Attention(isWaitingForApproval: true, isRunning: true) == .approval)
        #expect(ConversationKind.Attention(isWaitingForApproval: false, isRunning: true) == .running)
        #expect(ConversationKind.Attention(isWaitingForApproval: false, isRunning: false) == nil)
    }

    @Test func elsewhereNamesTheKindWithTheMostMatches() {
        let found = ConversationKind.elsewhere(["telegram", "cli", "tui"], current: .app)
        #expect(found?.kind == .terminal && found?.count == 2)
        #expect(ConversationKind.elsewhere(["telegram"], current: .app)?.kind == .telegram)
        // The tab has matches, there are none anywhere, or the tab is All: no row.
        #expect(ConversationKind.elsewhere(["api_server", "telegram"], current: .app) == nil)
        #expect(ConversationKind.elsewhere([], current: .app) == nil)
        #expect(ConversationKind.elsewhere(["telegram"], current: .all) == nil)
    }
}
