import Testing
@testable import Core
import Foundation

@Suite("MonthlyReportBuilder")
struct MonthlyReportBuilderTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func pnl(_ income: Int64, _ expenses: Int64) -> [ReportLine] {
        [ReportLine(label: "Sales", amount: usd(income), depth: 2, isSummary: false, accountID: "1"),
         ReportLine(label: "Total Income", amount: usd(income), depth: 1, isSummary: true),
         ReportLine(label: "Rent", amount: usd(expenses), depth: 2, isSummary: false, accountID: "2"),
         ReportLine(label: "Total Expenses", amount: usd(expenses), depth: 1, isSummary: true),
         ReportLine(label: "Net Income", amount: usd(income - expenses), depth: 0, isSummary: true)]
    }
    func inputs(months: [MonthlyReport], today: AccountingDate = AccountingDate(year: 2026, month: 9, day: 29)) -> MonthlyReportInputs {
        MonthlyReportInputs(clientName: "Acme", period: AccountingPeriod(year: 2026, month: 7), today: today, generatedAt: Date(), accountingBasis: "Accrual", environment: "sandbox",
                            monthlyProfitAndLoss: months, balanceSheet: [], cashFlow: [], agedReceivables: [], accountTypes: [:], findings: [], coverage: .complete)
    }

    @Test("Percentages only against a positive baseline; zero/negative baselines are 'n/m'; missing is '—'")
    func percent() {
        #expect(MonthlyReportBuilder.percentText(current: usd(150), prior: usd(100)) == "+50.0%")
        #expect(MonthlyReportBuilder.percentText(current: usd(150), prior: usd(0)) == "n/m")
        #expect(MonthlyReportBuilder.percentText(current: usd(150), prior: usd(-100)) == "n/m")
        #expect(MonthlyReportBuilder.percentText(current: usd(150), prior: nil) == "—")
        #expect(MonthlyReportBuilder.changeText(current: usd(15_000), prior: usd(10_000)) == "+$50.00")
    }

    @Test("Month-over-month rows use the prior month; a net-loss baseline never gets a percentage")
    func monthOverMonth() {
        let r = MonthlyReportBuilder.build(inputs(months: [
            MonthlyReport(period: AccountingPeriod(year: 2026, month: 6), lines: pnl(100_000, 150_000)),
            MonthlyReport(period: AccountingPeriod(year: 2026, month: 7), lines: pnl(200_000, 50_000))
        ]))
        #expect(r.kpis.first { $0.id == "revenue" }?.valueText == "$2,000.00")
        #expect(r.monthOverMonth.first { $0.label == "Revenue" }?.percentText == "+100.0%")
        #expect(r.monthOverMonth.first { $0.label == "Net income" }?.percentText == "n/m")
        #expect(r.yearOverYear == nil)
        #expect(r.notes.contains { $0.contains("Year-over-year comparison omitted") })
        #expect(r.notes.contains { $0.contains("SANDBOX") })
    }

    @Test("Missing prior month is stated, not shown as zero")
    func missingPrior() {
        let r = MonthlyReportBuilder.build(inputs(months: [MonthlyReport(period: AccountingPeriod(year: 2026, month: 7), lines: pnl(200_000, 50_000))]))
        #expect(r.monthOverMonth.isEmpty)
        #expect(r.kpis.first { $0.id == "revenue" }?.comparisonText == "No prior-month data")
    }

    @Test("A month still in progress is labeled partial with the real balance date")
    func partialMonth() {
        let r = MonthlyReportBuilder.build(inputs(months: [MonthlyReport(period: AccountingPeriod(year: 2026, month: 7), lines: pnl(1, 1))], today: AccountingDate(year: 2026, month: 7, day: 12)))
        #expect(r.meta.isPartialMonth)
        #expect(r.meta.balanceDateLabel == "Balances as of July 12, 2026")
    }
}
