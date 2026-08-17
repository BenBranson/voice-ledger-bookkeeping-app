import Foundation

/// `VL-DUP-BILL-001`. docs/phase-0/08_RULE_ENGINE.md §8.8 — the same
/// duplicate-detection question as `VL-DUP-EXP-001`, applied to `Bill`
/// instead of `Purchase`. Kept as a separate rule rather than folding into
/// `VL-DUP-EXP-001`: a `Bill` is an unpaid liability, not a posted cash
/// expense, so the accounting significance and the reserved ID are both
/// deliberately distinct (§8.8).
///
/// **Deliberately narrower than `VL-DUP-EXP-001`'s three tiers.** Only one
/// match rule here: same vendor, same date, same amount. No T2 (DocNumber)
/// tier — whether QBO enforces DocNumber uniqueness for `Bill` the way it
/// does for `Purchase` (§11.2's verified finding) has not been checked, so
/// no tier is built on that unverified assumption. No T3 (near-date) tier
/// either — added only once there's a real reason to believe bills need it,
/// rather than copying `VL-DUP-EXP-001`'s shape by default.
public enum DuplicateBillRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-DUP-BILL-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible duplicate bill",
        category: .duplicateExpense,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Two bills from the same vendor, same date, same amount are presumptively the same liability entered twice, which overstates accounts payable and, if both are paid, overstates expense.",
        sourceDependencies: [SourceDependency(entity: .bill)]
    )

    public static let requirements = DataRequirements(
        entities: [.bill],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let bills = input.transactions.filter { $0.entityKind == .bill && !$0.isVoided }
        var findings: [Finding] = []
        var consideredPairs: Set<Set<String>> = []

        for i in 0..<bills.count {
            for j in (i + 1)..<bills.count {
                let a = bills[i]
                let b = bills[j]

                if context.gatedTransactionIDs.contains(a.id) || context.gatedTransactionIDs.contains(b.id) { continue }

                guard let vendorA = a.vendorName, vendorA == b.vendorName else { continue }
                guard a.totalAmount == b.totalAmount else { continue }
                guard a.txnDate == b.txnDate else { continue }
                guard a.totalAmount >= context.materiality.absoluteFloor else { continue }

                let pairKey: Set<String> = [a.id, b.id]
                guard !consideredPairs.contains(pairKey) else { continue }
                consideredPairs.insert(pairKey)

                let sortedIDs = [a.id, b.id].sorted()
                let findingID = FindingIDGenerator.makeID(
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    sortedAffectedIDs: sortedIDs
                )
                if context.dismissedFindingIDs.contains(findingID) { continue }

                let procedure = GuidedProcedure(
                    steps: [
                        "Open QuickBooks Online",
                        "Go to Expenses, find the vendor \(vendorA)",
                        "Locate the duplicate Bill (\(b.id))",
                        "Confirm this isn't two genuinely separate bills that happen to share vendor/date/amount",
                        "If it's a true duplicate: void the duplicate Bill in QBO (if unpaid) — if already paid, this needs more care, see pitfalls"
                    ],
                    pitfalls: [
                        "If the duplicate Bill has already been paid, voiding it alone leaves an orphaned BillPayment — check for a linked payment first",
                        "Void, not delete — voiding preserves the audit trail; deleting does not"
                    ],
                    doneCriteria: "Only one Bill remains for this vendor/date/amount combination"
                )

                let action = ProposedAction(
                    id: "void-duplicate-bill",
                    title: "Void the duplicate Bill in QBO",
                    resolution: .manualQBO,
                    guidedProcedure: procedure,
                    consequences: [
                        .reporting("accounts payable and, if both were paid, expense decrease by \(a.totalAmount) once corrected"),
                        .auditTrail("Voice Ledger records your attestation; QBO's own record of the void is authoritative")
                    ],
                    reversal: .reversibleManually(procedure: "Un-void in QBO if done in error")
                )

                findings.append(Finding(
                    id: findingID,
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    title: "Possible duplicate bill — \(a.totalAmount)",
                    severity: Severity.derive(dollarExposure: a.totalAmount, materiality: context.materiality),
                    confidence: .high,
                    dollarExposure: a.totalAmount,
                    evidence: [
                        EvidenceItem(transactionID: a.id, highlightedFields: ["amount", "date", "vendor"]),
                        EvidenceItem(transactionID: b.id, highlightedFields: ["amount", "date", "vendor"])
                    ],
                    proposedActions: [action],
                    provenance: [a.provenance, b.provenance]
                ))
            }
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: bills.count)
        }
        return .findings(findings)
    }
}
