import Foundation

/// Assets vs. Liabilities & Equity breakdown for the Balance Sheet donut
/// charts — pure, deterministic, no I/O. Relies on the same real, verified
/// QBO Balance Sheet shape `ReportLine`'s own doc comment describes
/// (`ASSETS > Current Assets > Bank Accounts > Checking`) and `isSummary`'s
/// meaning ("true for a section's own total row"): every subtotal along
/// that chain (e.g. "Total Current Assets") is itself `isSummary`, so
/// filtering to `!isSummary` lines already excludes subtotals and keeps
/// only real leaf account amounts — no double-counting a parent total
/// alongside its own children.
public enum BalanceSheetBreakdown {
    public struct Slice: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let amount: Money

        public init(label: String, amount: Money) {
            self.id = label
            self.label = label
            self.amount = amount
        }
    }

    /// `nil` if neither label is found — the split point between the
    /// Assets section and the Liabilities & Equity section that follows it
    /// in QBO's own report ordering. Same "return nil, never guess" posture
    /// as `FinancialKPIs`. Live-verified 2026-08-29 against this app's real
    /// sandbox company: the grand total here renders as "TOTAL ASSETS"
    /// (all caps) — a different casing than the section subtotals like
    /// "Total Current Assets," which is why this tries both rather than
    /// trusting the same casing convention throughout.
    private static func totalAssetsIndex(in lines: [ReportLine]) -> Int? {
        lines.firstIndex(where: { $0.isSummary && ($0.label == "TOTAL ASSETS" || $0.label == "Total Assets") })
    }

    public static func assetSlices(from lines: [ReportLine]) -> [Slice] {
        guard let splitIndex = totalAssetsIndex(in: lines) else { return [] }
        return lines[..<splitIndex].compactMap { line in
            guard !line.isSummary, let amount = line.amount, amount.minorUnits != 0 else { return nil }
            return Slice(label: line.label, amount: amount)
        }
    }

    public static func liabilitiesAndEquitySlices(from lines: [ReportLine]) -> [Slice] {
        guard let splitIndex = totalAssetsIndex(in: lines) else { return [] }
        return lines[(splitIndex + 1)...].compactMap { line in
            guard !line.isSummary, let amount = line.amount, amount.minorUnits != 0 else { return nil }
            return Slice(label: line.label, amount: amount)
        }
    }
}
