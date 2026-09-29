import Foundation

/// Validated chart data shared by the in-app ECharts views and the monthly
/// PDF renderer (owner request 2026-09-29). Every number here is computed
/// deterministically from QBO report lines (CLAUDE.md rule 1); the
/// JavaScript side only draws it. Items are keyed by `ReportLine.stableKey`
/// (QBO account ID when available), never by array position.
public struct ChartItem: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let accountID: String?
    public let label: String
    public let value: Double
    public let valueText: String
    /// Drives color and meaning: asset, liability, equity, expense,
    /// overdraft, contra, creditBalance, debitBalance, negativeEquity,
    /// deficit, netLoss, other.
    public let category: String
    public let note: String?
    /// Share of the stated denominator, 0...1; `nil` for negative items.
    public let share: Double?

    public init(id: String, accountID: String?, label: String, value: Double, valueText: String, category: String, note: String? = nil, share: Double? = nil) {
        self.id = id
        self.accountID = accountID
        self.label = label
        self.value = value
        self.valueText = valueText
        self.category = category
        self.note = note
        self.share = share
    }
}

private extension Money {
    static func fromMajor(_ value: Double) -> Money { Money(minorUnits: Int64((value * 100).rounded()), currency: .usd) }
}

private func summary(_ label: String, in lines: [ReportLine]) -> Money? {
    lines.first { $0.isSummary && $0.label == label }?.amount
}

// MARK: - Signed balance breakdown (assets / liabilities & equity)

public struct SignedBreakdown: Codable, Equatable, Sendable {
    public let title: String
    public let positiveItems: [ChartItem]
    public let negativeItems: [ChartItem]
    public let positiveSubtotal: Double
    public let positiveSubtotalText: String
    public let negativeSubtotal: Double
    public let negativeSubtotalText: String
    public let net: Double
    public let netText: String
    /// The section total QBO reported (TOTAL ASSETS / TOTAL LIABILITIES AND
    /// EQUITY), and whether our items add up to it.
    public let reportedTotalText: String?
    public let reconciles: Bool
    public let percentDenominatorLabel: String
}

public enum BalanceSheetSection: String, Sendable { case assets, liabilitiesAndEquity }

public extension ChartData {
    static func signedBreakdown(from lines: [ReportLine], section: BalanceSheetSection, accountTypes: [String: LedgerAccountType]) -> SignedBreakdown? {
        guard let split = lines.firstIndex(where: { $0.isSummary && ($0.label == "TOTAL ASSETS" || $0.label == "Total Assets") }) else { return nil }
        let slice = section == .assets ? Array(lines[..<split]) : Array(lines[(split + 1)...])
        let reportedTotal: Money? = section == .assets
            ? lines[split].amount
            : lines.first { $0.isSummary && ($0.label == "TOTAL LIABILITIES AND EQUITY" || $0.label == "Total Liabilities and Equity") }?.amount
        let leaves = slice.filter { !$0.isSummary && $0.amount != nil && $0.amount!.minorUnits != 0 }

        let positives = leaves.filter { $0.amount!.minorUnits > 0 }
        let negatives = leaves.filter { $0.amount!.minorUnits < 0 }
        let positiveTotal = positives.reduce(Money.zero) { $0 + $1.amount! }
        let negativeTotal = negatives.reduce(Money.zero) { $0 + $1.amount! }
        let net = positiveTotal + negativeTotal

        let positiveItems = positives
            .sorted { $0.amount!.minorUnits > $1.amount!.minorUnits }
            .map { line -> ChartItem in
                let type = line.accountID.flatMap { accountTypes[$0] }
                return ChartItem(
                    id: line.stableKey, accountID: line.accountID, label: line.label,
                    value: line.amount!.majorUnitsDouble, valueText: line.amount!.accountingDescription,
                    category: positiveCategory(section: section, type: type),
                    share: positiveTotal.minorUnits > 0 ? Double(line.amount!.minorUnits) / Double(positiveTotal.minorUnits) : nil
                )
            }
        let negativeItems = negatives
            .sorted { $0.amount!.minorUnits < $1.amount!.minorUnits }
            .map { line -> ChartItem in
                let kind = negativeKind(section: section, type: line.accountID.flatMap { accountTypes[$0] }, label: line.label)
                return ChartItem(
                    id: line.stableKey, accountID: line.accountID, label: line.label,
                    value: line.amount!.majorUnitsDouble, valueText: line.amount!.accountingDescription,
                    category: kind.category, note: kind.note
                )
            }

        return SignedBreakdown(
            title: section == .assets ? "Assets" : "Liabilities & Equity",
            positiveItems: positiveItems,
            negativeItems: negativeItems,
            positiveSubtotal: positiveTotal.majorUnitsDouble,
            positiveSubtotalText: positiveTotal.accountingDescription,
            negativeSubtotal: negativeTotal.majorUnitsDouble,
            negativeSubtotalText: negativeTotal.accountingDescription,
            net: net.majorUnitsDouble,
            netText: net.accountingDescription,
            reportedTotalText: reportedTotal?.accountingDescription,
            reconciles: reportedTotal.map { abs($0.minorUnits - net.minorUnits) <= 1 } ?? false,
            percentDenominatorLabel: "Slice percentages are shares of positive balances only (\(positiveTotal.accountingDescription))"
        )
    }

