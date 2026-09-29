import Testing
@testable import Core

@Suite("Ask AI about a report row")
struct ReportRowAskAITests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }

    @Test("Context carries the row, its section, last period, and the report totals — the figures come from the report, not the AI")
    func context() {
        let lines = [ReportLine(label: "Expenses", amount: nil, depth: 0, isSummary: false),
                     ReportLine(label: "Fuel", amount: usd(61_250), depth: 1, isSummary: false, accountID: "56"),
                     ReportLine(label: "Total Expenses", amount: usd(90_000), depth: 0, isSummary: true)]
        let prior = [ReportLine(label: "Fuel", amount: usd(48_000), depth: 1, isSummary: false, accountID: "56")]
        let ask = AskAIContext.reportRow(lines[1], in: lines, priorLines: prior, reportTitle: "Profit & Loss", periodLabel: "July 2026")
        #expect(ask.context.contains("Selected row: Fuel"))
        #expect(ask.context.contains("Section: Expenses"))
        #expect(ask.context.contains("Same row last period: $480.00"))
        #expect(ask.context.contains("Total Expenses: $900.00"))
        #expect(ask.question.contains("\"Fuel\" line ($612.50)"))
        #expect(ask.question.contains("don't calculate new ones"))
    }
}
