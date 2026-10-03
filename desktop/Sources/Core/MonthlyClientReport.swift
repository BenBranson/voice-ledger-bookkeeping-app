import Foundation
import CryptoKit

/// The client-facing monthly report (owner request 2026-09-29): a fully
/// computed, self-describing snapshot. The renderer (report-renderer/)
/// only lays it out — every figure, comparison, and check is decided here,
/// deterministically. Saved next to its PDF so a report can be traced and
/// reproduced.
public struct MonthlyClientReport: Codable, Sendable {
    public struct Meta: Codable, Sendable {
        public let firmName: String
        public let clientName: String
        public let periodKey: String
        public let periodLabel: String
        public let generatedAt: String
        public let generatedAtLabel: String
        public let accountingBasis: String
        public let balanceDateLabel: String
        public let isPartialMonth: Bool
        public let environment: String
        public let isSample: Bool
        public var snapshotID: String
    }

    public struct KPI: Codable, Sendable {
        public let id: String
        public let label: String
        public let valueText: String
        public let comparisonText: String
        public let detail: String
        public let isNegative: Bool
    }

    public struct ComparisonRow: Codable, Sendable {
        public let label: String
        public let currentText: String
        public let priorText: String
        public let changeText: String
        public let percentText: String
    }

    public struct Row: Codable, Sendable {
        public let label: String
        public let valueText: String
        public let depth: Int
        public let isTotal: Bool
    }

    public struct Cash: Codable, Sendable {
        public let accounts: [ChartItem]
        public let totalText: String?
        public let cashFlow: [Row]
        public let note: String
    }

    public struct Receivables: Codable, Sendable {
        public let buckets: [ChartItem]
        public let totalText: String
        public let topCustomers: [Row]
        public let note: String
        /// Credits and unapplied payments (negative buckets), kept apart
        /// from money owed.
        public var creditsText: String? = nil
    }

    public struct FindingRow: Codable, Sendable {
        public let title: String
        public let amountText: String
        public let detail: String
        public let action: String?
    }

    public struct Check: Codable, Sendable {
        public let label: String
        public let passed: Bool
        public let detail: String
    }

    public let schemaVersion: Int
    public var meta: Meta
    public var kpis: [KPI]
    public let monthOverMonth: [ComparisonRow]
    public let yearOverYear: [ComparisonRow]?
    public let trend: TrendData?
    public let waterfall: WaterfallData?
    public let expenses: RankedBars?
    public let assets: SignedBreakdown?
    public let liabilitiesAndEquity: SignedBreakdown?
    public let cash: Cash?
    public let receivables: Receivables?
    public var verifiedFindings: [FindingRow]
    public var reviewFindings: [FindingRow]
    public let recommendedActions: [String]
    public let profitAndLossTable: [Row]
    public let balanceSheetTable: [Row]
    public let checks: [Check]
    public var notes: [String]

    // Owner-summary and narrative sections (MonthlyReportSections.swift).
    public struct HealthCheck: Codable, Sendable {
        public let area: String
        public let question: String
        public let status: String
        public let statusKind: String
        public let detail: String
    }

    public struct Priority: Codable, Sendable {
        public let action: String
        public let owner: String
        public let why: String
        public let timing: String
        public var status = "Open"
        public var impact = ""
    }

    public struct Narrative: Codable, Sendable {
        public let happened: String
        public let matters: String
        public let next: String
    }

    public struct ComparativeRow: Codable, Sendable {
        public let label: String
        public let currentText: String
        public let priorText: String
        public let depth: Int
        public let isTotal: Bool
    }

    public var preparedBy = ""
    public var healthChecks: [HealthCheck] = []
    public var takeaways: [String] = []
    public var priorities: [Priority] = []
    public var questionsForClient: [String] = []
    public var narratives: [String: Narrative] = [:]
    public var expenseChanges: [ComparisonRow] = []
    public var payables: Receivables?
    public var position: [Row] = []
    public var workCompleted: [WorkItem] = []
    public var workSummary: [Row] = []
    public var comparativeProfitAndLoss: [ComparativeRow] = []
    public var cashFlowStatement: [Row] = []
    public var moneyFlow: MoneyFlowData?
    public var sparklines: SparklineData?

    // Integrity additions (owner review 2026-09-29; MonthlyReportIntegrity.swift).
    public var openItems: [ReportOpenItem] = []
    /// The one status count every page uses.
    public var statusSummary: [Row] = []
    public var droppedAfterPeriod = 0
    public var autoClearedCount = 0
    public var performanceBridge: PerformanceBridge?
    public var ytd: [ComparativeRow] = []
    public var ytdLabel: String?
    public var cashTie: [Row] = []
    public var workImpact: [WorkImpactRow] = []
    public var reportingConfidence: String?
}

