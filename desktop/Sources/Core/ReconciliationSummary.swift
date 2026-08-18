import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 5 (Reconciliation, Type B+C): "Compares
/// statement lines to ledger; identifies unmatched/duplicates; calculates
/// difference." This is the "calculates difference" piece, computed from
/// `VL-RECON-MISSING-001`'s own already-tested findings rather than
/// re-deriving statement-to-ledger matching a second time — that matching
/// logic lives in `BankFeedMissingPostingRule` and stays there as the one
/// place it's decided (`CLAUDE.md` rule 1: one deterministic answer, not
/// two implementations that could disagree).
public struct ReconciliationSummary: Sendable {
    public let totalStatementLines: Int
    public let matchedCount: Int
    public let unmatchedCount: Int
    /// Sum of the unmatched lines' `dollarExposure` — `nil` when there are
    /// none (matches `Money`'s own "no zero-with-a-currency-guess" posture
    /// elsewhere in this codebase: absence is `nil`, not `$0.00`).
    public let unmatchedTotal: Money?

    public init(totalStatementLines: Int, matchedCount: Int, unmatchedCount: Int, unmatchedTotal: Money?) {
        self.totalStatementLines = totalStatementLines
        self.matchedCount = matchedCount
        self.unmatchedCount = unmatchedCount
        self.unmatchedTotal = unmatchedTotal
    }

    /// `unmatchedFindings` must be `VL-RECON-MISSING-001`'s findings and no
    /// other rule's — this function has no way to check that itself, so
    /// callers own passing the right slice.
    public static func compute(totalStatementLines: Int, unmatchedFindings: [Finding]) -> ReconciliationSummary {
        let unmatchedCount = unmatchedFindings.count
        let matchedCount = max(0, totalStatementLines - unmatchedCount)
        let unmatchedTotal: Money? = unmatchedFindings.isEmpty
            ? nil
            : unmatchedFindings.dropFirst().reduce(unmatchedFindings[0].dollarExposure) { $0 + $1.dollarExposure }
        return ReconciliationSummary(
            totalStatementLines: totalStatementLines,
            matchedCount: matchedCount,
            unmatchedCount: unmatchedCount,
            unmatchedTotal: unmatchedTotal
        )
    }
}
