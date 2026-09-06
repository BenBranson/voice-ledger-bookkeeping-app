import Foundation

/// The top N vendors by total spend, from whatever `LedgerTransaction`s are
/// actually in memory — added 2026-09-06 for `VoiceToolLoop`'s
/// `list_vendors_by_spend` tool ("who are this client's top five vendors by
/// spend").
///
/// **Honest scope, deliberately**: `AppState.transactions` holds exactly
/// ONE synced accounting period at a time (see that property's own doc
/// comment) — there is no persisted multi-month transaction ledger
/// anywhere in this app today. A question like "top vendors this YEAR"
/// cannot be answered from real data without a new persistence layer this
/// function does not have; it computes strictly over whatever transactions
/// are passed in; and it is the CALLER's job (`VoiceToolLoop`) to state the
/// real scope ("this period," not "this year") rather than let silence
/// imply a broader answer than what was actually computed — CLAUDE.md
/// rule 5's "green means verified" applies here as much as to any UI
/// status pill.
public enum VendorSpendSummary {
    public struct VendorTotal: Identifiable, Sendable, Equatable {
        public let id: String
        public let vendorName: String
        public let total: Money
        public let transactionCount: Int

        public init(vendorName: String, total: Money, transactionCount: Int) {
            self.id = vendorName
            self.vendorName = vendorName
            self.total = total
            self.transactionCount = transactionCount
        }
    }

    /// Voided transactions are excluded (not real spend); transactions
    /// with no `vendorName` are excluded (nothing to group them under —
    /// counting them under a fabricated "Unknown" bucket would overstate
    /// confidence in a number that isn't really about any one vendor).
    /// Same-currency guarded like every other sum in this codebase —
    /// mixed-currency transactions are dropped from the total for a
    /// vendor whose transactions span more than one currency, rather than
    /// silently summed together.
    public static func top(_ count: Int, from transactions: [LedgerTransaction]) -> [VendorTotal] {
        var totals: [String: [Money]] = [:]
        for transaction in transactions where !transaction.isVoided {
            guard let vendorName = transaction.vendorName, !vendorName.isEmpty else { continue }
            totals[vendorName, default: []].append(transaction.totalAmount)
        }

        return totals.compactMap { vendorName, amounts -> VendorTotal? in
            guard let first = amounts.first, amounts.allSatisfy({ $0.currency == first.currency }) else { return nil }
            let sum = amounts.dropFirst().reduce(first) { $0 + $1 }
            return VendorTotal(vendorName: vendorName, total: sum, transactionCount: amounts.count)
        }
        .sorted { abs($0.total.minorUnits) > abs($1.total.minorUnits) }
        .prefix(count)
        .map { $0 }
    }
}
