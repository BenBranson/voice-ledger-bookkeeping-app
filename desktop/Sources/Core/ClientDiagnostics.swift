import Foundation

/// Owner feature list 2026-09-29: pre-cleanup scope score + quote, stale
/// bank-feed sentinel, period-over-period flux, and a KPI summary. All
/// deterministic over a `HistorySnapshot` (CLAUDE.md rule 1) — AI may
/// narrate these numbers, never produce them.
public enum ClientDiagnostics {}

// MARK: - Stale bank feed sentinel

public struct BankFeedActivity: Identifiable, Hashable, Sendable {
    public let accountID: String
    public let accountName: String
    public let lastActivity: AccountingDate?
    public let daysSinceLastActivity: Int?
    public let isStale: Bool
    public var id: String { accountID }
}

public extension ClientDiagnostics {
    static let staleFeedThresholdDays = 5

    /// QBO's API cannot see bank-feed connection status, so this is an
    /// INFERENCE: the newest posted transaction touching each bank/credit
    /// card account. No posting in over 5 days usually means the feed
    /// stopped pulling (or nobody has accepted "For Review" items).
    static func bankFeedActivity(history: HistorySnapshot, asOf: AccountingDate) -> [BankFeedActivity] {
        var latest: [String: AccountingDate] = [:]
        func note(_ accountID: String?, _ date: AccountingDate?) {
            guard let accountID, let date else { return }
            if let existing = latest[accountID], existing >= date { return }
            latest[accountID] = date
        }
        for txn in history.transactions where !txn.isVoided {
            note(txn.paymentAccountID, txn.txnDate)
        }
        for deposit in history.deposits {
            note(deposit.depositToAccountID, deposit.txnDate)
        }
        return history.accounts
            .filter { $0.accountType == .bank || $0.accountType == .creditCard }
            .map { account in
                let last = latest[account.id]
                let days = last.map { AccountingDate.daysBetween($0, asOf) }
                return BankFeedActivity(
                    accountID: account.id,
                    accountName: account.name,
                    lastActivity: last,
                    daysSinceLastActivity: days,
                    isStale: (days ?? Int.max) > staleFeedThresholdDays
                )
            }
            .sorted { ($0.daysSinceLastActivity ?? Int.max) > ($1.daysSinceLastActivity ?? Int.max) }
    }
}

// MARK: - Flux analysis

public struct FluxAlert: Identifiable, Hashable, Sendable {
    public let label: String
    public let period: AccountingPeriod
    public let current: Money
    public let trailingAverage: Money
    public let change: Money
    /// `nil` when the trailing average is zero (a brand-new line).
    public let percentChange: Double?
    public var id: String { label }
}

public extension ClientDiagnostics {
    static let fluxPercentThreshold = 0.20
    static let fluxDollarThreshold = Money(minorUnits: 50_000, currency: .usd)

    /// Flags any P&L account line whose most recent COMPLETE month differs
    /// from its trailing 3-month average by more than 20% AND more than
    /// $500. Needs at least 4 complete months.
    static func fluxAlerts(history: HistorySnapshot, asOf: AccountingDate) -> [FluxAlert] {
        let currentMonth = AccountingPeriod(year: asOf.year, month: asOf.month)
        let complete = history.monthlyProfitAndLoss.filter { $0.period != currentMonth }
        guard complete.count >= 4, let latest = complete.last else { return [] }
        let trailing = complete.dropLast().suffix(3)

        func amounts(_ report: MonthlyReport) -> [String: Money] {
            var result: [String: Money] = [:]
            for line in report.lines where !line.isSummary {
                if let amount = line.amount { result[line.label] = (result[line.label] ?? .zero) + amount }
            }
            return result
        }
        let latestAmounts = amounts(latest)
        let trailingAmounts = trailing.map(amounts)
        let labels = Set(latestAmounts.keys).union(trailingAmounts.flatMap(\.keys))

        var alerts: [FluxAlert] = []
        for label in labels {
            let current = latestAmounts[label] ?? .zero
            let trailingTotal = trailingAmounts.reduce(Int64(0)) { $0 + ($1[label]?.minorUnits ?? 0) }
            let average = Money(minorUnits: (trailingTotal * 10 / 3 + (trailingTotal >= 0 ? 5 : -5)) / 10, currency: .usd)
            let change = current - average
            guard abs(change.minorUnits) > fluxDollarThreshold.minorUnits else { continue }
            let percent: Double? = average.minorUnits == 0 ? nil : Double(change.minorUnits) / Double(abs(average.minorUnits))
            if let percent, abs(percent) <= fluxPercentThreshold { continue }
            alerts.append(FluxAlert(label: label, period: latest.period, current: current, trailingAverage: average, change: change, percentChange: percent))
        }
        return alerts.sorted { abs($0.change.minorUnits) > abs($1.change.minorUnits) }
    }
}

