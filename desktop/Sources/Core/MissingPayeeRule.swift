import Foundation

/// `VL-MISSING-PAYEE-001`. The one rule from the owner's original pasted
/// "goalie" audit-engine spec (2026-08-29) that wasn't already covered by
/// an existing rule — every other category on that list (duplicates, sign
/// integrity, undeposited funds, uncategorized dumping, opening balance
/// equity) already had a real rule here.
///
/// "Expense transactions with dollar amount > $0 where VendorRef is null"
/// — a Purchase with no vendor at all makes it impossible to answer basic
/// questions later ("who did we pay $486 to in July?"), and commonly means
/// the transaction was force-added from the bank feed without picking a
/// payee, the same failure mode `UncategorizedTransactionRule` catches for
/// missing categories.
public enum MissingPayeeRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-MISSING-PAYEE-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Expense with no vendor",
        category: .missingPayee,
        ruleClass: .categorization,
        page: .page3Transactions,
        accountingPrinciple: "Every expense should be traceable to who was paid. A Purchase with no VendorRef can't be matched to a 1099, can't be searched for later by vendor, and often means the transaction was added straight from the bank feed without anyone actually picking a payee.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let candidates = input.transactions.filter { $0.entityKind == .purchase }
        var findings: [Finding] = []

        for txn in candidates {
            guard !txn.isVoided else { continue }
            guard !context.gatedTransactionIDs.contains(txn.id) else { continue }
            // Deliberately EXACTLY nil, not `?.isEmpty ?? true` — a real
            // empty-string vendor name would be a separate, stranger data
            // problem than "no VendorRef was ever set," and this rule
            // should only ever mean the latter, matching the spec's own
            // "VendorRef is null" wording precisely.
            guard txn.vendorName == nil else { continue }
            guard txn.totalAmount.minorUnits > 0 else { continue }
            guard txn.totalAmount >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [txn.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online and find this transaction (\(txn.totalAmount), dated \(txn.txnDate.formatted))",
                    "Determine who was actually paid",
                    "Edit the transaction and set the Payee/Vendor field",
                    "Save the transaction"
                ],
                pitfalls: [
                    "If this recurs often from the same bank feed rule, the rule itself may need a default payee set, not just this one transaction"
                ],
                doneCriteria: "The transaction has a real vendor/payee attached, not blank"
            )

            let action = ProposedAction(
                id: "assign-missing-payee",
                title: "Attach the correct vendor",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("Vendor-level reports (spend by vendor, 1099 totals) become accurate once attached"),
                    .auditTrail("Voice Ledger records your attestation; the vendor assignment itself is QBO's own record")
                ],
                reversal: .reversibleManually(procedure: "The vendor field can be changed again in QBO if attached wrongly")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Expense with no vendor — \(txn.totalAmount)",
                severity: Severity.derive(dollarExposure: txn.totalAmount, materiality: context.materiality),
                confidence: .high,
                dollarExposure: txn.totalAmount,
                evidence: [EvidenceItem(
                    transactionID: txn.id,
                    highlightedFields: ["vendor", "amount", "date"],
                    fieldValues: ["vendor": "(none)", "amount": txn.totalAmount.description, "date": txn.txnDate.formatted]
                )],
                proposedActions: [action],
                provenance: [txn.provenance],
                vendorName: nil,
                narrative: "A \(txn.totalAmount) expense dated \(txn.txnDate.formatted) has no vendor attached — there's no record of who was actually paid.",
                riskIfIgnored: "This \(txn.totalAmount) stays untraceable to a payee — vendor spend reports and 1099 totals will both be understated until it's attached."
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: candidates.count)
        }
        return .findings(findings)
    }
}
