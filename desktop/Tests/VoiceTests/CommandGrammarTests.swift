import Testing
@testable import Voice
import Core

@Suite("CommandGrammar — spoken commands resolved in code")
struct CommandGrammarTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func parse(_ s: String) -> VoiceIntent? { CommandGrammar.parse(s) }

    @Test("Every sidebar destination accepts natural opening verbs")
    func allNavigationPhrases() {
        for destination in VoiceDestination.allCases {
            for verb in ["go to", "open", "open up", "show", "show me", "display", "pull up", "bring up", "take me to", "navigate to", "get me"] {
                let phrase = "please \(verb) the \(destination.menuTitle) for me"
                #expect(VoiceIntentRouter.match(text: phrase, context: .empty) == .navigate(destination), "\(phrase)")
            }
        }
        #expect(VoiceIntentRouter.match(text: "show balance sheet", context: .empty) == .navigate(.balanceSheetReport))
        for phrase in ["go to month and clothes", "open month end clothes", "show month in clothes", "take me to end clothes"] {
            #expect(VoiceIntentRouter.match(text: phrase, context: .empty) == .navigate(.monthEndClose), "\(phrase)")
        }
        #expect(VoiceIntentRouter.match(text: "display the duplicates", context: .empty) == .findingsGroup(.duplicates))
        #expect(VoiceIntentRouter.match(text: "show me a chart of income vs expenses", context: .empty) == .chart(.incomeVsExpenses))
    }

    @Test("Currency is spoken as grouped amounts")
    func spokenCurrency() {
        #expect(VoiceSpeechFormatter.formatCurrency("$19,200.00") == "nineteen thousand two hundred dollars")
        #expect(VoiceSpeechFormatter.formatCurrency("($3,293.02)") == "negative three thousand two hundred ninety three dollars and two cents")
        #expect(VoiceSpeechFormatter.formatCurrency("$1,420.50") == "one thousand four hundred twenty dollars and fifty cents")
        #expect(VoiceSpeechFormatter.formatCurrency("$1.01") == "one dollar and one cent")
        #expect(VoiceSpeechFormatter.formatCurrency("$1.5") == "one dollar and fifty cents")
    }

    @Test("Follow-up selections require real candidates")
    func selection() {
        var context = VoiceSessionContext.empty
        context.candidateFindingIDs = ["a", "b"]
        #expect(VoiceIntentRouter.match(text: "open the second one", context: context) == .chooseFinding(1))
        #expect(VoiceIntentRouter.match(text: "first", context: context) == .chooseFinding(0))
        #expect(VoiceIntentRouter.match(text: "third", context: context) == .unrecognized("third"))
        #expect(VoiceIntentRouter.match(text: "second", context: .empty) == .unrecognized("second"))
    }

    @Test("Back and forward, with filler")
    func backForward() {
        for p in ["go back", "Go back.", "hey moneypenny go back", "please go back", "back", "previous page", "can you go back"] { #expect(parse(p) == .goBack, "\(p)") }
        #expect(parse("go forward") == .goForward)
    }

    @Test("Finding groups by many phrasings")
    func groups() {
        for p in ["pull up the duplicates", "show me duplicates", "open the duplicate transactions", "list all the dupes", "find duplicates", "duplicates"] { #expect(parse(p) == .findingsGroup(.duplicates), "\(p)") }
        for p in ["show me the uncategorized transactions", "pull up uncategorized", "open miscategorized"] { #expect(parse(p) == .findingsGroup(.miscategorizedOrUncategorized), "\(p)") }
        for p in ["pull up the negative balances", "show overdrawn accounts"] { #expect(parse(p) == .findingsGroup(.negativeBalance), "\(p)") }
        for p in ["show me the personal expenses", "pull up owner draws"] { #expect(parse(p) == .findingsGroup(.personalExpense), "\(p)") }
        for p in ["show me all open findings", "what's open", "pull up everything open"] { #expect(parse(p) == .findingsGroup(.allOpen), "\(p)") }
        #expect(parse("open the suspense and clearing") == .findingsGroup(.balanceSheetIntegrity))
    }

    @Test("A finding by amount or by name, and plain searches")
    func openFinding() {
        #expect(parse("open the $1,420 one") == .openFindingMatching(amount: usd(142_000), text: "$1,420 one"))
        #expect(parse("pull up the fourteen twenty finding") == .openFindingMatching(amount: usd(142_000), text: "fourteen twenty finding"))
        #expect(parse("show me the cool cars payment") == .openFindingMatching(amount: nil, text: "cool cars payment"))
        #expect(parse("open the duplicate invoice") == .openFindingMatching(amount: nil, text: "duplicate invoice"))
        #expect(parse("find the 1420.00 transaction") == .searchAmount(usd(142_000)))
        #expect(parse("search for $500") == .searchAmount(usd(50_000)))
        #expect(parse("any transaction for three thousand two hundred ninety three dollars and two cents") == .searchAmount(usd(329_302)))
        #expect(parse("find hicks hardware") == .searchVendor("hicks hardware"))
    }

    @Test("Balances, vendors, KPIs, freshness, charts")
    func dataQuestions() {
        for p in ["what's the balance of the sweeper checking account", "balance of sweeper checking", "what is the balance in checking", "how much is in the savings account", "tell me the balance on mastercard"] {
            if case .accountBalance = parse(p) {} else { Issue.record("\(p) → \(String(describing: parse(p)))") }
        }
        #expect(parse("what's the balance of the sweeper checking account") == .accountBalance("sweeper checking"))
        #expect(parse("what do we owe norton lumber") == .vendorOwed("norton lumber"))
        #expect(parse("how much have we paid tania's nursery") == .searchVendor("tania's nursery"))
        #expect(parse("what's our revenue this month") == .kpi(.revenue, .current))
        #expect(parse("what was net income last month") == .kpi(.netIncome, .priorMonth))
        #expect(parse("how much cash do we have") == nil || parse("what's our cash balance") == .kpi(.cashBalance, .current))
        #expect(parse("what's the cash balance") == .kpi(.cashBalance, .current))
        #expect(parse("when did we last sync") == .freshness)
        #expect(parse("is this current") == .freshness)
        #expect(parse("chart the expenses") == .chart(.expenseDrivers))
        #expect(parse("show me a chart of income vs expenses") == .chart(.incomeVsExpenses))
    }

    @Test("'What do we owe <vendor>' — including the 'own' mishearing — and hands-free retry")
    func owedAndRetry() {
        for p in ["what do we owe norton lumber", "what do we own norton lumber", "How much do we owe Norton Lumber?", "what do we owe to norton lumber", "how much do we oh norton lumber"] {
            #expect(parse(p) == .vendorOwed("norton lumber"), "\(p)")
        }
        for p in ["try again", "Try again.", "hey moneypenny try again", "that's wrong", "never mind", "scratch that"] { #expect(parse(p) == .retry, "\(p)") }
        #expect(parse("what do we own") == .totalOwed)   // "own" is how recognizers hear "owe"
    }

    @Test("Open-ended questions are left to the model")
    func leftToModel() {
        #expect(parse("why is this flagged") == nil)
        #expect(parse("why did expenses jump this month compared to last") == nil)
        #expect(parse("summarize the month for the client") == nil)
        #expect(parse("what does opening balance equity mean") == nil)
    }
}

@Suite("CommandGrammar — dashboard measures and vendor spend (owner test 2026-10-02)")
struct DashboardMeasureGrammarTests {
    @Test("Every dashboard card can be asked for")
    func dashboardMeasures() {
        #expect(CommandGrammar.parse("working capital") == .kpi(.workingCapital, .current))
        #expect(CommandGrammar.parse("what's our working capital") == .kpi(.workingCapital, .current))
        #expect(CommandGrammar.parse("what is the current ratio") == .kpi(.currentRatio, .current))
        #expect(CommandGrammar.parse("quick ratio") == .kpi(.quickRatio, .current))
        #expect(CommandGrammar.parse("what's our gross margin") == .kpi(.grossMargin, .current))
        #expect(CommandGrammar.parse("net margin last month") == .kpi(.netMargin, .priorMonth))
        #expect(CommandGrammar.parse("what's our net income") == .kpi(.netIncome, .current))
    }

    @Test("Vendor spend, including the recognizer's 'spin'")
    func vendorSpend() {
        #expect(CommandGrammar.parse("vendor by spend") == .chart(.vendorSpend))
        #expect(CommandGrammar.parse("vendor by spin") == .chart(.vendorSpend))
        #expect(CommandGrammar.parse("vendors by spin") == .chart(.vendorSpend))
        #expect(CommandGrammar.parse("top vendors") == .chart(.vendorSpend))
        #expect(CommandGrammar.parse("who do we pay the most") == .chart(.vendorSpend))
    }
}
