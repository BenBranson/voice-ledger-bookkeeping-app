import Foundation
import Core

/// FICTIONAL sample data for reviewing the monthly report design. Lives
/// only in the dev tool — never in the app — and is flagged `isSample`,
/// which prints "SAMPLE DATA" on every page.
enum SampleMonthlyReport {
    static func usd(_ dollars: Double) -> Money { Money(minorUnits: Int64((dollars * 100).rounded()), currency: .usd) }
    static func line(_ label: String, _ dollars: Double?, depth: Int = 2, total: Bool = false, id: String? = nil) -> ReportLine {
        ReportLine(label: label, amount: dollars.map(usd), depth: depth, isSummary: total, accountID: id)
    }

    static func profitAndLoss(month: Int, year: Int) -> [ReportLine] {
        let season = [0.62, 0.66, 0.84, 1.05, 1.22, 1.30, 1.34, 1.26, 1.08, 0.92, 0.74, 0.64][month - 1]
        let growth = year == 2026 ? 1.09 : 1.0
        let services = (41_800 * season * growth).rounded()
        let materials = (9_600 * season * growth).rounded()
        let income = services + materials
        let cogs = ((materials * 0.58) + services * 0.21).rounded()
        let expenses: [(String, String, Double)] = [
            ("Payroll Expenses", "e1", (14_200 * (0.8 + season * 0.2)).rounded()),
            ("Vehicle Fuel", "e2", (2_150 * season).rounded()),
            ("Equipment Rental", "e3", (1_900 * season).rounded()),
            ("Rent or Lease", "e4", 3_200),
            ("Insurance", "e5", 1_140),
            ("Repairs & Maintenance", "e6", (860 * season).rounded()),
            ("Advertising & Marketing", "e7", month == 3 || month == 4 ? 2_400 : 650),
            ("Utilities", "e8", 540),
            ("Software & Subscriptions", "e9", 385),
            ("Office Supplies", "e10", 212),
            ("Bank Fees", "e11", 64),
            ("Meals", "e12", 148),
            ("Professional Fees", "e13", month == 7 && year == 2026 ? 3_750 : 450)
        ]
        let totalExpenses = expenses.map(\.2).reduce(0, +)
        let otherIncome = 42.0
        let otherExpenses = 310.0
        var lines: [ReportLine] = [
            line("Landscaping Services", services, id: "i1"),
            line("Materials Sales", materials, id: "i2"),
            line("Total Income", income, depth: 1, total: true),
            line("Cost of Goods Sold", cogs, id: "c1"),
            line("Total Cost of Goods Sold", cogs, depth: 1, total: true),
            line("Gross Profit", income - cogs, depth: 0, total: true)
        ]
        lines += expenses.map { line($0.0, $0.2, id: $0.1) }
        lines += [
            line("Total Expenses", totalExpenses, depth: 1, total: true),
            line("Net Operating Income", income - cogs - totalExpenses, depth: 0, total: true),
            line("Interest Earned", otherIncome, id: "o1"),
            line("Total Other Income", otherIncome, depth: 1, total: true),
            line("Depreciation", otherExpenses, id: "o2"),
            line("Total Other Expenses", otherExpenses, depth: 1, total: true),
            line("Net Other Income", otherIncome - otherExpenses, depth: 0, total: true),
            line("Net Income", income - cogs - totalExpenses + otherIncome - otherExpenses, depth: 0, total: true)
        ]
        return lines
    }

