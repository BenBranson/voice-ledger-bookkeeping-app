import Foundation

/// Owner directive (2026-09-06): "build cash flow forecasting" — flagged
/// earlier this session (`VoiceToolDefinitions.swift`'s system prompt) as
/// something this app explicitly did NOT compute. Built now as a plain,
/// disclosed arithmetic projection over already-real, already-fetched
/// numbers — never a machine-learning guess, never a number this app can't
/// trace back to a specific QBO figure. CLAUDE.md rule 1 applies here as
/// much as anywhere in this codebase: this is a projection assembled from
/// real inputs under stated assumptions, not a prediction this app is
/// claiming special insight into.
///
/// **The model, stated plainly** (also surfaced in the UI disclaimer, not
/// just here): starting from today's real cash balance,
/// - Expected cash IN = the portion of Accounts Receivable whose QBO aging
///   bucket falls inside the horizon (Current → 30 days, +1-30 → 60 days,
///   +31-60/61-90 → 90 days). The 91+ bucket is never counted as expected
///   cash — see `atRiskReceivables` — because a receivable that old has no
///   honest claim to "expected soon."
/// - Expected cash OUT = the equivalent aging-bucket cut of Accounts
///   Payable, same bucket-to-horizon mapping, plus every detected
///   `RecurringVendor` charge (`RecurringVendorDetector`) whose projected
///   next occurrence(s) fall inside the horizon — additive, not
///   double-counted, because a `Purchase` (recurring vendor's own history)
///   and a `Bill` (what AP aging reports on) are different QBO entities
///   representing different cash events (see `RecurringVendorDetector`'s
///   own doc comment).
/// - This does NOT model day-to-day timing within a bucket, seasonal
///   effects, one-time large transactions not yet on the books, or
///   payroll/loan amortization schedules — an honest scope limit, stated
///   in the UI, not hidden.
public struct CashFlowForecastHorizon: Identifiable, Sendable {
    public var id: Int { days }
    public let days: Int
    public let expectedInflow: Money?
    public let expectedOutflow: Money?
    public let projectedEndingCash: Money?

    public init(days: Int, expectedInflow: Money?, expectedOutflow: Money?, projectedEndingCash: Money?) {
        self.days = days
        self.expectedInflow = expectedInflow
        self.expectedOutflow = expectedOutflow
        self.projectedEndingCash = projectedEndingCash
    }
}

public struct CashFlowForecast: Sendable {
    public let startingCash: Money?
    public let horizons: [CashFlowForecastHorizon]
    /// Accounts Receivable 91+ days overdue — excluded from every
    /// horizon's expected inflow. Surfaced separately so a bookkeeper
    /// still sees it, just not counted as money likely to arrive soon.
    public let atRiskReceivables: Money?

    public init(startingCash: Money?, horizons: [CashFlowForecastHorizon], atRiskReceivables: Money?) {
        self.startingCash = startingCash
        self.horizons = horizons
        self.atRiskReceivables = atRiskReceivables
    }
}

public enum CashFlowForecastEngine {
    public static let horizonsInDays = [30, 60, 90]

    public static func compute(
        currentCash: Money?,
        agedReceivablesLines: [AgingLine],
        agedPayablesLines: [AgingLine],
        recurringVendors: [RecurringVendor],
        asOf: AccountingDate
    ) -> CashFlowForecast {
        let receivables = AgingSummary.bucketTotals(agedReceivablesLines)
        let payables = AgingSummary.bucketTotals(agedPayablesLines)

        let horizons = horizonsInDays.map { days -> CashFlowForecastHorizon in
            let inflow = cumulativeBucketAmount(receivables, throughDays: days)
            let outflowFromBills = cumulativeBucketAmount(payables, throughDays: days)
            let outflowFromRecurring = projectedRecurringTotal(recurringVendors, withinDays: days, of: asOf)
            let outflow = sum([outflowFromBills, outflowFromRecurring])

            var projectedEndingCash: Money?
            if let currentCash {
                var runningMinorUnits = currentCash.minorUnits
                var sawAny = false
                if let inflow, inflow.currency == currentCash.currency {
                    runningMinorUnits += inflow.minorUnits
                    sawAny = true
                }
                if let outflow, outflow.currency == currentCash.currency {
                    runningMinorUnits -= outflow.minorUnits
                    sawAny = true
                }
                projectedEndingCash = sawAny ? Money(minorUnits: runningMinorUnits, currency: currentCash.currency) : currentCash
            }

            return CashFlowForecastHorizon(days: days, expectedInflow: inflow, expectedOutflow: outflow, projectedEndingCash: projectedEndingCash)
        }

        return CashFlowForecast(startingCash: currentCash, horizons: horizons, atRiskReceivables: receivables?.days91AndOver)
    }

    /// Sums the aging buckets that fall within `days` of today, per this
    /// file's own doc comment on the bucket-to-horizon mapping. `nil`
    /// input (no aging data loaded) yields `nil`, never a fabricated zero.
    private static func cumulativeBucketAmount(_ buckets: AgingSummary.BucketTotals?, throughDays days: Int) -> Money? {
        guard let buckets else { return nil }
        switch days {
        case ..<31: return buckets.current
        case 31..<61: return sum([buckets.current, buckets.days1to30])
        default: return sum([buckets.current, buckets.days1to30, buckets.days31to60, buckets.days61to90])
        }
    }

    /// Every recurring vendor's projected occurrence(s) within `days` of
    /// `asOf`, starting from that vendor's own `expectedNextChargeDate`
    /// and stepping forward by its own historical average interval — a
    /// vendor billed weekly can occur more than once inside a 30-day
    /// horizon; one billed quarterly may occur zero times inside it.
    private static func projectedRecurringTotal(_ vendors: [RecurringVendor], withinDays days: Int, of asOf: AccountingDate) -> Money? {
        let horizonEnd = asOf.adding(days: days)
        var totalsByCurrency: [CurrencyCode: Int64] = [:]
        for vendor in vendors {
            guard vendor.averageIntervalDays > 0 else { continue }
            var occurrence = vendor.expectedNextChargeDate
            // Capped at 24 projected occurrences per vendor — more than
            // enough for even a daily-billed vendor across a 90-day
            // horizon, and a hard backstop against an infinite loop if a
            // future change ever let `averageIntervalDays` round to 0.
            var guardCount = 0
            while occurrence <= horizonEnd && guardCount < 24 {
                if occurrence >= asOf {
                    totalsByCurrency[vendor.averageAmount.currency, default: 0] += vendor.averageAmount.minorUnits
                }
                occurrence = occurrence.adding(days: max(1, Int(vendor.averageIntervalDays.rounded())))
                guardCount += 1
            }
        }
        // Same-currency guard as every other sum in this app: a mixed-
        // currency result has no single honest total, so this returns the
        // single currency present, or `nil` if the vendor list spans more
        // than one (rare — most books operate in one currency).
        guard totalsByCurrency.count == 1, let (currency, total) = totalsByCurrency.first else { return nil }
        return Money(minorUnits: total, currency: currency)
    }

    private static func sum(_ amounts: [Money?]) -> Money? {
        let present = amounts.compactMap { $0 }
        guard let currency = present.first?.currency, present.allSatisfy({ $0.currency == currency }) else { return nil }
        return Money(minorUnits: present.reduce(0) { $0 + $1.minorUnits }, currency: currency)
    }
}
