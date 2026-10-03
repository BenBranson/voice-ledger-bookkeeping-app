import Testing
import Foundation
@testable import Core

/// Self-checking math must (a) tie on correct books and (b) catch each kind of
/// break with exactly the right check and the exact difference. A check that
/// can't fail proves nothing.
@Suite("Tie-out checks: tie on correct books, catch every break")
struct TieOutTests {
    func usd(_ dollars: Double) -> Money { Money(minorUnits: Int64((dollars * 100).rounded()), currency: .usd) }
    func s(_ label: String, _ v: Double, depth: Int = 0) -> ReportLine { ReportLine(label: label, amount: usd(v), depth: depth, isSummary: true) }
    func d(_ label: String, _ v: Double, id: String? = nil) -> ReportLine { ReportLine(label: label, amount: usd(v), depth: 1, isSummary: false, accountID: id) }
    func aging(_ rows: [(String, Double)], total: Double) -> [AgingLine] {
        rows.map { AgingLine(label: $0.0, current: usd($0.1), days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: usd($0.1), depth: 0, isSummary: false) }
            + [AgingLine(label: "TOTAL", current: usd(total), days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: nil, total: usd(total), depth: 0, isSummary: true)]
    }

    /// Books that tie: assets 20,000 = liabilities 5,000 + equity 15,000; NI 1,500.
    func good() -> TieOut.Input {
        let bs = [d("Checking", 6_000), s("Total Bank Accounts", 6_000, depth: 1), s("Total Accounts Receivable", 4_000, depth: 1),
                  d("Undeposited Funds", 500, id: "4"), s("TOTAL ASSETS", 20_000),
                  s("Total Accounts Payable", 3_000, depth: 1), s("Total Liabilities", 5_000, depth: 1),
                  d("Net Income", 9_500), s("Total Equity", 15_000, depth: 1), s("TOTAL LIABILITIES AND EQUITY", 20_000)]
        let prior = [d("Net Income", 8_000)]
        let pl = [s("Total Income", 10_000), s("Total Cost of Goods Sold", 1_000), s("Gross Profit", 9_000), s("Total Expenses", 7_000),
                  s("Net Operating Income", 2_000), s("Total Other Expenses", 500), s("Net Other Income", -500), s("Net Income", 1_500)]
        let cf = [d("Cash at end of period", 6_500)]
        let tb = [TrialBalanceLine(label: "TOTAL", debit: usd(30_000), credit: usd(30_000), isSummary: true)]
        let accounts = [LedgerAccount(id: "4", name: "Undeposited Funds", accountType: .otherCurrentAsset, accountSubType: "UndepositedFunds")]
        return TieOut.Input(period: AccountingPeriod(year: 2026, month: 9), balanceSheet: bs, priorBalanceSheet: prior, profitAndLoss: pl, cashFlow: cf,
                            trialBalance: tb, agedReceivables: aging([("Amy", 1_500), ("Bob", 2_500)], total: 4_000),
                            agedPayables: aging([("Norton", 3_000)], total: 3_000), accounts: accounts, agingIsPeriodEnd: true)
    }

    func failingIDs(_ input: TieOut.Input) -> [String: Money] {
        Dictionary(TieOut.run(input).compactMap { c in if case .doesNotTie(let diff) = c.status { return (c.id, diff) }; return nil }, uniquingKeysWith: { a, _ in a })
    }

    @Test("Correct books: all nine checks tie")
    func allTie() {
        let checks = TieOut.run(good())
        #expect(checks.count == 9)
        for c in checks { #expect(c.status == .ties, "\(c.id): \(c.status)") }
        #expect(TieOut.failing(checks).isEmpty)
    }

    @Test("Each break is caught by exactly the right check, with the exact difference")
    func everyBreakCaught() {
        func replace(_ lines: [ReportLine], _ label: String, _ v: Double) -> [ReportLine] {
            lines.map { $0.label == label ? ReportLine(label: label, amount: usd(v), depth: $0.depth, isSummary: $0.isSummary, accountID: $0.accountID) : $0 }
        }
        var i = good(); i.balanceSheet = replace(i.balanceSheet, "TOTAL ASSETS", 20_010)
        #expect(failingIDs(i) == ["bs-balances": usd(10)])

        i = good(); i.trialBalance = [TrialBalanceLine(label: "TOTAL", debit: usd(30_000), credit: usd(29_999.99), isSummary: true)]
        #expect(failingIDs(i) == ["tb-balances": usd(0.01)])

        // A customer row lost (the parent-customer parse bug): rows no longer add up AND the TOTAL is right.
        i = good(); i.agedReceivables = aging([("Amy", 1_500)], total: 4_000)
        #expect(failingIDs(i) == ["ar-rows": usd(-2_500)])

        i = good(); i.agedPayables = aging([("Norton", 3_100)], total: 3_100)
        #expect(failingIDs(i) == ["ap-tie": usd(100)])

        i = good(); i.agedReceivables = aging([("Amy", 1_500), ("Bob", 2_600)], total: 4_100)
        #expect(failingIDs(i) == ["ar-tie": usd(100)])

        i = good(); i.profitAndLoss = replace(i.profitAndLoss, "Net Income", 1_400)
        let pl = failingIDs(i)
        #expect(pl["pl-math"] == usd(100))
        #expect(pl["pl-to-bs"] == usd(100))

        i = good(); i.profitAndLoss = replace(i.profitAndLoss, "Gross Profit", 9_050)
        #expect(failingIDs(i) == ["pl-math": usd(-50)])

        i = good(); i.cashFlow = [d("Cash at end of period", 6_000)]
        #expect(failingIDs(i) == ["cash-tie": usd(500)])
    }

    @Test("New fiscal year: the balance sheet's net income restarts and still ties")
    func fiscalYearReset() {
        var i = good()
        i.priorBalanceSheet = [d("Net Income", 40_000)]
        i.balanceSheet = i.balanceSheet.map { $0.label == "Net Income" ? d("Net Income", 1_500) : $0 }
        #expect(TieOut.run(i).first { $0.id == "pl-to-bs" }?.status == .ties)
    }

    @Test("Month in progress: aging ties to today's account balance (A/P sign flipped)")
    func inProgress() {
        var i = good()
        i.agingIsPeriodEnd = false
        i.accounts += [LedgerAccount(id: "84", name: "A/R", accountType: .accountsReceivable, currentBalance: usd(4_000)),
                       LedgerAccount(id: "33", name: "A/P", accountType: .accountsPayable, currentBalance: usd(-3_000))]
        #expect(failingIDs(i).isEmpty)
    }

    @Test("Missing data is 'not checked', never 'ties'")
    func missingIsNotChecked() {
        let checks = TieOut.run(TieOut.Input(period: AccountingPeriod(year: 2026, month: 9), balanceSheet: [], profitAndLoss: [], agingIsPeriodEnd: true))
        for c in checks { if case .ties = c.status { Issue.record("\(c.id) claimed to tie with no data") } }
    }
}