// MARK: - KPI summary

public struct KPISummary: Hashable, Sendable {
    public let period: AccountingPeriod?
    public let grossMarginPercent: Double?
    public let operatingCashFlow: Money?
    public let daysSalesOutstanding: Double?
    public let revenue: Money?
    public let netIncome: Money?

    /// Ready to paste into a monthly client review email. Missing metrics
    /// say so rather than being silently dropped.
    public var emailBullets: [String] {
        let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
        let monthName = period.map { "\(monthNames[$0.month - 1]) \($0.year)" } ?? "the latest month"
        return [
            "Revenue for \(monthName): \(revenue?.accountingDescription ?? "not available")",
            "Net income: \(netIncome?.accountingDescription ?? "not available")",
            "Gross margin: \(grossMarginPercent.map { String(format: "%.1f%%", $0) } ?? "not available (no Gross Profit on the P&L)")",
            "Operating cash flow: \(operatingCashFlow?.accountingDescription ?? "not available")",
            "Days sales outstanding: \(daysSalesOutstanding.map { String(format: "%.0f days", $0) } ?? "not available (no revenue in the trailing 3 months)")"
        ]
    }
}

public extension ClientDiagnostics {
    static func kpiSummary(history: HistorySnapshot, asOf: AccountingDate) -> KPISummary {
        let currentMonth = AccountingPeriod(year: asOf.year, month: asOf.month)
        let complete = history.monthlyProfitAndLoss.filter { $0.period != currentMonth }
        let latest = complete.last
        let revenue = latest.flatMap { FinancialKPIs.totalIncome(from: $0.lines) }
        let netIncome = latest.flatMap { TaxEstimate.netIncome(from: $0.lines) }
        let grossMargin = latest.flatMap { FinancialKPIs.grossMarginPercent(from: $0.lines) }
        let operatingCashFlow = history.latestCashFlow.first { $0.isSummary && $0.label == "Net cash provided by operating activities" }?.amount

        // DSO = A/R ÷ trailing-90-day revenue × 90.
        let receivables = history.latestBalanceSheet.first { $0.isSummary && $0.label == "Total Accounts Receivable" }?.amount
        let trailingRevenue = complete.suffix(3).compactMap { FinancialKPIs.totalIncome(from: $0.lines) }.reduce(Money.zero, +)
        let dso: Double? = {
            guard let receivables, trailingRevenue.minorUnits > 0 else { return nil }
            return receivables.majorUnitsDouble / trailingRevenue.majorUnitsDouble * 90
        }()

        return KPISummary(period: latest?.period, grossMarginPercent: grossMargin, operatingCashFlow: operatingCashFlow, daysSalesOutstanding: dso, revenue: revenue, netIncome: netIncome)
    }
}

// MARK: - Cleanup scope score + quote

public struct CleanupScopeInputs: Hashable, Sendable {
    public var unreconciledMonths: Int
    public var baseFee: Money
    public var perUnreconciledMonth: Money
    public var perAnomaly: Money
    public var perUncategorizedTransaction: Money
    public var hourlyRate: Money

    public init(
        unreconciledMonths: Int = 0,
        baseFee: Money = Money(minorUnits: 50_000, currency: .usd),
        perUnreconciledMonth: Money = Money(minorUnits: 15_000, currency: .usd),
        perAnomaly: Money = Money(minorUnits: 3_500, currency: .usd),
        perUncategorizedTransaction: Money = Money(minorUnits: 250, currency: .usd),
        hourlyRate: Money = Money(minorUnits: 10_000, currency: .usd)
    ) {
        self.unreconciledMonths = unreconciledMonths
        self.baseFee = baseFee
        self.perUnreconciledMonth = perUnreconciledMonth
        self.perAnomaly = perAnomaly
        self.perUncategorizedTransaction = perUncategorizedTransaction
        self.hourlyRate = hourlyRate
    }
}