public struct MonthlyReportInputs: Sendable {
    public var firmName = "Benjamin Branson Bookkeeping"
    public var clientName: String
    public var period: AccountingPeriod
    public var today: AccountingDate
    public var generatedAt: Date
    public var accountingBasis: String?
    public var environment: String
    public var isSample = false
    /// Oldest first, ending with `period`; up to 13 months so the same
    /// month last year can be compared when it exists.
    public var monthlyProfitAndLoss: [MonthlyReport]
    public var balanceSheet: [ReportLine]
    public var cashFlow: [ReportLine]
    public var agedReceivables: [AgingLine]
    public var accountTypes: [String: LedgerAccountType]
    public var findings: [Finding]
    public var coverage: Coverage
    public var agedPayables: [AgingLine] = []
    public var receivablesLoaded = true
    public var payablesLoaded = true
    public var activityLog: [ActivityLogEntry] = []
    public var clientQuestions: [ClientQuestionDrafter.Thread] = []
    public var preparedBy = "Benjamin Branson"
    public var monthEndCash: [MonthlyAmount] = []

    public init(clientName: String, period: AccountingPeriod, today: AccountingDate, generatedAt: Date, accountingBasis: String?, environment: String, monthlyProfitAndLoss: [MonthlyReport], balanceSheet: [ReportLine], cashFlow: [ReportLine], agedReceivables: [AgingLine], accountTypes: [String: LedgerAccountType], findings: [Finding], coverage: Coverage) {
        self.clientName = clientName
        self.period = period
        self.today = today
        self.generatedAt = generatedAt
        self.accountingBasis = accountingBasis
        self.environment = environment
        self.monthlyProfitAndLoss = monthlyProfitAndLoss
        self.balanceSheet = balanceSheet
        self.cashFlow = cashFlow
        self.agedReceivables = agedReceivables
        self.accountTypes = accountTypes
        self.findings = findings
        self.coverage = coverage
    }
}

public enum MonthlyReportBuilder {
    public static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

    static func label(_ p: AccountingPeriod) -> String { "\(monthNames[p.month - 1]) \(p.year)" }

    static func summary(_ label: String, _ lines: [ReportLine]) -> Money? {
        lines.first { $0.isSummary && $0.label == label }?.amount
    }

    static func totalCosts(_ lines: [ReportLine]) -> Money? {
        let parts = ["Total Cost of Goods Sold", "Total Expenses", "Total Other Expenses"].compactMap { summary($0, lines) }
        return parts.isEmpty ? (summary("Total Income", lines) == nil ? nil : .zero) : parts.reduce(.zero, +)
    }

    /// Percent change only when the baseline is positive; a zero or
    /// negative baseline makes a percentage misleading.
    public static func percentText(current: Money?, prior: Money?) -> String {
        guard let current, let prior else { return "—" }
        guard prior.minorUnits > 0 else { return "n/m" }
        let pct = Double(current.minorUnits - prior.minorUnits) / Double(prior.minorUnits) * 100
        return String(format: "%+.1f%%", pct)
    }

    public static func changeText(current: Money?, prior: Money?) -> String {
        guard let current, let prior else { return "No comparable data" }
        let delta = current - prior
        return (delta.minorUnits > 0 ? "+" : "") + delta.accountingDescription
    }

