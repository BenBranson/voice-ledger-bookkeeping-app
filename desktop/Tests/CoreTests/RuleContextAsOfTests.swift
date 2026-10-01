import Testing
@testable import Core

@Suite("RuleContext keeps its as-of date through gating")
struct RuleContextAsOfTests {
    @Test("gatingTransactions preserves asOfDate (it used to reset to today)")
    func gatingPreservesAsOf() {
        let pinned = AccountingDate(year: 2026, month: 9, day: 30)
        let context = RuleContext(period: AccountingPeriod(year: 2026, month: 7), materiality: .defaultPolicy,
                                  companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), asOfDate: pinned)
        #expect(context.gatingTransactions(["a"]).asOfDate == pinned)
    }
}