public struct CleanupScopeScore: Equatable, Sendable {
    public let score: Int
    public let band: String
    public let monthsScanned: Int
    public let averageMonthlyTransactions: Int
    public let volumeTier: PricingCalculator.VolumeTier
    public let unreconciledMonths: Int
    public let undepositedPaymentCount: Int
    public let undepositedPaymentTotal: Money
    public let unappliedVendorCreditTotal: Money
    public let duplicateAccountGroups: Int
    public let agedOver90Count: Int
    public let openAnomalies: Int
    public let uncategorizedTransactions: Int
    public let totalExposure: Money
    public let cleanupQuote: Money
    public let estimatedHoursLow: Int
    public let estimatedHoursHigh: Int
    public let monthlyRetainer: PricingCalculator.MonthlyQuote
}

public extension ClientDiagnostics {
    static func scopeScore(history: HistorySnapshot, openFindings: [Finding], asOf: AccountingDate, inputs: CleanupScopeInputs) -> CleanupScopeScore {
        let months = max(history.monthsCovered, 1)
        let average = history.transactions.count / months
        let tier: PricingCalculator.VolumeTier = average < 200 ? .light : (average < 500 ? .growth : .high)

        let bankAccountIDs = Set(history.accounts.filter { $0.accountType == .bank }.map(\.id))
        let deposited = Set(history.deposits.flatMap(\.linkedPaymentIDs))
        let undeposited = history.transactions.filter {
            $0.entityKind == .payment && !$0.isVoided && !deposited.contains($0.id) && !bankAccountIDs.contains($0.paymentAccountID ?? "")
        }
        let undepositedTotal = undeposited.reduce(Money.zero) { $0 + $1.totalAmount }
        let agedOver90 = undeposited.filter { AccountingDate.daysBetween($0.txnDate, asOf) > 90 }.count
        let unappliedCredits = history.vendorCredits.reduce(Money.zero) { $0 + $1.balance }

        // Leaf-name matching is a known false-positive trap (8 on the
        // sandbox); reuse the FullyQualifiedName-based detector.
        let duplicateGroups = ChartOfAccountsCleanup.findDuplicateCandidates(history.accounts).count

        let open = openFindings.filter { $0.status == .open }
        let uncategorized = open.filter { $0.ruleID.rawValue == "VL-CAT-UNCAT-001" }.count
        let anomalies = open.count - uncategorized
        let exposure = open.reduce(Money.zero) { $0 + $1.dollarExposure }

        let score = min(100,
            min(inputs.unreconciledMonths * 4, 30)
            + min(undeposited.count, 15)
            + min(duplicateGroups * 3, 15)
            + min(agedOver90 * 2, 15)
            + min(open.count, 25))
        let band: String
        switch score {
        case ..<26: band = "Light"
        case 26..<51: band = "Moderate"
        case 51..<76: band = "Heavy"
        default: band = "Severe"
        }

        func times(_ money: Money, _ count: Int) -> Money { Money(minorUnits: money.minorUnits * Int64(count), currency: money.currency) }
        let quote = inputs.baseFee
            + times(inputs.perUnreconciledMonth, inputs.unreconciledMonths)
            + times(inputs.perAnomaly, anomalies)
            + times(inputs.perUncategorizedTransaction, uncategorized)
        let hours = inputs.hourlyRate.minorUnits > 0 ? Double(quote.minorUnits) / Double(inputs.hourlyRate.minorUnits) : 0

        let retainer = PricingCalculator.monthlyQuote(
            tier: tier,
            hourlyRate: inputs.hourlyRate,
            flags: PricingCalculator.MonthlyComplexityFlags(multipleBankAccounts: bankAccountIDs.count > 1)
        )

        return CleanupScopeScore(
            score: score,
            band: band,
            monthsScanned: history.monthsCovered,
            averageMonthlyTransactions: average,
            volumeTier: tier,
            unreconciledMonths: inputs.unreconciledMonths,
            undepositedPaymentCount: undeposited.count,
            undepositedPaymentTotal: undepositedTotal,
            unappliedVendorCreditTotal: unappliedCredits,
            duplicateAccountGroups: duplicateGroups,
            agedOver90Count: agedOver90,
            openAnomalies: anomalies,
            uncategorizedTransactions: uncategorized,
            totalExposure: exposure,
            cleanupQuote: quote,
            estimatedHoursLow: Int((hours * 0.85).rounded()),
            estimatedHoursHigh: Int((hours * 1.15).rounded()),
            monthlyRetainer: retainer
        )
    }
}
