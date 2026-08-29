import Foundation

/// `VL-RELATIONSHIP-005`. docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md's
/// Transaction Relationship Guard, branch 5: "Should it be split —
/// principal/interest/fees, or across categories?" `VL-PAYROLL-LUMP-001`
/// already covers one instance of this exact pattern (a payroll
/// processor's net draw, coded to a single line instead of split into
/// wages/tax/withholding) — this is the same mechanism applied to the
/// OTHER common lump-payment case: a loan or note payment, which bundles
/// principal (a balance sheet movement, reducing the liability) and
/// interest (a real expense) into one bank draw. Kept as a separate rule
/// ID from `VL-PAYROLL-LUMP-001` rather than merged — unlike
/// `VL-VEND-PRICE-001`/`VL-SUB-INCREASE-001` (the exact same fact,
/// same vendor domain), these two target entirely different vendor
/// keyword sets and produce different guided procedures for a
/// bookkeeper, the same "different keyword domain, same mechanism"
/// precedent `AvoidableFeeRule`/`PayrollLumpSumRule`/`PersonalExpenseRule`
/// already established as three separate rules.
///
/// **Cannot compute the correct split — same honest limit
/// `VL-PAYROLL-LUMP-001` documents.** Voice Ledger has no loan
/// amortization schedule; it only detects the pattern and hands off to a
/// human with the specific document (the lender's statement) to go get.
public enum LoanPaymentLumpSumRule: Rule {
    /// Case-insensitive substring match against vendor name AND memo —
    /// same two-field check `AvoidableFeeRule`/`PersonalExpenseRule` use.
    /// Deliberately specific multi-word/unambiguous terms, not a bare word
    /// like "loan" alone, which could match a legitimate vendor name.
    static let loanPaymentKeywords = [
        "loan payment", "loan pmt", "mortgage payment", "note payable payment",
        "auto loan payment", "installment loan", "loan payoff"
    ]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-RELATIONSHIP-005"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Loan payment coded to a single expense line",
        category: .loanPaymentLumpSum,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A loan or note payment bundles two different things into one bank draw: principal (which reduces the loan liability on the balance sheet, not an expense) and interest (a real expense). Coding the whole payment to a single expense line overstates that expense and leaves the loan balance on the books wrong — it never goes down even as real payments are made.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let purchases = input.transactions.filter { $0.entityKind == .purchase && !$0.isVoided }
        var findings: [Finding] = []

        for purchase in purchases {
            let vendorLower = purchase.vendorName?.lowercased() ?? ""
            let memoLower = purchase.memo?.lowercased() ?? ""
            guard loanPaymentKeywords.contains(where: { vendorLower.contains($0) || memoLower.contains($0) }) else { continue }
            guard !context.gatedTransactionIDs.contains(purchase.id) else { continue } // §8.2a gating

            // "Single expense line" — already split means someone already
            // did the principal/interest breakdown.
            guard purchase.lineAccountIDs.count == 1 else { continue }
            guard purchase.totalAmount >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [purchase.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let vendorText = purchase.vendorName.map { " to \($0)" } ?? ""

            let procedure = GuidedProcedure(
                steps: [
                    "Pull the lender's payment statement or amortization schedule for this payment\(vendorText)",
                    "Identify the actual principal and interest amounts from that statement",
                    "Open this transaction in QuickBooks Online (\(purchase.txnDate.year)-\(purchase.txnDate.month)-\(purchase.txnDate.day), \(purchase.totalAmount))",
                    "Split the single line into a principal line (coded to the loan's liability account) and an interest line (coded to interest expense), matching the lender's statement",
                    "Confirm the split lines sum to the original total — the transaction's total dollar amount does not change, only how it's categorized"
                ],
                pitfalls: [
                    "Voice Ledger cannot compute the correct principal/interest split — it has no access to the amortization schedule. Do not guess at amounts.",
                    "The full payment amount is very often NOT the interest expense — treating it as such overstates interest expense and leaves the loan liability balance stale"
                ],
                doneCriteria: "The payment is split across a principal (liability) line and an interest (expense) line matching the lender's statement, not a single lump expense line"
            )

            let action = ProposedAction(
                id: "split-loan-payment-lines",
                title: "Split into principal and interest lines",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("interest expense corrected to the actual amount once split; the loan liability balance becomes accurate as principal is properly applied"),
                    .auditTrail("Voice Ledger records your attestation; the lender's statement is the source of truth for the correct split, not Voice Ledger")
                ],
                reversal: .reversibleManually(procedure: "Recombine into a single line in QBO if done in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Loan payment\(vendorText) coded to a single line — \(purchase.totalAmount)",
                severity: Severity.derive(dollarExposure: purchase.totalAmount, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: purchase.totalAmount,
                evidence: [EvidenceItem(
                    transactionID: purchase.id,
                    highlightedFields: ["vendor", "amount", "date"],
                    fieldValues: [
                        "vendor": purchase.vendorName ?? "unknown",
                        "amount": purchase.totalAmount.description,
                        "date": purchase.txnDate.formatted
                    ]
                )],
                proposedActions: [action],
                provenance: [purchase.provenance],
                vendorName: purchase.vendorName,
                narrative: "A \(purchase.totalAmount) payment\(vendorText) on \(purchase.txnDate.formatted) was coded entirely to one expense line — loan payments bundle principal and interest together, so this single line likely overstates interest expense and leaves the loan balance stale.",
                riskIfIgnored: "Interest expense stays overstated and the loan liability balance stays wrong on the books until this payment is split using the lender's actual statement."
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: purchases.count)
        }
        return .findings(findings)
    }
}