    public static func build(_ input: MonthlyReportInputs) -> MonthlyClientReport {
        let monthly = input.monthlyProfitAndLoss
        let current = monthly.first { $0.period == input.period }
        let prior = monthly.first { $0.period == input.period.previousMonth }
        let lastYear = monthly.first { $0.period == AccountingPeriod(year: input.period.year - 1, month: input.period.month) }
        let pnl = current?.lines ?? []

        let revenue = summary("Total Income", pnl) ?? (pnl.isEmpty ? nil : .zero)
        let costs = totalCosts(pnl)
        let net = TaxEstimate.netIncome(from: pnl) ?? (pnl.isEmpty ? nil : .zero)
        let priorRevenue = prior.map { summary("Total Income", $0.lines) ?? .zero }
        let priorCosts = prior.flatMap { totalCosts($0.lines) ?? .zero }
        let priorNet = prior.map { TaxEstimate.netIncome(from: $0.lines) ?? .zero }
        let cash = summary("Total Bank Accounts", input.balanceSheet)

        let isPartial = input.period.contains(input.today) && input.today.day < input.period.daysInMonth
        let periodEndDay = isPartial ? input.today.day : input.period.daysInMonth
        let balanceDate = "\(monthNames[input.period.month - 1]) \(periodEndDay), \(input.period.year)"

        func vsPrior(_ c: Money?, _ p: Money?) -> String {
            guard p != nil else { return "No prior-month data" }
            let pct = percentText(current: c, prior: p)
            return "\(changeText(current: c, prior: p)) vs \(label(input.period.previousMonth))" + (pct == "n/m" || pct == "—" ? "" : " (\(pct))")
        }

        let kpis = [
            MonthlyClientReport.KPI(id: "revenue", label: "Revenue", valueText: revenue?.accountingDescription ?? "Not available", comparisonText: vsPrior(revenue, priorRevenue), detail: "Total Income, \(label(input.period))", isNegative: false),
            MonthlyClientReport.KPI(id: "expenses", label: "Total costs", valueText: costs?.accountingDescription ?? "Not available", comparisonText: vsPrior(costs, priorCosts), detail: "COGS + operating + other expenses", isNegative: false),
            MonthlyClientReport.KPI(id: "net", label: (net?.minorUnits ?? 0) < 0 ? "Net Loss" : "Net Profit", valueText: net?.accountingDescription ?? "Not available", comparisonText: vsPrior(net, priorNet), detail: "Net Income per QuickBooks", isNegative: (net?.minorUnits ?? 0) < 0),
            MonthlyClientReport.KPI(id: "cash", label: "Cash in Bank", valueText: cash?.accountingDescription ?? "Not available", comparisonText: "Balance as of \(balanceDate)", detail: "Total Bank Accounts on the Balance Sheet", isNegative: (cash?.minorUnits ?? 0) < 0)
        ]

        func rows(_ c: MonthlyReport?, _ p: MonthlyReport?) -> [MonthlyClientReport.ComparisonRow] {
            let cl = c?.lines ?? [], pl = p?.lines ?? []
            let items: [(String, Money?, Money?)] = [
                ("Revenue", summary("Total Income", cl) ?? .zero, p == nil ? nil : summary("Total Income", pl) ?? .zero),
                ("Total costs", totalCosts(cl) ?? .zero, p == nil ? nil : totalCosts(pl) ?? .zero),
                ("Net income", TaxEstimate.netIncome(from: cl) ?? .zero, p == nil ? nil : TaxEstimate.netIncome(from: pl) ?? .zero)
            ]
            return items.map { name, cv, pv in
                MonthlyClientReport.ComparisonRow(label: name, currentText: cv?.accountingDescription ?? "—", priorText: pv?.accountingDescription ?? "No data", changeText: changeText(current: cv, prior: pv), percentText: percentText(current: cv, prior: pv))
            }
        }
        let lastYearHasActivity = lastYear.map { !$0.lines.filter { !$0.isSummary && $0.amount != nil }.isEmpty } ?? false

        let bankItems: [ChartItem] = input.balanceSheet.filter { !$0.isSummary && $0.amount != nil && $0.accountID.flatMap { input.accountTypes[$0] } == .bank }
            .map { ChartItem(id: $0.stableKey, accountID: $0.accountID, label: $0.label, value: $0.amount!.majorUnitsDouble, valueText: $0.amount!.accountingDescription, category: $0.amount!.minorUnits < 0 ? "overdraft" : "asset", note: $0.amount!.minorUnits < 0 ? "Overdrawn" : nil) }
        let cashFlowLabels = ["Net cash provided by operating activities", "Net cash provided by investing activities", "Net cash provided by financing activities", "Net cash increase for period", "Cash at end of period"]
        let cashFlowRows = cashFlowLabels.compactMap { name -> MonthlyClientReport.Row? in
            guard let amount = summary(name, input.cashFlow) else { return nil }
            return MonthlyClientReport.Row(label: name.prefix(1).uppercased() + name.dropFirst(), valueText: amount.accountingDescription, depth: 0, isTotal: name.hasPrefix("Cash at end"))
        }
        let cashSection = (bankItems.isEmpty && cashFlowRows.isEmpty) ? nil : MonthlyClientReport.Cash(
            accounts: bankItems,
            totalText: cash?.accountingDescription,
            cashFlow: cashFlowRows,
            note: cashFlowRows.isEmpty
                ? "QuickBooks' Statement of Cash Flows was not available for this period, so cash movement is not shown. Profit is not a substitute for cash flow."
                : "Cash movement comes from QuickBooks' Statement of Cash Flows for \(label(input.period)) — it differs from profit because of timing (receivables, payables) and non-operating items."
        )

        let arTotal = input.agedReceivables.last { $0.isSummary }
        let receivables: MonthlyClientReport.Receivables? = arTotal.flatMap { total in
            guard let grand = total.total, grand.minorUnits != 0 else { return nil }
            let split = AgingSplit(total)
            let buckets: [(String, String, Money?)] = [("current", "Current", total.current), ("1-30", "1–30 days", total.days1to30), ("31-60", "31–60 days", total.days31to60), ("61-90", "61–90 days", total.days61to90), ("91+", "91+ days", total.days91AndOver)]
            let customers = input.agedReceivables.filter { !$0.isSummary && ($0.total?.minorUnits ?? 0) != 0 }
                .sorted { ($0.total?.minorUnits ?? 0) > ($1.total?.minorUnits ?? 0) }.prefix(8)
                .map { MonthlyClientReport.Row(label: $0.label, valueText: $0.total!.accountingDescription, depth: 0, isTotal: false) }
            // With QuickBooks' per-invoice detail, buckets show only money owed and
            // customer credits get their own bar (they aren't an age). Without it,
            // fall back to QuickBooks' netted buckets.
            let exact = total.openItems.flatMap { o in o.owedByBucket.isEmpty || total.total.map({ $0 != o.net }) == true ? nil : o }
            var items: [ChartItem] = buckets.map { id, name, amount in
                let value = exact.map { $0.owedByBucket[id] ?? .zero } ?? (amount ?? .zero)
                let isCredit = value.minorUnits < 0
                return ChartItem(id: id, accountID: nil, label: isCredit ? "\(name) (credits)" : name, value: value.majorUnitsDouble, valueText: value.accountingDescription, category: isCredit ? "credit" : id == "91+" ? "overdraft" : "asset")
            }
            if let exact, exact.credits.minorUnits < 0 {
                items.append(ChartItem(id: "credits", accountID: nil, label: "Credits (not owed)", value: exact.credits.majorUnitsDouble, valueText: exact.credits.accountingDescription, category: "credit"))
            }
            return MonthlyClientReport.Receivables(
                buckets: items,
                totalText: grand.accountingDescription,
                topCustomers: Array(customers),
                note: split.credits.minorUnits < 0
                    ? "Aging as of \(balanceDate), matching the Balance Sheet. \(split.creditsProseText) is customer credits or payments not yet applied to an invoice — not money owed. It is netted into the total but excluded from the \"older than 60 days\" figures; it should be applied to an open invoice or refunded. 91+ days is at risk of not being collected."
                    : "Aging as of \(balanceDate), matching the Balance Sheet; 91+ days is at risk of not being collected.",
                creditsText: split.credits.minorUnits < 0 ? split.credits.accountingDescription : nil
            )
        }

        let open = FindingTriage.sorted(input.findings.filter { $0.status == .open })
        func row(_ f: Finding) -> MonthlyClientReport.FindingRow {
            // A finding with no dollar exposure (e.g. a duplicate vendor record) shows "—", not "$0.00".
            MonthlyClientReport.FindingRow(title: f.title, amountText: f.dollarExposure.exposureText, detail: f.narrative ?? "", action: f.proposedActions.first?.title)
        }
        let verified = open.filter { $0.confidence == .high }.prefix(12).map(row)
        let review = open.filter { $0.confidence != .high }.prefix(12).map(row)
        var actions: [String] = []
        for f in open.prefix(8) {
            guard let title = f.proposedActions.first?.title else { continue }
            let line = f.dollarExposure.minorUnits == 0 ? title : "\(title) (\(f.dollarExposure.accountingDescription))"
            if !actions.contains(line) { actions.append(line) }
        }

        let waterfall = ChartData.waterfall(from: pnl)
        let expenses = ChartData.expenseCategories(from: pnl)
        let assets = ChartData.signedBreakdown(from: input.balanceSheet, section: .assets, accountTypes: input.accountTypes)
        let liabilities = ChartData.signedBreakdown(from: input.balanceSheet, section: .liabilitiesAndEquity, accountTypes: input.accountTypes)

        var checks: [MonthlyClientReport.Check] = []
        if let waterfall { checks.append(.init(label: "Revenue-to-net-income bridge ties to QuickBooks net income", passed: waterfall.reconciles, detail: waterfall.note ?? "Ties exactly.")) }
        if let expenses { checks.append(.init(label: "Expense categories sum to Total Expenses", passed: expenses.reconciles, detail: "Categories \(expenses.totalText) vs reported \(expenses.reportedTotalText ?? "not reported")")) }
        if let assets { checks.append(.init(label: "Asset accounts sum to Total Assets", passed: assets.reconciles, detail: "Accounts \(assets.netText) vs reported \(assets.reportedTotalText ?? "not reported")")) }
        if let liabilities { checks.append(.init(label: "Liability and equity accounts sum to Total Liabilities & Equity", passed: liabilities.reconciles, detail: "Accounts \(liabilities.netText) vs reported \(liabilities.reportedTotalText ?? "not reported")")) }

        if let tie = CashTie.rows(balanceSheet: input.balanceSheet, cashFlow: input.cashFlow) {
            checks.append(.init(label: "Bank balances plus undeposited funds equal the cash-flow statement's ending cash", passed: tie.ties, detail: tie.detail))
        }

        var notes: [String] = []
        notes.append("Accounting basis: \(input.accountingBasis ?? "not stated by QuickBooks") — all periods in this report use the same basis and calendar-month boundaries.")
        if isPartial { notes.append("\(label(input.period)) is still in progress: figures run through \(balanceDate) and will change.") }
        if case .partial(let reason) = input.coverage { notes.append("Data coverage is incomplete: \(reason)") }
        if prior == nil { notes.append("No prior-month data was loaded, so month-over-month comparisons are omitted.") }
        if !lastYearHasActivity { notes.append("Year-over-year comparison omitted: no activity is recorded for \(label(AccountingPeriod(year: input.period.year - 1, month: input.period.month))).") }
        if let trend = Optional(ChartData.trend(from: monthly)), !trend.points.isEmpty { notes.append("Trend: \(trend.note)") }
        for check in checks where !check.passed { notes.append("Check not passed — \(check.label): \(check.detail)") }
        if input.environment == "sandbox" { notes.append("Generated from a QuickBooks SANDBOX company, not a real client's books.") }
        notes.append("Status labels: \"Confirmed issue\" is established directly from the QuickBooks data; \"Possible issue\" is a pattern that often signals an error but isn't established; \"Corrected and verified\" means a person made the correction and a later QuickBooks sync confirms it.")

        let pnlTable = pnl.filter { $0.amount != nil }.map { MonthlyClientReport.Row(label: $0.label, valueText: $0.amount!.accountingDescription, depth: $0.depth, isTotal: $0.isSummary) }
        // Section and parent-account headings ("Bank Accounts", "Truck") have no amount
        // but are kept, so a child like "Original Cost" is never shown without its parent.
        let bsTable = input.balanceSheet.filter { $0.amount != nil || !$0.isSummary }.map { MonthlyClientReport.Row(label: $0.label, valueText: $0.amount?.accountingDescription ?? "", depth: $0.depth, isTotal: $0.isSummary) }

        let formatter = ISO8601DateFormatter()
        let display = DateFormatter()
        display.dateStyle = .long
        display.timeStyle = .short
        display.locale = Locale(identifier: "en_US")

        let base = MonthlyClientReport(
            schemaVersion: 1,
            meta: .init(
                firmName: input.firmName, clientName: input.clientName,
                periodKey: "\(input.period.year)-\(String(format: "%02d", input.period.month))", periodLabel: label(input.period),
                generatedAt: formatter.string(from: input.generatedAt), generatedAtLabel: display.string(from: input.generatedAt),
                accountingBasis: input.accountingBasis ?? "Not stated", balanceDateLabel: "Balances as of \(balanceDate)",
                isPartialMonth: isPartial, environment: input.environment, isSample: input.isSample, snapshotID: ""
            ),
            kpis: kpis,
            monthOverMonth: prior == nil ? [] : rows(current, prior),
            yearOverYear: lastYearHasActivity ? rows(current, lastYear) : nil,
            trend: { let t = ChartData.trend(from: monthly); return t.points.count >= 2 ? t : nil }(),
            waterfall: waterfall,
            expenses: expenses,
            assets: assets,
            liabilitiesAndEquity: liabilities,
            cash: cashSection,
            receivables: receivables,
            verifiedFindings: Array(verified),
            reviewFindings: Array(review),
            recommendedActions: actions,
            profitAndLossTable: pnlTable,
            balanceSheetTable: bsTable,
            checks: checks,
            notes: notes
        )
        return MonthlyReportSections.enrich(base, input: input)
    }
}

public extension MonthlyClientReport {
    /// Canonical JSON with `meta.snapshotID` set to the SHA-256 of the
    /// report content, so a PDF can be traced to exactly this data.
    func sealedJSON() throws -> (json: Data, snapshotID: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        var copy = self
        copy.meta.snapshotID = ""
        let digest = SHA256.hash(data: try encoder.encode(copy)).map { String(format: "%02x", $0) }.joined()
        copy.meta.snapshotID = digest
        return (try encoder.encode(copy), digest)
    }
}
