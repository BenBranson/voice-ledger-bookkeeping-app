import Testing
@testable import Core
import Foundation

// Owner review of the July 2026 sandbox report (2026-10-03, with a Gemini critique):
// parent account names, unsettled working capital, credits outside the aging
// buckets, and no "$0.00" for findings that carry no dollar amount.
@Suite("Monthly report presentation")
struct ReportPresentationTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func line(_ label: String, _ cents: Int64?, _ depth: Int, total: Bool = false, id: String? = nil) -> ReportLine {
        ReportLine(label: label, amount: cents.map(usd), depth: depth, isSummary: total, accountID: id)
    }

    /// QBO's real nesting: section headings carry no account id; "Truck" is a parent ACCOUNT heading.
    var balanceSheet: [ReportLine] {
        [line("ASSETS", nil, 0), line("Current Assets", nil, 1), line("Bank Accounts", nil, 2),
         line("Checking", -100_000, 3, id: "35"), line("Savings", 300_000, 3, id: "36"),
         line("Total Bank Accounts", 200_000, 2, total: true),
         line("Other Current Assets", nil, 2),
         line("VL Spike Suspense", 60_000, 3, id: "90"), line("VL Spike Payroll Clearing", 30_000, 3, id: "91"),
         line("Total Other Current Assets", 90_000, 2, total: true),
         line("Total Current Assets", 290_000, 1, total: true),
         line("Fixed Assets", nil, 1), line("Truck", nil, 2, id: "37"), line("Original Cost", 1_349_500, 3, id: "38"),
         line("Total Truck", 1_349_500, 2, total: true), line("Total Fixed Assets", 1_349_500, 1, total: true),
         line("TOTAL ASSETS", 1_639_500, 0, total: true),
         line("Accounts Payable (A/P)", 250_000, 3, id: "33"), line("Total Current Liabilities", 250_000, 1, total: true),
         line("Opening Balance Equity", 1_389_500, 2, id: "30"),
         line("TOTAL LIABILITIES AND EQUITY", 1_639_500, 0, total: true)]
    }

    func report(aging: [AgingLine] = [], findings: [Finding] = []) -> MonthlyClientReport {
        MonthlyReportBuilder.build(MonthlyReportInputs(
            clientName: "Acme", period: AccountingPeriod(year: 2026, month: 7), today: AccountingDate(year: 2026, month: 10, day: 3),
            generatedAt: Date(), accountingBasis: "Accrual", environment: "sandbox", monthlyProfitAndLoss: [],
            balanceSheet: balanceSheet, cashFlow: [], agedReceivables: aging,
            accountTypes: ["35": .bank, "36": .bank, "90": .otherCurrentAsset, "91": .otherCurrentAsset, "38": .fixedAsset],
            findings: findings, coverage: .complete))
    }

    @Test("A sub-account is named with its parent account; section headings never prefix")
    func qualifiedLabels() {
        let bs = balanceSheet   // one instance: line ids are per-instance
        let names = bs.qualifiedLabels()
        let byLabel = Dictionary(uniqueKeysWithValues: bs.map { ($0.label, names[$0.id]) })
        #expect(byLabel["Original Cost"] == "Truck: Original Cost")
        #expect(byLabel["Checking"] == .some(nil))        // under "Bank Accounts", a section, not an account
        let chart = report().assets
        #expect(chart?.positiveItems.contains { $0.label == "Truck: Original Cost" } == true)
        #expect(chart?.negativeItems.contains { $0.label == "Checking" } == true)
    }

    @Test("The balance sheet table keeps headings, so Original Cost sits under Truck")
    func statementHeadings() {
        let rows = report().balanceSheetTable
        let truck = rows.firstIndex { $0.label == "Truck" }, cost = rows.firstIndex { $0.label == "Original Cost" }
        #expect(truck != nil && cost != nil && truck! < cost!)
        #expect(rows.first { $0.label == "Truck" }?.valueText == "")
        #expect(rows.contains { $0.label == "Bank Accounts" })
    }

    @Test("Working capital is also shown without suspense/clearing balances, and the ratio is flagged")
    func workingCapitalWithoutUnsettled() {
        let position = report().position
        // 2,900 − 2,500 = 400 on paper; without the 900 still under review it is (500).
        #expect(position.contains { $0.label.hasPrefix("Working capital (") && $0.valueText == "$400.00" })
        #expect(position.contains { $0.label.contains("without the $900.00 in suspense and clearing") && $0.valueText == "($500.00)" })
        #expect(position.contains { $0.label.hasPrefix("Current ratio") && $0.label.contains("under review or overdrawn") })
    }

    @Test("With the aging detail, buckets show only money owed and credits get their own bar; it still ties")
    func creditsOutsideBuckets() throws {
        var total = AgingLine(label: "TOTAL", current: .zero, days1to30: .zero, days31to60: usd(100_000), days61to90: usd(-80_000),
                              days91AndOver: usd(528_152), total: usd(548_152), depth: 0, isSummary: true)
        total.openItems = OpenItemsSplit(owed: usd(628_152), credits: usd(-80_000), over60Owed: usd(528_152), net: usd(548_152), itemCount: 9,
                                         owedByBucket: ["31-60": usd(100_000), "91+": usd(528_152)])
        let buckets = try #require(report(aging: [total]).receivables).buckets
        #expect(buckets.first { $0.id == "61-90" }?.label == "61–90 days")
        #expect(buckets.first { $0.id == "61-90" }?.value == 0)
        #expect(buckets.first { $0.id == "credits" }?.label == "Credits (not owed)")
        #expect(abs(buckets.map(\.value).reduce(0, +) - 5_481.52) < 0.001)
    }

    @Test("Without the detail, QuickBooks' netted buckets are used as before")
    func nettedFallback() throws {
        let total = AgingLine(label: "TOTAL", current: .zero, days1to30: .zero, days31to60: usd(100_000), days61to90: usd(-80_000),
                              days91AndOver: usd(528_152), total: usd(548_152), depth: 0, isSummary: true)
        let buckets = try #require(report(aging: [total]).receivables).buckets
        #expect(buckets.first { $0.id == "61-90" }?.label == "61–90 days (credits)")
        #expect(!buckets.contains { $0.id == "credits" })
    }

    @Test("An issue with no dollar amount shows a dash, never $0.00")
    func zeroExposureIsADash() {
        #expect(Money.zero.exposureText == "—")
        #expect(Money(minorUnits: 26_499, currency: .usd).exposureText == "$264.99")
    }
}