    static func build(generatedAt: Date) -> MonthlyClientReport {
        let period = AccountingPeriod(year: 2026, month: 7)
        let months = period.trailingMonths(13).map { MonthlyReport(period: $0, lines: profitAndLoss(month: $0.month, year: $0.year)) }
        let balanceSheet: [ReportLine] = [
            line("Business Checking", 38_412.55, depth: 3, id: "b1"),
            line("Payroll Checking", -1_284.10, depth: 3, id: "b2"),
            line("Savings", 25_000, depth: 3, id: "b3"),
            line("Total Bank Accounts", 62_128.45, depth: 2, total: true),
            line("Accounts Receivable (A/R)", 27_915.40, depth: 3, id: "a1"),
            line("Undeposited Funds", 1_850, depth: 3, id: "a2"),
            line("Trucks & Equipment", 96_500, depth: 3, id: "f1"),
            line("Accumulated Depreciation", -31_400, depth: 3, id: "f2"),
            line("TOTAL ASSETS", 156_993.85, depth: 0, total: true),
            line("Accounts Payable (A/P)", 9_842.18, depth: 3, id: "l1"),
            line("Business Credit Card", 4_318.92, depth: 3, id: "l2"),
            line("Sales Tax Payable", 1_206.44, depth: 3, id: "l3"),
            line("Equipment Loan", 48_750, depth: 3, id: "l4"),
            line("Owner's Investment", 20_000, depth: 3, id: "q1"),
            line("Owner's Draw", -18_500, depth: 3, id: "q2"),
            line("Retained Earnings", 62_210.47, depth: 3, id: "q3"),
            line("Net Income", 29_165.84, depth: 3),
            line("TOTAL LIABILITIES AND EQUITY", 156_993.85, depth: 0, total: true)
        ]
        let types: [String: LedgerAccountType] = ["b1": .bank, "b2": .bank, "b3": .bank, "a1": .accountsReceivable, "a2": .otherCurrentAsset, "f1": .fixedAsset, "f2": .fixedAsset,
                                                  "l1": .accountsPayable, "l2": .creditCard, "l3": .otherCurrentLiability, "l4": .longTermLiability, "q1": .equity, "q2": .equity, "q3": .equity]
        let cashFlow = [
            line("Net cash provided by operating activities", 11_236.18, depth: 0, total: true),
            line("Net cash provided by investing activities", -4_800, depth: 0, total: true),
            line("Net cash provided by financing activities", -2_625, depth: 0, total: true),
            line("Net cash increase for period", 3_811.18, depth: 0, total: true),
            line("Cash at end of period", 62_128.45, depth: 0, total: true)
        ]
        func aging(_ label: String, _ c: Double, _ a: Double, _ b: Double, _ d: Double, _ e: Double, total: Bool = false) -> AgingLine {
            AgingLine(label: label, current: usd(c), days1to30: usd(a), days31to60: usd(b), days61to90: usd(d), days91AndOver: usd(e), total: usd(c + a + b + d + e), depth: total ? 0 : 1, isSummary: total)
        }
        let receivables = [
            aging("Hillcrest HOA", 8_400, 3_150, 0, 0, 0),
            aging("Maple Ridge Apartments", 4_925.40, 2_200, 1_480, 0, 0),
            aging("Dr. Patel (residence)", 1_860, 0, 0, 0, 0),
            aging("Cedar Park Church", 0, 0, 0, 1_150, 2_310),
            aging("Various residential", 2_440, 0, 0, 0, 0),
            aging("TOTAL", 17_625.40, 5_350, 1_480, 1_150, 2_310, total: true)
        ]
        let realm = RealmID(rawValue: "sample")
        func finding(_ id: String, _ title: String, _ dollars: Double, _ confidence: Confidence, _ narrative: String, _ action: String) -> Finding {
            let procedure = GuidedProcedure(steps: ["Review in QuickBooks"], pitfalls: [], doneCriteria: "Resolved")
            return Finding(id: id, ruleID: RuleID(rawValue: "SAMPLE"), ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realm, period: period,
                           title: title, severity: .high, confidence: confidence, dollarExposure: usd(dollars), evidence: [],
                           proposedActions: [ProposedAction(id: id, title: action, resolution: .manualQBO, guidedProcedure: procedure, consequences: [], reversal: .reversibleManually(procedure: "Undo in QBO"))],
                           provenance: [], narrative: narrative, riskIfIgnored: nil)
        }
        let findings = [
            finding("s1", "Payroll Checking is overdrawn — ($1,284.10)", 1_284.10, .high, "The payroll account went negative after the July 31 payroll run posted before the funding transfer.", "Record or confirm the July 31 funding transfer"),
            finding("s2", "Payment from Cedar Park Church is 91+ days past due", 2_310, .high, "Two invoices from April remain unpaid.", "Follow up with the client on the April invoices"),
            finding("s3", "Possible duplicate bill — Green Valley Nursery, $1,640.00", 1_640, .medium, "Two bills for the same amount 3 days apart with slightly different vendor spellings.", "Compare both bills and void the duplicate"),
            finding("s4", "Professional Fees up sharply vs. trailing average", 3_300, .low, "July Professional Fees were $3,750 against a 3-month average of $450.", "Confirm the July legal invoice is a one-time cost")
        ]
        var input = MonthlyReportInputs(
            clientName: "Sample Landscaping Co.", period: period, today: AccountingDate(year: 2026, month: 9, day: 29), generatedAt: generatedAt,
            accountingBasis: "Accrual", environment: "sample", monthlyProfitAndLoss: months, balanceSheet: balanceSheet, cashFlow: cashFlow,
            agedReceivables: receivables, accountTypes: types, findings: findings, coverage: .complete
        )
        input.isSample = true
        return MonthlyReportBuilder.build(input)
    }
}
