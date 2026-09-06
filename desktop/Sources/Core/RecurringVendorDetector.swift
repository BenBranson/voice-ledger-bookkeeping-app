import Foundation

/// Owner directive (2026-09-06): "recurring-vendor detection" — flagged
/// earlier this session (`VoiceToolDefinitions.swift`'s system prompt) as
/// something this app explicitly did NOT compute. Built now, deterministically,
/// over real `Purchase` history (`QBOSyncClient.fetchPurchases`, the same
/// entity kind and fetch `VL-VEND-PRICE-001` already uses for its own
/// one-prior-period vendor comparison) spanning several trailing months —
/// no AI involvement, no invented pattern. CLAUDE.md rule 1: this only
/// ever reports a vendor as "recurring" when the actual historical
/// interval and amount data support it, using fixed, disclosed
/// tolerances, never a guess.
///
/// **Why `Purchase`, not `Bill`** (accounts payable): a QBO `Purchase` is
/// an already-recorded, already-paid cash/card expense — exactly the shape
/// of a recurring SaaS charge or subscription. `Bill`s (what
/// `fetchAgedPayables` reports on) are unpaid invoices from a vendor on
/// terms — a fundamentally different, non-overlapping cash event. This
/// keeps `RecurringVendorDetector` and `AgingSummary`'s payables figures
/// additive, not double-counting the same real dollar.
public struct RecurringVendor: Identifiable, Sendable, Equatable {
    public let id: String
    public let vendorName: String
    public let occurrenceCount: Int
    public let averageAmount: Money
    public let averageIntervalDays: Double
    public let lastChargeDate: AccountingDate
    public let lastAmount: Money
    public let expectedNextChargeDate: AccountingDate
    /// The most recent charge's amount fell outside this vendor's own
    /// historical tolerance band — the same "your subscription's price
    /// changed" signal `VL-VEND-PRICE-001` already gives for a single
    /// prior-period comparison, but derived from this vendor's own full
    /// history instead.
    public let lastAmountChanged: Bool

    public init(
        vendorName: String,
        occurrenceCount: Int,
        averageAmount: Money,
        averageIntervalDays: Double,
        lastChargeDate: AccountingDate,
        lastAmount: Money,
        expectedNextChargeDate: AccountingDate,
        lastAmountChanged: Bool
    ) {
        self.id = vendorName
        self.vendorName = vendorName
        self.occurrenceCount = occurrenceCount
        self.averageAmount = averageAmount
        self.averageIntervalDays = averageIntervalDays
        self.lastChargeDate = lastChargeDate
        self.lastAmount = lastAmount
        self.expectedNextChargeDate = expectedNextChargeDate
        self.lastAmountChanged = lastAmountChanged
    }
}

public enum RecurringVendorDetector {
    /// Fewer than this many charges from the same vendor isn't a pattern —
    /// it's a coincidence. Three lets a genuinely monthly vendor qualify
    /// after one quarter of history, without calling two unrelated charges
    /// "recurring."
    public static let defaultMinOccurrences = 3
    /// Coefficient of variation (stddev / mean) ceilings below which
    /// intervals/amounts count as "consistent enough" to call recurring —
    /// loose enough to tolerate a weekend-shifted billing date or a small
    /// usage-based fee change, tight enough that genuinely unrelated
    /// one-off purchases from the same vendor don't qualify.
    public static let defaultIntervalTolerance = 0.35
    public static let defaultAmountTolerance = 0.15

    public static func detect(
        from transactions: [LedgerTransaction],
        minOccurrences: Int = defaultMinOccurrences,
        intervalTolerance: Double = defaultIntervalTolerance,
        amountTolerance: Double = defaultAmountTolerance
    ) -> [RecurringVendor] {
        let purchases = transactions.filter { !$0.isVoided && $0.entityKind == .purchase && $0.vendorName != nil }
        let byVendor = Dictionary(grouping: purchases) { $0.vendorName! }

        var results: [RecurringVendor] = []
        for (vendorName, charges) in byVendor {
            let sorted = charges.sorted { $0.txnDate < $1.txnDate }
            guard sorted.count >= minOccurrences else { continue }
            guard let currency = sorted.first?.totalAmount.currency, sorted.allSatisfy({ $0.totalAmount.currency == currency }) else { continue }

            let intervals = zip(sorted, sorted.dropFirst()).map { Double(AccountingDate.daysBetween($0.txnDate, $1.txnDate)) }
            guard let meanInterval = mean(intervals), meanInterval > 0 else { continue }
            guard coefficientOfVariation(intervals, mean: meanInterval) <= intervalTolerance else { continue }

            // The amount BASELINE deliberately excludes the most recent
            // charge: a price increase on charge N shouldn't disqualify
            // the vendor from being "recurring" at all (it just means the
            // price changed) — it should surface as `lastAmountChanged`
            // against the pattern the charges BEFORE it established.
            // `minOccurrences >= 2` guarantees at least one prior charge
            // remains after dropping the last.
            let priorAmounts = sorted.dropLast().map { Double(abs($0.totalAmount.minorUnits)) }
            guard let baselineAmount = mean(priorAmounts), baselineAmount > 0 else { continue }
            guard coefficientOfVariation(priorAmounts, mean: baselineAmount) <= amountTolerance else { continue }

            let last = sorted[sorted.count - 1]
            let lastAmountMagnitude = Double(abs(last.totalAmount.minorUnits))
            let lastAmountChanged = abs(lastAmountMagnitude - baselineAmount) / baselineAmount > amountTolerance

            results.append(RecurringVendor(
                vendorName: vendorName,
                occurrenceCount: sorted.count,
                averageAmount: Money(minorUnits: Int64(baselineAmount.rounded()), currency: currency),
                averageIntervalDays: meanInterval,
                lastChargeDate: last.txnDate,
                lastAmount: last.totalAmount,
                expectedNextChargeDate: last.txnDate.adding(days: Int(meanInterval.rounded())),
                lastAmountChanged: lastAmountChanged
            ))
        }
        return results.sorted { $0.vendorName.localizedCaseInsensitiveCompare($1.vendorName) == .orderedAscending }
    }

    /// A detected recurring vendor whose next expected charge is already
    /// overdue as of `asOf` — the subscription may have lapsed, been
    /// cancelled, or simply not been entered into QBO yet. `graceDays`
    /// avoids flagging a charge that's merely a few days late.
    public static func missingAsOf(_ recurringVendors: [RecurringVendor], asOf: AccountingDate, graceDays: Int = 10) -> [RecurringVendor] {
        recurringVendors.filter { vendor in
            vendor.expectedNextChargeDate < asOf && AccountingDate.daysBetween(vendor.expectedNextChargeDate, asOf) > graceDays
        }
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func coefficientOfVariation(_ values: [Double], mean: Double) -> Double {
        guard mean > 0, !values.isEmpty else { return .infinity }
        let variance = values.reduce(0.0) { $0 + pow($1 - mean, 2) } / Double(values.count)
        return variance.squareRoot() / mean
    }
}
