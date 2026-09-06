import Foundation

/// Owner directive (2026-09-06): "does the dashboard have all the KPIs I
/// need... AR/AP aging" — a deterministic headline figure ("how much is
/// overdue, and what fraction of the total that is") over already-fetched
/// `AgingLine` rows, for the dashboard's AR/AP cards.
///
/// Sums only LEAF rows (`isSummary == false`): per `AgingLine`'s own doc
/// comment, a customer/vendor WITH sub-customers appears as its own
/// `isSummary` subtotal row PLUS its children as separate leaf rows —
/// summing every row would double-count that parent subtotal. This is a
/// structural rule, not a label guess, matching `QBOSyncClient.flattenAging`'s
/// own "detect leaves structurally" reasoning rather than searching for an
/// unverified report-wide "TOTAL" row label.
public enum AgingSummary {
    public struct Result: Sendable {
        public let currentAmount: Money?
        public let overdueAmount: Money?
        public let totalAmount: Money?
        /// `overdueAmount / totalAmount`, as a percentage (0...100). `nil`
        /// when either side is missing or `totalAmount` is zero.
        public let percentOverdue: Double?
    }

    /// Owner directive (2026-09-06): "build cash flow forecasting" — the
    /// forecast's 30/60/90-day horizons map directly onto these bucket
    /// cutoffs (QBO's own aging-bucket definitions are already "days past
    /// due as of today," so this is applying that existing meaning, not
    /// inventing a new one). Broken out from `summarize` below so both it
    /// and `CashFlowForecastEngine` share one leaf-summation
    /// implementation rather than two copies that could drift.
    public struct BucketTotals: Sendable {
        public let current: Money?
        public let days1to30: Money?
        public let days31to60: Money?
        public let days61to90: Money?
        public let days91AndOver: Money?
        public let total: Money?
    }

    public static func bucketTotals(_ lines: [AgingLine]) -> BucketTotals? {
        let leaves = lines.filter { !$0.isSummary }
        guard !leaves.isEmpty else { return nil }
        guard let currency = leaves.compactMap({ $0.total?.currency ?? $0.current?.currency }).first else { return nil }

        func sum(_ amounts: [Money?]) -> Money? {
            var total: Int64 = 0
            var sawAny = false
            for amount in amounts {
                guard let amount, amount.currency == currency else { continue }
                total += amount.minorUnits
                sawAny = true
            }
            return sawAny ? Money(minorUnits: total, currency: currency) : nil
        }

        return BucketTotals(
            current: sum(leaves.map(\.current)),
            days1to30: sum(leaves.map(\.days1to30)),
            days31to60: sum(leaves.map(\.days31to60)),
            days61to90: sum(leaves.map(\.days61to90)),
            days91AndOver: sum(leaves.map(\.days91AndOver)),
            total: sum(leaves.map(\.total))
        )
    }

    public static func summarize(_ lines: [AgingLine]) -> Result? {
        guard let buckets = bucketTotals(lines) else { return nil }
        let currency = buckets.total?.currency ?? buckets.current?.currency

        func sum(_ amounts: [Money?]) -> Money? {
            guard let currency else { return nil }
            var total: Int64 = 0
            var sawAny = false
            for amount in amounts {
                guard let amount, amount.currency == currency else { continue }
                total += amount.minorUnits
                sawAny = true
            }
            return sawAny ? Money(minorUnits: total, currency: currency) : nil
        }

        let overdue = sum([buckets.days1to30, buckets.days31to60, buckets.days61to90, buckets.days91AndOver])

        var percentOverdue: Double?
        if let overdue, let total = buckets.total, total.minorUnits != 0 {
            percentOverdue = Double(overdue.minorUnits) / Double(total.minorUnits) * 100
        }

        return Result(currentAmount: buckets.current, overdueAmount: overdue, totalAmount: buckets.total, percentOverdue: percentOverdue)
    }

    /// Days Sales/Payable Outstanding — a standard estimate: `(balance /
    /// period amount) * days in period`. Deliberately labeled "approx."
    /// everywhere it's shown: it uses TOTAL revenue/expense as a stand-in
    /// for "credit sales"/"credit purchases" specifically, since QBO's API
    /// doesn't expose that split separately — an honest approximation, not
    /// a claim of precision the underlying data can't support.
    public static func daysOutstanding(balance: Money?, periodAmount: Money?, daysInPeriod: Int) -> Double? {
        guard let balance, let periodAmount, periodAmount.currency == balance.currency, periodAmount.minorUnits != 0 else { return nil }
        return Double(balance.minorUnits) / Double(periodAmount.minorUnits) * Double(daysInPeriod)
    }
}
