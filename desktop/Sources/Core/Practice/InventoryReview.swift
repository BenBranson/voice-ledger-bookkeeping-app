import Foundation

/// Inventory checks for clients who carry stock (owner directive
/// 2026-10-02). Deterministic, from data already loaded: cost of goods sold
/// as a share of sales by month, and the books' inventory balance against
/// the client's own physical count. It never adjusts anything.
public struct InventoryReview: Sendable, Equatable {
    public struct MonthRatio: Sendable, Equatable, Identifiable {
        public var id: String { "\(period.year)-\(period.month)" }
        public let period: AccountingPeriod
        public let sales: Money
        public let costOfGoods: Money
        /// Cost of goods ÷ sales × 100.
        public let percent: Double
    }

    public let months: [MonthRatio]
    /// Average of the months before the latest one.
    public let priorAverage: Double?
    public let inventoryBalance: Money?
    public let count: Money?
    public let countDate: AccountingDate?

    public var latest: MonthRatio? { months.last }

    /// The latest month's cost-of-goods share moved more than 5 points from the prior average.
    public var ratioShift: Double? {
        guard let latest, let priorAverage else { return nil }
        return latest.percent - priorAverage
    }
    public var ratioFlag: Bool { abs(ratioShift ?? 0) > 5 }

    /// Books minus count (positive: the books show more than the shelf).
    public var countDifference: Money? {
        guard let inventoryBalance, let count else { return nil }
        return inventoryBalance - count
    }
    public var negativeInventory: Bool { (inventoryBalance?.minorUnits ?? 0) < 0 }
    public var noCostOfGoods: Bool { !months.isEmpty && months.allSatisfy { $0.costOfGoods.minorUnits == 0 } }

    public static func build(monthlyProfitAndLoss: [MonthlyReport], accounts: [LedgerAccount], count: Money?, countDate: AccountingDate?, lastMonths: Int = 6) -> InventoryReview {
        let months = monthlyProfitAndLoss.suffix(lastMonths).compactMap { report -> MonthRatio? in
            guard let sales = amount(["Total Income"], report.lines), sales.minorUnits > 0 else { return nil }
            let cogs = amount(["Total Cost of Goods Sold", "Total Cost of Sales"], report.lines)
                ?? amount(["Gross Profit"], report.lines).map { sales - $0 }
                ?? Money(minorUnits: 0, currency: sales.currency)
            return MonthRatio(period: report.period, sales: sales, costOfGoods: cogs, percent: cogs.majorUnitsDouble / sales.majorUnitsDouble * 100)
        }
        let prior = months.dropLast()
        let avg = prior.isEmpty ? nil : prior.map(\.percent).reduce(0, +) / Double(prior.count)
        let inventoryAccounts = accounts.filter { a in
            a.accountType == .otherCurrentAsset && ((a.accountSubType ?? "").lowercased() == "inventory" || a.name.lowercased().contains("inventory"))
        }
        let balance = inventoryAccounts.isEmpty ? nil : inventoryAccounts.map(\.currentBalance).reduce(Money(minorUnits: 0, currency: .usd), +)
        return InventoryReview(months: Array(months), priorAverage: avg, inventoryBalance: balance, count: count, countDate: countDate)
    }

    static func amount(_ labels: [String], _ lines: [ReportLine]) -> Money? {
        for label in labels {
            if let line = lines.first(where: { $0.isSummary && $0.label.caseInsensitiveCompare(label) == .orderedSame }), let a = line.amount { return a }
        }
        return nil
    }
}
