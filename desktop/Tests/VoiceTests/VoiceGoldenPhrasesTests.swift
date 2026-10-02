import Testing
@testable import Voice
import Core

/// Voice regression table. Every phrase the owner has verified by
/// microphone, plus the recognizer's usual mishearings, with the exact
/// result it must keep producing. If a grammar edit changes one of these,
/// this fails — change the table only on purpose.
@Suite("Voice golden phrases")
struct VoiceGoldenPhrasesTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func route(_ s: String) -> VoiceIntent { VoiceIntentRouter.match(text: s, context: .empty) }

    @Test("Pages by voice, as said and as misheard")
    func pages() {
        let table: [(String, VoiceDestination)] = [
            ("go to dashboard", .dashboard), ("go to the balance sheet", .balanceSheetReport), ("go to month end close", .monthEndClose),
            ("go to profit and loss", .profitAndLossReport), ("open aged payables", .agedPayablesReport), ("pull up aged receivables", .agedReceivablesReport),
            ("take me to client diagnostics", .clientDiagnostics), ("go to search by amount", .amountSearch), ("go to intake questions", .intakeQuestions),
            ("hey moneypenny go to cash flow forecast", .cashFlowForecast), ("open cleanup assessment please", .cleanupAssessment), ("go to bank feed cleanup", .bankFeedCleanup),
            ("go to scope and period lock", .scopeAndPeriodLock), ("go to audio settings", .audioSettings), ("go to voice history", .aiConversations), ("go to ai conversations", .aiConversations)
        ]
        for (phrase, destination) in table { #expect(route(phrase) == .navigate(destination), "\(phrase)") }
    }

    @Test("Finding groups, finding by amount, searches")
    func findings() {
        for p in ["pull up the duplicates", "show me the duplicates", "open duplicate transactions"] { #expect(route(p) == .findingsGroup(.duplicates), "\(p)") }
        #expect(route("show me the uncategorized transactions") == .findingsGroup(.miscategorizedOrUncategorized))
        #expect(route("pull up the negative balances") == .findingsGroup(.negativeBalance))
        #expect(route("open the $1,420 one") == .openFindingMatching(amount: usd(142_000), text: "$1,420 one"))
        #expect(route("find 1420") == .searchAmount(usd(142_000)))
        #expect(route("find fourteen twenty") == .searchAmount(usd(142_000)))
        #expect(route("search for $500") == .searchAmount(usd(50_000)))
    }

    @Test("Balances, what we owe (including 'own'), KPIs, freshness")
    func data() {
        #expect(route("what's the balance of the sweeper checking account") == .accountBalance("sweeper checking"))
        for p in ["what do we owe norton lumber", "what do we own norton lumber", "how much do we owe norton lumber"] { #expect(route(p) == .vendorOwed("norton lumber"), "\(p)") }
        #expect(route("what's our revenue this month") == .kpi(.revenue, .current))
        #expect(route("what was net income last month") == .kpi(.netIncome, .priorMonth))
        #expect(route("when did we last sync") == .freshness)
    }

    @Test("Totals with no vendor named: what we owe, what we're owed")
    func totals() {
        for p in ["what do we owe", "what do we own", "how much do we owe", "What do we owe?", "what bills are due", "what's our accounts payable"] { #expect(route(p) == .totalOwed, "\(p)") }
        for p in ["what are we owed", "who owes us", "how much are we owed", "what do customers owe us"] { #expect(route(p) == .totalReceivable, "\(p)") }
        #expect(route("what do we owe norton lumber") == .vendorOwed("norton lumber"))
        #expect(route("what do we owe in total") == .totalOwed)
    }

    @Test("Back, forward, hands-free correction")
    func control() {
        #expect(route("go back") == .goBack)
        #expect(route("go forward") == .goForward)
        for p in ["try again", "that's wrong", "never mind", "scratch that"] { #expect(route(p) == .retry, "\(p)") }
    }

    @Test("Open-ended questions are NOT grabbed by the grammar (they belong to the model)")
    func leftToModel() {
        for p in ["why is this flagged", "why did expenses jump this month compared to last", "summarize the month for the client", "what does opening balance equity mean"] {
            switch route(p) {
            case .unrecognized, .explainCurrent: break   // model path, or the explain-this-finding path
            default: Issue.record("\(p) → \(route(p))")
            }
        }
    }

    @Test("Every sidebar title is unique and spoken forms never collide across destinations")
    func menuIntegrity() {
        let titles = VoiceDestination.allCases.map { $0.menuTitle.lowercased() }
        #expect(Set(titles).count == titles.count)
        var seen: [String: VoiceDestination] = [:]
        for d in VoiceDestination.allCases { for form in VoiceIntentRouter.spokenForms(of: d.menuTitle) {
            if let other = seen[form], other != d { Issue.record("'\(form)' maps to both \(other) and \(d)") }
            seen[form] = d
        } }
    }
}
