import Testing
@testable import Core

@Suite("FinancialKPIs")
struct FinancialKPIsTests {
    private func money(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currency: .usd)
    }

    private var balanceSheetLines: [ReportLine] {
        [
            ReportLine(label: "Checking", amount: money(500_000), depth: 2, isSummary: false),
            ReportLine(label: "Cash", amount: money(500_000), depth: 1, isSummary: true),
            ReportLine(label: "Accounts Receivable", amount: money(200_000), depth: 1, isSummary: true),
            ReportLine(label: "Total Current Assets", amount: money(700_000), depth: 0, isSummary: true),
            ReportLine(label: "Total Assets", amount: money(700_000), depth: 0, isSummary: true),
            ReportLine(label: "Total Current Liabilities", amount: money(350_000), depth: 0, isSummary: true)
        ]
    }

    private var profitAndLossLines: [ReportLine] {
        [
            ReportLine(label: "Total Income", amount: money(1_000_000), depth: 0, isSummary: true),
            ReportLine(label: "Gross Profit", amount: money(600_000), depth: 0, isSummary: true),
            ReportLine(label: "Rent", amount: money(100_000), depth: 1, isSummary: false),
            ReportLine(label: "Net Income", amount: money(200_000), depth: 0, isSummary: true)
        ]
    }

    @Test("Gross margin is Gross Profit / Total Income as a percentage")
    func grossMargin() {
        #expect(FinancialKPIs.grossMarginPercent(from: profitAndLossLines) == 60.0)
    }

    @Test("Gross margin is nil when Gross Profit is missing — never a guess")
    func grossMarginNilWhenMissing() {
        let lines = [ReportLine(label: "Total Income", amount: money(1_000_000), depth: 0, isSummary: true)]
        #expect(FinancialKPIs.grossMarginPercent(from: lines) == nil)
    }

    @Test("Net margin is Net Income / Total Income as a percentage")
    func netMargin() {
        #expect(FinancialKPIs.netMarginPercent(from: profitAndLossLines) == 20.0)
    }

    @Test("Working capital is Total Current Assets minus Total Current Liabilities")
    func workingCapital() {
        #expect(FinancialKPIs.workingCapital(from: balanceSheetLines) == money(350_000))
    }

    @Test("Working capital is nil when a required line is missing")
    func workingCapitalNilWhenMissing() {
        #expect(FinancialKPIs.workingCapital(from: []) == nil)
    }

    @Test("Current ratio is Total Current Assets / Total Current Liabilities")
    func currentRatio() {
        #expect(FinancialKPIs.currentRatio(from: balanceSheetLines) == 2.0)
    }

    @Test("Current ratio is nil when current liabilities are zero — an undefined ratio, not infinite")
    func currentRatioNilWhenLiabilitiesZero() {
        let lines = [
            ReportLine(label: "Total Current Assets", amount: money(700_000), depth: 0, isSummary: true),
            ReportLine(label: "Total Current Liabilities", amount: money(0), depth: 0, isSummary: true)
        ]
        #expect(FinancialKPIs.currentRatio(from: lines) == nil)
    }

    @Test("Quick ratio is (Cash + Accounts Receivable) / Total Current Liabilities")
    func quickRatio() {
        // (500_000 + 200_000) / 350_000 = 2.0
        #expect(FinancialKPIs.quickRatio(from: balanceSheetLines) == 2.0)
    }

    @Test("Quick ratio is nil when Accounts Receivable isn't its own summary line")
    func quickRatioNilWhenMissing() {
        let lines = [
            ReportLine(label: "Cash", amount: money(500_000), depth: 1, isSummary: true),
            ReportLine(label: "Total Current Liabilities", amount: money(350_000), depth: 0, isSummary: true)
        ]
        #expect(FinancialKPIs.quickRatio(from: lines) == nil)
    }

    @Test("Quick ratio falls back to Total Bank Accounts / Total Accounts Receivable — real labels confirmed live 2026-08-29 against this app's sandbox company, which has no bare Cash/Accounts Receivable summary line")
    func quickRatioFallsBackToRealSandboxLabels() {
        let lines = [
            ReportLine(label: "Total Bank Accounts", amount: money(500_000), depth: 1, isSummary: true),
            ReportLine(label: "Total Accounts Receivable", amount: money(200_000), depth: 1, isSummary: true),
            ReportLine(label: "Total Current Liabilities", amount: money(350_000), depth: 0, isSummary: true)
        ]
        #expect(FinancialKPIs.quickRatio(from: lines) == 2.0)
    }
}

