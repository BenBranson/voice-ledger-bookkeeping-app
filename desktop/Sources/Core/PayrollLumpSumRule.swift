import Foundation

/// `VL-PAYROLL-LUMP-001`. docs/backlog/CLEANUP_MODE.md §2.2: a payment to a
/// known payroll processor, coded entirely to a single expense line. The net
/// bank draw from a payroll processor is not the payroll expense — it
/// should split into wages, employer taxes, and withholdings, and the real
/// payroll amount can be materially different from the net draw.
///
/// **This rule cannot compute the correct split — that needs the payroll
/// register, which Voice Ledger doesn't have (no import path built yet,
/// §9).** It only detects the pattern and hands off to a human with the
/// specific document to go get. This is deliberately narrower than solving
/// the problem; it's the honest scope of what's detectable from QBO data
/// alone.
public enum PayrollLumpSumRule: Rule {
    /// Case-insensitive substring match. Not exhaustive — same caveat as
    /// `CreditCardPaymentMiscodedRule`'s keyword list.
    static let payrollProcessorKeywords = [
        "adp", "gusto", "paychex", "rippling", "quickbooks payroll",
        "intuit payroll", "justworks", "trinet"
    ]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-PAYROLL-LUMP-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Payroll processor payment coded to a single expense line",
        category: .payrollLumpSum,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A payroll processor's net bank draw bundles wages, employer taxes, and withholdings into one number. Coding the whole draw to a single wages expense line overstates wages and omits employer tax expense and withholding liabilities entirely.",
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
            guard let vendor = purchase.vendorName, !vendor.isEmpty else { continue }
            let vendorLower = vendor.lowercased()
            guard payrollProcessorKeywords.contains(where: { vendorLower.contains($0) }) else { continue }
            guard !context.gatedTransactionIDs.contains(purchase.id) else { continue } // §8.2a gating

            // "Single expense line" — the pattern this rule targets. A
            // payroll payment already split across multiple lines isn't
            // this error (someone already did the split).
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

            let procedure = GuidedProcedure(
                steps: [
                    "Pull the payroll register or summary report from \(vendor)'s dashboard for this pay period",
                    "Identify the actual wages, employer tax, and withholding amounts from that register",
                    "Open this transaction in QuickBooks Online (\(vendor), \(purchase.txnDate.year)-\(purchase.txnDate.month)-\(purchase.txnDate.day), \(purchase.totalAmount))",
                    "Split the single line into separate lines for wages, employer taxes, and withholding liabilities, matching the payroll register",
                    "Confirm the split lines sum to the original total — this transaction's total dollar amount does not change, only how it's categorized"
                ],
                pitfalls: [
                    "Voice Ledger cannot compute the correct split — it has no access to the payroll register. Do not guess at amounts.",
                    "The net draw amount is very often NOT the actual wages expense — treating it as such overstates wages and omits tax/withholding entries entirely"
                ],
                doneCriteria: "The payment is split across wages, employer tax, and withholding lines matching the payroll register, not a single lump line"
            )

            let action = ProposedAction(
                id: "split-payroll-lines",
                title: "Split into wages, employer tax, and withholding lines",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("wages expense corrected to the actual amount once split; employer tax expense and withholding liabilities become visible for the first time"),
                    .auditTrail("Voice Ledger records your attestation; the payroll register is the source of truth for the correct split, not Voice Ledger")
                ],
                reversal: .reversibleManually(procedure: "Recombine into a single line in QBO if done in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Payroll payment to \(vendor) coded to a single line — \(purchase.totalAmount)",
                severity: Severity.derive(dollarExposure: purchase.totalAmount, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: purchase.totalAmount,
                evidence: [EvidenceItem(transactionID: purchase.id, highlightedFields: ["vendor", "lineAccount"])],
                proposedActions: [action],
                provenance: [purchase.provenance]
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
