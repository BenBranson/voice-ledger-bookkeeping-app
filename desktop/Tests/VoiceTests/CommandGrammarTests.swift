import Testing
@testable import Voice
import Core

@Suite("CommandGrammar — spoken commands resolved in code")
struct CommandGrammarTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func parse(_ s: String) -> VoiceIntent? { CommandGrammar.parse(s) }

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
        #expect(parse("what do we owe norton lumber") == .searchVendor("norton lumber"))
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

    @Test("Open-ended questions are left to the model")
    func leftToModel() {
        #expect(parse("why is this flagged") == nil)
        #expect(parse("why did expenses jump this month compared to last") == nil)
        #expect(parse("summarize the month for the client") == nil)
        #expect(parse("what does opening balance equity mean") == nil)
    }
}