@Suite("BalanceSheetBreakdown")
struct BalanceSheetBreakdownTests {
    private func money(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currency: .usd)
    }

    @Test("Splits assets from liabilities & equity at the Total Assets line")
    func splitsAtTotalAssets() {
        let lines = [
            ReportLine(label: "Checking", amount: money(500_000), depth: 1, isSummary: false),
            ReportLine(label: "Total Assets", amount: money(500_000), depth: 0, isSummary: true),
            ReportLine(label: "Accounts Payable", amount: money(200_000), depth: 1, isSummary: false),
            ReportLine(label: "Total Liabilities and Equity", amount: money(500_000), depth: 0, isSummary: true)
        ]
        let assets = BalanceSheetBreakdown.assetSlices(from: lines)
        let liabilities = BalanceSheetBreakdown.liabilitiesAndEquitySlices(from: lines)
        #expect(assets.map(\.label) == ["Checking"])
        #expect(liabilities.map(\.label) == ["Accounts Payable"])
    }

    @Test("Excludes summary/subtotal lines so a parent total isn't double-counted alongside its children")
    func excludesSummaryLines() {
        let lines = [
            ReportLine(label: "Checking", amount: money(300_000), depth: 2, isSummary: false),
            ReportLine(label: "Savings", amount: money(200_000), depth: 2, isSummary: false),
            ReportLine(label: "Total Bank Accounts", amount: money(500_000), depth: 1, isSummary: true),
            ReportLine(label: "Total Assets", amount: money(500_000), depth: 0, isSummary: true)
        ]
        let assets = BalanceSheetBreakdown.assetSlices(from: lines)
        #expect(assets.map(\.label) == ["Checking", "Savings"])
    }

    @Test("Empty when Total Assets isn't found — never a guess")
    func emptyWhenNoSplitPoint() {
        #expect(BalanceSheetBreakdown.assetSlices(from: []).isEmpty)
        #expect(BalanceSheetBreakdown.liabilitiesAndEquitySlices(from: []).isEmpty)
    }

    @Test("Splits at 'TOTAL ASSETS' (all caps) — the real label confirmed live 2026-08-29 against this app's sandbox company")
    func splitsAtAllCapsTotalAssets() {
        let lines = [
            ReportLine(label: "Checking", amount: money(500_000), depth: 1, isSummary: false),
            ReportLine(label: "TOTAL ASSETS", amount: money(500_000), depth: 0, isSummary: true),
            ReportLine(label: "Accounts Payable", amount: money(200_000), depth: 1, isSummary: false),
            ReportLine(label: "TOTAL LIABILITIES AND EQUITY", amount: money(500_000), depth: 0, isSummary: true)
        ]
        #expect(BalanceSheetBreakdown.assetSlices(from: lines).map(\.label) == ["Checking"])
        #expect(BalanceSheetBreakdown.liabilitiesAndEquitySlices(from: lines).map(\.label) == ["Accounts Payable"])
    }
}

@Suite("ProfitAndLossWaterfall")
struct ProfitAndLossWaterfallTests {
    private func money(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currency: .usd)
    }

    @Test("Builds Revenue -> COGS -> Expenses -> Net Income when Gross Profit is present")
    func fullWaterfallWithCOGS() {
        let lines = [
            ReportLine(label: "Total Income", amount: money(1_000_000), depth: 0, isSummary: true),
            ReportLine(label: "Gross Profit", amount: money(600_000), depth: 0, isSummary: true),
            ReportLine(label: "Net Income", amount: money(200_000), depth: 0, isSummary: true)
        ]
        let segments = ProfitAndLossWaterfall.segments(from: lines)
        #expect(segments?.map(\.label) == ["Revenue", "COGS", "Expenses", "Net Income"])
        #expect(segments?.last?.end == 2000.0)
    }

    @Test("Skips the COGS segment when Gross Profit equals Total Income — real, reported bug (2026-08-29): a company with no real COGS produced a zero-width bar with a floating '$0' label and nothing under it")
    func skipsCOGSWhenGrossProfitEqualsTotalIncome() {
        let lines = [
            ReportLine(label: "Total Income", amount: money(1_000_000), depth: 0, isSummary: true),
            ReportLine(label: "Gross Profit", amount: money(1_000_000), depth: 0, isSummary: true),
            ReportLine(label: "Net Income", amount: money(200_000), depth: 0, isSummary: true)
        ]
        let segments = ProfitAndLossWaterfall.segments(from: lines)
        #expect(segments?.map(\.label) == ["Revenue", "Expenses", "Net Income"])
    }

    @Test("Skips the COGS segment when this company's P&L has no Gross Profit line")
    func skipsCOGSWhenNoGrossProfit() {
        let lines = [
            ReportLine(label: "Total Income", amount: money(1_000_000), depth: 0, isSummary: true),
            ReportLine(label: "Net Income", amount: money(200_000), depth: 0, isSummary: true)
        ]
        let segments = ProfitAndLossWaterfall.segments(from: lines)
        #expect(segments?.map(\.label) == ["Revenue", "Expenses", "Net Income"])
    }

    @Test("Nil when Total Income is missing — never a guess")
    func nilWhenMissingRequiredLine() {
        #expect(ProfitAndLossWaterfall.segments(from: []) == nil)
    }
}

@Suite("TopExpenseDrivers")
struct TopExpenseDriversTests {
    private func money(_ minorUnits: Int64) -> Money {
        Money(minorUnits: minorUnits, currency: .usd)
    }

    @Test("Ranks expense lines by amount, largest first, capped at the requested count")
    func ranksByAmount() {
        let lines = [
            ReportLine(label: "Total Income", amount: money(1_000_000), depth: 0, isSummary: true),
            ReportLine(label: "Rent", amount: money(100_000), depth: 1, isSummary: false),
            ReportLine(label: "Software", amount: money(300_000), depth: 1, isSummary: false),
            ReportLine(label: "Travel", amount: money(50_000), depth: 1, isSummary: false),
            ReportLine(label: "Total Expenses", amount: money(450_000), depth: 0, isSummary: true)
        ]
        let top2 = TopExpenseDrivers.top(2, from: lines)
        #expect(top2.map(\.label) == ["Software", "Rent"])
    }

    @Test("Empty when no income/gross-profit split point is found")
    func emptyWhenNoSplitPoint() {
        #expect(TopExpenseDrivers.top(5, from: []).isEmpty)
    }
}
