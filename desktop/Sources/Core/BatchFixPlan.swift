import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 7 (Batch Fixes, Type A), scoped-down
/// slice: **only the one write operation this app has ever had — Purchase
/// line `AccountRef` reclassification (`updatePurchaseLineAccount`,
/// `VL-CC-PAYMENT-001`'s structural-match findings) — applied to several
/// findings in sequence rather than one at a time.** Spec's fuller list
/// (`ClassRef`, `DepartmentRef`, vendor, other line detail) is NOT built —
/// each of those would be a genuinely new, unverified write operation, and
/// CLAUDE.md's working style is to verify a capability against a live
/// sandbox before designing around it, not extend a write path on
/// documentation alone. "Supported entities" here honestly means the one
/// entity/field this app has ever written to and round-trip-verified.
///
/// **No new write logic exists for this.** `AppState.applyBatchFix` calls
/// the SAME already-hardened `applyStagedFix` once per selected finding,
/// sequentially — the same round-trip verification, Activity Log entries,
/// and per-finding in-flight/error tracking `FindingDetailView`'s single-
/// finding "Apply Fix" already uses. One implementation, not two that
/// could disagree (`CLAUDE.md` rule 1).
///
/// **Investigated for extension 2026-08-28, found no safe candidate.**
/// `VL-CC-PAYMENT-001` only offers `.stagedAPI` on its STRUCTURAL match
/// tier (`isStructuralMatch`) — its keyword-only tier stays `.manualQBO`,
/// deliberately, because a batch-approved automatic write needs real
/// certainty, not a pattern guess. Every rule built after it
/// (`VL-CAT-MISCODE-001`, `VL-VEND-PRICE-001`, `VL-VEND-ANOMALY-001`,
/// etc.) is `.medium` confidence BY DESIGN — each one's own doc comment
/// documents a real, legitimate exception a batch fix could wrongly
/// "correct." Offering `.stagedAPI` on any of them would break the exact
/// discipline `VL-CC-PAYMENT-001` established. The genuinely different
/// candidate (`VL-RELATIONSHIP-003`'s "delete this Purchase, re-enter as
/// a Transfer") isn't a line-reclassification at all — it would need a
/// brand-new delete-capable write path, a materially higher-stakes
/// capability than anything built so far, live-verified against sandbox
/// before being designed around, not attempted opportunistically here.
public struct BatchFixItem: Identifiable, Sendable {
    public let id: String
    public let findingID: String
    public let findingTitle: String
    public let dollarExposure: Money
    public let currentAccountName: String
    public let suggestedAccountName: String
    public let consequences: [Consequence]
    public let reversal: ReversalPlan

    public init(findingID: String, findingTitle: String, dollarExposure: Money, currentAccountName: String, suggestedAccountName: String, consequences: [Consequence], reversal: ReversalPlan) {
        self.id = findingID
        self.findingID = findingID
        self.findingTitle = findingTitle
        self.dollarExposure = dollarExposure
        self.currentAccountName = currentAccountName
        self.suggestedAccountName = suggestedAccountName
        self.consequences = consequences
        self.reversal = reversal
    }
}

public enum BatchFixPlan {
    /// Only findings with a real, unambiguous `apiWriteDetails` (the same
    /// gate `FindingDetailView`'s single "Apply Fix" button already
    /// requires) are eligible — a finding whose only path is a guided
    /// manual procedure never appears here, same as it never gets an
    /// "Apply Fix" button on its own detail page.
    public static func preview(findings: [Finding]) -> [BatchFixItem] {
        findings.compactMap { finding in
            guard let action = finding.proposedActions.first, let details = action.apiWriteDetails else { return nil }
            return BatchFixItem(
                findingID: finding.id,
                findingTitle: finding.title,
                dollarExposure: finding.dollarExposure,
                currentAccountName: details.currentAccountName,
                suggestedAccountName: details.suggestedAccountName,
                consequences: action.consequences,
                reversal: action.reversal
            )
        }
    }

    /// `nil` when `items` is empty — same "no zero-with-a-currency-guess"
    /// posture `ReconciliationSummary`/`VarianceAnalysis` already use.
    public static func totalExposure(_ items: [BatchFixItem]) -> Money? {
        guard let first = items.first else { return nil }
        return items.dropFirst().reduce(first.dollarExposure) { $0 + $1.dollarExposure }
    }
}
