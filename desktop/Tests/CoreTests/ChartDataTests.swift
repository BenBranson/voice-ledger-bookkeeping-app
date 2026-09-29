import Testing
@testable import Core

@Suite("ChartData")
struct ChartDataTests {
    func line(_ label: String, _ cents: Int64?, summary: Bool = false, id: String? = nil) -> ReportLine {
        ReportLine(label: label, amount: cents.map { Money(minorUnits: $0, currency: .usd) }, depth: summary ? 0 : 2, isSummary: summary, accountID: id)
    }

    var balanceSheet: [ReportLine] {
        [
            line("Checking", -306_376, id: "35"),
            line("Savings", 80_000, id: "36"),
            line("Accounts Receivable (A/R)", 548_152, id: "84"),
            line("Accumulated Depreciation", -10_000, id: "90"),
            line("TOTAL ASSETS", 311_776, summary: true),
            line("Accounts Payable (A/P)", 160_267, id: "33"),
            line("Opening Balance Equity", -833_750, id: "34"),
            line("Retained Earnings", 135_949, id: "2"),
            line("Net Income", -397_981),
            line("TOTAL LIABILITIES AND EQUITY", -935_515, summary: true)
        ]
    }

    @Test("Assets: negatives are kept, labeled by kind, and positive + negative = QBO's reported total")
    func assetsBreakdown() throws {
        let b = try #require(ChartData.signedBreakdown(from: balanceSheet, section: .assets, accountTypes: ["35": .bank, "90": .fixedAsset]))
        #expect(b.positiveItems.map(\.label) == ["Accounts Receivable (A/R)", "Savings"])
        #expect(b.negativeItems.map(\.category) == ["overdraft", "contra"])
        #expect(b.positiveSubtotalText == "$6,281.52")
        #expect(b.netText == "$3,117.76")
        #expect(b.reconciles)
        #expect(b.positiveItems.first?.id == "acct:84")
        #expect(abs((b.positiveItems.first?.share ?? 0) - 548_152.0 / 628_152.0) < 1e-9)
    }

    @Test("Liabilities & equity: a net loss and negative equity are not called overdrafts")
    func liabilitiesBreakdown() throws {
        let b = try #require(ChartData.signedBreakdown(from: balanceSheet, section: .liabilitiesAndEquity, accountTypes: ["34": .equity, "2": .equity, "33": .accountsPayable]))
        #expect(Set(b.negativeItems.map(\.category)) == ["negativeEquity", "netLoss"])
        #expect(!b.negativeItems.contains { $0.category == "overdraft" })
        #expect(b.reconciles)
    }

    @Test("Waterfall: revenue from zero, deductions float, other income/expense included, net anchored at zero and reconciled")
    func waterfall() throws {
        let pnl = [
            line("Total Income", 1_000_000, summary: true),
            line("Total Cost of Goods Sold", 300_000, summary: true),
            line("Gross Profit", 700_000, summary: true),
            line("Total Expenses", 500_000, summary: true),
            line("Total Other Income", 20_000, summary: true),
            line("Total Other Expenses", 5_000, summary: true),
            line("Net Income", 215_000, summary: true)
        ]
        let w = try #require(ChartData.waterfall(from: pnl))
        #expect(w.steps.map(\.id) == ["revenue", "cogs", "expenses", "other-income", "other-expenses", "net"])
        #expect(w.steps[0].from == 0 && w.steps[0].to == 10_000)
        #expect(w.steps[1].from == 10_000 && w.steps[1].to == 7_000 && w.steps[1].kind == "decrease")
        #expect(w.steps[3].kind == "increase")
        #expect(w.steps.last?.from == 0 && w.steps.last?.to == 2_150)
        #expect(w.reconciles)
    }

    @Test("Waterfall that doesn't add up says so instead of plugging the gap")
    func waterfallMismatch() throws {
        let w = try #require(ChartData.waterfall(from: [line("Total Income", 100_000, summary: true), line("Total Expenses", 50_000, summary: true), line("Net Income", 40_000, summary: true)]))
        #expect(!w.reconciles)
        #expect(w.note?.contains("$500.00") == true)
    }

    @Test("Expenses: ranked, top N plus an Other bar, reconciled to Total Expenses, credits listed separately")
    func expenses() throws {
        var pnl = [line("Total Income", 900_000, summary: true)]
        for i in 1...10 { pnl.append(line("Cat \(i)", Int64(i) * 1_000, id: "e\(i)")) }
        pnl.append(line("Refund credit", -500, id: "r"))
        pnl.append(line("Total Expenses", 54_500, summary: true))
        pnl.append(line("Total Other Income", 99_999, summary: true))
        let r = try #require(ChartData.expenseCategories(from: pnl, top: 3))
        #expect(r.items.map(\.label) == ["Cat 10", "Cat 9", "Cat 8", "Other (7 categories)"])
        #expect(r.items.last?.valueText == "$280.00")
        #expect(r.reconciles)
        #expect(r.creditItems.map(\.id) == ["acct:r"])
    }

    @Test("Trend drops months before first activity but keeps a real zero month after it")
    func trend() {
        let months = [
            MonthlyReport(period: AccountingPeriod(year: 2026, month: 1), lines: []),
            MonthlyReport(period: AccountingPeriod(year: 2026, month: 2), lines: [line("Sales", 10_000), line("Total Income", 10_000, summary: true), line("Net Income", 10_000, summary: true)]),
            MonthlyReport(period: AccountingPeriod(year: 2026, month: 3), lines: [])
        ]
        let t = ChartData.trend(from: months)
        #expect(t.points.map(\.label) == ["Feb 2026", "Mar 2026"])
        #expect(t.points.last?.revenue == 0)
        #expect(t.note.contains("1 earlier month"))
    }
}