    private static func positiveCategory(section: BalanceSheetSection, type: LedgerAccountType?) -> String {
        guard section == .liabilitiesAndEquity else { return "asset" }
        return type == .equity ? "equity" : (type == nil ? "equity" : "liability")
    }

    static func negativeKind(section: BalanceSheetSection, type: LedgerAccountType?, label: String) -> (category: String, note: String) {
        let lower = label.lowercased()
        switch section {
        case .assets:
            if type == .bank { return ("overdraft", "Overdrawn bank account") }
            if type == nil { return ("creditBalance", "Negative balance — sync to identify the account type") }
            if lower.contains("depreciation") || lower.contains("amortization") { return ("contra", "Contra asset — reduces the related asset") }
            return ("creditBalance", "Asset with a credit balance — review for a posting error")
        case .liabilitiesAndEquity:
            if lower == "net income" { return ("netLoss", "Net loss for the year to date") }
            if lower.contains("retained earnings") { return ("deficit", "Accumulated deficit") }
            if lower.contains("draw") || lower.contains("distribution") { return ("draw", "Owner draws / distributions (normally negative)") }
            if type == .equity || lower.contains("equity") { return ("negativeEquity", "Negative equity balance") }
            if let type, type.isAssetOrLiability { return ("debitBalance", "Liability with a debit balance — overpaid or miscoded") }
            return ("negativeEquity", "Negative balance")
        }
    }
}

// MARK: - Revenue-to-net-income waterfall

public struct WaterfallStep: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// total (anchored at zero), decrease, or increase.
    public let kind: String
    public let from: Double
    public let to: Double
    public let valueText: String
}

public struct WaterfallData: Codable, Equatable, Sendable {
    public let steps: [WaterfallStep]
    public let reconciles: Bool
    public let note: String?
}

public extension ChartData {
    /// Revenue from zero, each deduction floating from the running total,
    /// other income/expense when present, net income anchored at zero.
    /// Uses only the section totals QBO reports, so nothing is counted
    /// twice; `reconciles` is false (and says why) if they don't add up.
    static func waterfall(from lines: [ReportLine]) -> WaterfallData? {
        guard let income = summary("Total Income", in: lines), let netIncome = TaxEstimate.netIncome(from: lines) else { return nil }
        var steps: [WaterfallStep] = [WaterfallStep(id: "revenue", label: "Revenue", kind: "total", from: 0, to: income.majorUnitsDouble, valueText: income.accountingDescription)]
        var running = income

        func apply(_ id: String, _ label: String, _ amount: Money?, sign: Int64) {
            guard let amount, amount.minorUnits != 0 else { return }
            let delta = Money(minorUnits: amount.minorUnits * sign, currency: amount.currency)
            let next = running + delta
            let shown = sign < 0 ? Money(minorUnits: -amount.minorUnits, currency: amount.currency) : amount
            steps.append(WaterfallStep(id: id, label: label, kind: delta.minorUnits < 0 ? "decrease" : "increase", from: running.majorUnitsDouble, to: next.majorUnitsDouble, valueText: shown.accountingDescription))
            running = next
        }
        // A reconciliation adjustment is a bookkeeping entry, not spending;
        // it gets its own step so it isn't read as operating cost.
        let adjustment = PerformanceAnalysis.adjustments(lines)
        var operating = summary("Total Expenses", in: lines)
        var other = summary("Total Other Expenses", in: lines)
        if adjustment.minorUnits != 0 {
            if let o = other, o >= adjustment { other = o - adjustment }
            else if let e = operating { operating = e - adjustment }
        }
        apply("cogs", "Cost of Goods Sold", summary("Total Cost of Goods Sold", in: lines), sign: -1)
        apply("expenses", "Operating Expenses", operating, sign: -1)
        apply("other-income", "Other Income", summary("Total Other Income", in: lines), sign: 1)
        apply("other-expenses", "Other Expenses", other, sign: -1)
        apply("adjustment", "Reconciliation Adjustment", adjustment.minorUnits != 0 ? adjustment : nil, sign: -1)

        steps.append(WaterfallStep(id: "net", label: netIncome.minorUnits < 0 ? "Net Loss" : "Net Income", kind: "total", from: 0, to: netIncome.majorUnitsDouble, valueText: netIncome.accountingDescription))
        let reconciles = abs(running.minorUnits - netIncome.minorUnits) <= 1
        return WaterfallData(
            steps: steps,
            reconciles: reconciles,
            note: reconciles ? nil : "The reported sections add to \(running.accountingDescription) but QBO reports net income of \(netIncome.accountingDescription); the difference is not charted."
        )
    }
}

// MARK: - Ranked expense categories

