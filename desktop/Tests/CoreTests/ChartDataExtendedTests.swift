import Testing
@testable import Core
import Foundation

@Suite("ChartData — flow, sparklines, calendar, treemap, margin")
struct ChartDataExtendedTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func leaf(_ l: String, _ c: Int64, id: String, depth: Int = 2) -> ReportLine { ReportLine(label: l, amount: usd(c), depth: depth, isSummary: false, accountID: id) }
    func total(_ l: String, _ c: Int64) -> ReportLine { ReportLine(label: l, amount: usd(c), depth: 1, isSummary: true) }

    func pnl(net: Int64) -> [ReportLine] {
        // income 1,000.00; COGS 200; expenses 700 + credit -50; other income 10; other expense 20
        let expenses: Int64 = 70_000 - 5_000
        let n = 100_000 - 20_000 - expenses + 1_000 - 2_000
        precondition(n == net || net == -1)
        return [
            leaf("Sales", 100_000, id: "i1"), total("Total Income", 100_000),
            total("Total Cost of Goods Sold", 20_000), total("Gross Profit", 80_000),
            leaf("Rent", 50_000, id: "e1"), leaf("Fuel", 20_000, id: "e2"), leaf("Refund", -5_000, id: "e3"), total("Total Expenses", expenses),
            total("Total Other Income", 1_000), total("Total Other Expenses", 2_000), total("Net Income", n)
        ]
    }

    @Test("Money flow: inflows equal outflows, profit is its own outflow, credits are an inflow")
    func flowProfit() throws {
        let f = try #require(ChartData.moneyFlow(from: pnl(net: 14_000), hubLabel: "July"))
        let inflow = f.links.filter { $0.target == "hub" }.reduce(0.0) { $0 + $1.value }
        let outflow = f.links.filter { $0.source == "hub" }.reduce(0.0) { $0 + $1.value }
        #expect(abs(inflow - outflow) < 0.005)
        #expect(f.nodes.contains { $0.id == "profit" && $0.valueText == "$140.00" })
        #expect(f.nodes.contains { $0.id == "expense-credits" && $0.valueText == "$50.00" })
        #expect(f.totalText == "$1,060.00")
    }

    @Test("Money flow: a loss appears as a labeled inflow, never as a negative band")
    func flowLoss() throws {
        let lines = [leaf("Sales", 10_000, id: "i1"), total("Total Income", 10_000), leaf("Rent", 50_000, id: "e1"), total("Total Expenses", 50_000), total("Net Income", -40_000)]
        let f = try #require(ChartData.moneyFlow(from: lines, hubLabel: "July"))
        #expect(f.nodes.contains { $0.id == "shortfall" && $0.kind == "loss" && $0.valueText == "$400.00" })
        #expect(!f.nodes.contains { $0.id == "profit" })
        #expect(f.links.allSatisfy { $0.value > 0 })
    }

    @Test("Money flow refuses to draw when sections don't tie to QuickBooks' totals")
    func flowMismatch() {
        let lines = [leaf("Sales", 10_000, id: "i1"), total("Total Income", 12_000), total("Net Income", 12_000)]
        #expect(ChartData.moneyFlow(from: lines, hubLabel: "July") == nil)
    }

    @Test("Treemap nests sub-accounts under their parent and keeps credits out of the area")
    func treemap() throws {
        let lines = [
            total("Total Income", 1),
            ReportLine(label: "Expenses", amount: nil, depth: 0, isSummary: false),
            ReportLine(label: "Vehicle", amount: nil, depth: 1, isSummary: false, accountID: "v"),
            leaf("Fuel", 30_000, id: "v1"), leaf("Repairs", 10_000, id: "v2"),
            ReportLine(label: "Total Vehicle", amount: usd(40_000), depth: 1, isSummary: true),
            leaf("Rent", 50_000, id: "r", depth: 1), leaf("Refund", -2_000, id: "x", depth: 1),
            total("Total Expenses", 88_000)
        ]
        let t = try #require(ChartData.expenseTree(from: lines))
        #expect(t.nodes.map(\.label) == ["Rent", "Vehicle"])
        #expect(t.nodes[1].children.map(\.label) == ["Fuel", "Repairs"])
        #expect(t.nodes[1].valueText == "$400.00")
        #expect(t.credits.map(\.label) == ["Refund"])
    }

    @Test("Margin is blank, not zero, when there is no revenue")
    func margin() {
        let t = ChartData.trend(from: [
            MonthlyReport(period: AccountingPeriod(year: 2026, month: 6), lines: [leaf("Sales", 100_000, id: "s"), total("Total Income", 100_000), total("Net Income", 25_000)]),
            MonthlyReport(period: AccountingPeriod(year: 2026, month: 7), lines: [leaf("Fuel", 1_000, id: "f"), total("Total Expenses", 1_000), total("Net Income", -1_000)])
        ])
        #expect(t.points.first?.marginPercent == 25)
        #expect(t.points.last?.marginPercent == nil)
    }

    @Test("Calendar counts postings and deposits per day for one account only")
    func calendar() throws {
        func txn(_ id: String, _ acct: String, _ day: Int) -> LedgerTransaction {
            LedgerTransaction(id: id, entityKind: .purchase, vendorName: "V", txnDate: AccountingDate(year: 2026, month: 7, day: day), totalAmount: usd(1_000), paymentAccountID: acct, docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
        }
        let h = HistorySnapshot(realmID: RealmID(rawValue: "r"), fetchedAt: Date(), from: AccountingDate(year: 2026, month: 1, day: 1), through: AccountingDate(year: 2026, month: 9, day: 29),
                                transactions: [txn("1", "chk", 3), txn("2", "chk", 3), txn("3", "sav", 3)],
                                deposits: [LedgerDeposit(id: "d", linkedPaymentIDs: [], txnDate: AccountingDate(year: 2026, month: 7, day: 9), depositToAccountID: "chk", totalAmount: usd(5_000))], vendorCredits: [],
                                accounts: [LedgerAccount(id: "chk", name: "Checking", accountType: .bank)], monthlyProfitAndLoss: [], latestBalanceSheet: [], latestCashFlow: [], coverage: .complete)
        let c = try #require(ChartData.postingCalendar(history: h, accountID: "chk"))
        #expect(c.days.map(\.date) == ["2026-07-03", "2026-07-09"])
        #expect(c.days.first?.count == 2)
        #expect(c.maxCount == 2)
        #expect(c.lastPostingText == "Last posting 2026-07-09")
    }

    @Test("Sparklines: unreadable cash months stay blank; change is vs the prior month")
    func sparklines() throws {
        let months = [6, 7].map { MonthlyReport(period: AccountingPeriod(year: 2026, month: $0), lines: [leaf("Sales", Int64($0) * 10_000, id: "s"), total("Total Income", Int64($0) * 10_000), total("Net Income", Int64($0) * 1_000)]) }
        let cash = [MonthlyAmount(period: AccountingPeriod(year: 2026, month: 6), amount: nil), MonthlyAmount(period: AccountingPeriod(year: 2026, month: 7), amount: usd(300_000))]
        let s = try #require(ChartData.sparklines(months: months, monthEndCash: cash))
        #expect(s.rows.first { $0.id == "revenue" }?.changeText == "+$100.00 vs prior month")
        let cashRow = try #require(s.rows.first { $0.id == "cash" })
        #expect(cashRow.values.first! == nil)
        #expect(cashRow.changeText == "No prior month")
    }

    @Test("Sparklines stop at the last completed month, so a partial month isn't the latest value")
    func sparklinesCutoff() throws {
        let months = [6, 7, 8].map { MonthlyReport(period: AccountingPeriod(year: 2026, month: $0), lines: [leaf("Sales", Int64($0) * 10_000, id: "s"), total("Total Income", Int64($0) * 10_000), total("Net Income", Int64($0) * 1_000)]) }
        let s = try #require(ChartData.sparklines(months: months, monthEndCash: [], through: AccountingPeriod(year: 2026, month: 7)))
        let revenue = try #require(s.rows.first { $0.id == "revenue" })
        #expect(revenue.values.count == 2)
        #expect(revenue.latestText == "$700.00")
    }
}