public struct RankedBars: Codable, Equatable, Sendable {
    public let items: [ChartItem]
    /// Every category (for the supporting table), largest first.
    public let allItems: [ChartItem]
    public let totalText: String
    public let reportedTotalText: String?
    public let reconciles: Bool
    public let creditItems: [ChartItem]
}

public extension ChartData {
    /// Operating-expense account lines (between the Gross Profit/Total
    /// Income split and Total Expenses). Beyond `top`, the rest are grouped
    /// into one "Other" bar. Credits (negative expense lines) are listed,
    /// never charted as bars.
    static func expenseCategories(from lines: [ReportLine], top: Int = 8) -> RankedBars? {
        let splitLabel = lines.contains { $0.isSummary && $0.label == "Gross Profit" } ? "Gross Profit" : "Total Income"
        guard let start = lines.firstIndex(where: { $0.isSummary && $0.label == splitLabel }) else { return nil }
        let end = lines[(start + 1)...].firstIndex { $0.isSummary && $0.label == "Total Expenses" } ?? lines.endIndex
        let leaves = lines[(start + 1)..<end].filter { !$0.isSummary && ($0.amount?.minorUnits ?? 0) != 0 }
        let reported = summary("Total Expenses", in: lines)
        let total = leaves.reduce(Money.zero) { $0 + $1.amount! }
        let positiveTotal = leaves.filter { $0.amount!.minorUnits > 0 }.reduce(Money.zero) { $0 + $1.amount! }

        func item(_ line: ReportLine) -> ChartItem {
            ChartItem(id: line.stableKey, accountID: line.accountID, label: line.label, value: line.amount!.majorUnitsDouble,
                      valueText: line.amount!.accountingDescription, category: "expense",
                      share: positiveTotal.minorUnits > 0 && line.amount!.minorUnits > 0 ? Double(line.amount!.minorUnits) / Double(positiveTotal.minorUnits) : nil)
        }
        let ranked = leaves.filter { $0.amount!.minorUnits > 0 }.sorted { $0.amount!.minorUnits > $1.amount!.minorUnits }.map(item)
        var shown = Array(ranked.prefix(top))
        let rest = ranked.dropFirst(top)
        if !rest.isEmpty {
            let restTotal = rest.reduce(Money.zero) { $0 + Money.fromMajor($1.value) }
            shown.append(ChartItem(id: "other", accountID: nil, label: "Other (\(rest.count) categories)", value: restTotal.majorUnitsDouble,
                                   valueText: restTotal.accountingDescription, category: "other",
                                   share: positiveTotal.minorUnits > 0 ? Double(restTotal.minorUnits) / Double(positiveTotal.minorUnits) : nil))
        }
        return RankedBars(
            items: shown,
            allItems: ranked,
            totalText: total.accountingDescription,
            reportedTotalText: reported?.accountingDescription,
            reconciles: reported.map { abs($0.minorUnits - total.minorUnits) <= 1 } ?? false,
            creditItems: leaves.filter { $0.amount!.minorUnits < 0 }.map(item)
        )
    }
}

// MARK: - Monthly trends

public struct TrendPoint: Codable, Equatable, Sendable {
    public let period: String
    public let label: String
    public let revenue: Double?
    public let expenses: Double?
    public let netIncome: Double?
    /// Net income as a percent of revenue; `nil` (never zero) without revenue.
    public var marginPercent: Double?
}

public struct TrendData: Codable, Equatable, Sendable {
    public let points: [TrendPoint]
    public let note: String
}

public extension ChartData {
    /// One point per fetched month. A fetched month with no activity is a
    /// real zero; months before the first activity are dropped (no history
    /// yet), and months never fetched never appear.
    static func trend(from months: [MonthlyReport]) -> TrendData {
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let firstActive = months.firstIndex { !$0.lines.filter { !$0.isSummary && $0.amount != nil }.isEmpty } ?? months.endIndex
        let points = months[firstActive...].map { month -> TrendPoint in
            let lines = month.lines
            let revenue = summary("Total Income", in: lines) ?? .zero
            let costs = (summary("Total Cost of Goods Sold", in: lines) ?? .zero) + (summary("Total Expenses", in: lines) ?? .zero) + (summary("Total Other Expenses", in: lines) ?? .zero)
            let net = TaxEstimate.netIncome(from: lines) ?? .zero
            return TrendPoint(
                period: "\(month.period.year)-\(String(format: "%02d", month.period.month))",
                label: "\(names[month.period.month - 1]) \(month.period.year)",
                revenue: revenue.majorUnitsDouble, expenses: costs.majorUnitsDouble, netIncome: net.majorUnitsDouble,
                marginPercent: revenue.minorUnits > 0 ? (net.majorUnitsDouble / revenue.majorUnitsDouble * 100 * 10).rounded() / 10 : nil
            )
        }
        let dropped = firstActive
        return TrendData(
            points: Array(points),
            note: dropped > 0 ? "\(dropped) earlier month\(dropped == 1 ? "" : "s") with no recorded activity omitted." : "All loaded months shown."
        )
    }
}

public enum ChartData {}
