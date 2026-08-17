import Foundation

/// `VL-DUP-INV-001`. docs/phase-0/08_RULE_ENGINE.md §8.8 — the sales-side
/// counterpart to `VL-DUP-BILL-001`: the same duplicate-detection question,
/// applied to `Invoice` instead of `Bill`. A duplicate Invoice overstates
/// revenue and accounts receivable, the opposite direction of error from a
/// duplicate expense/bill, so it's tracked as its own category.
///
/// **Same single-tier shape as `VL-DUP-BILL-001`, for the same reason: same
/// customer, same date, same amount — no DocNumber tier (Invoice's
/// DocNumber-uniqueness behavior is unverified, same caveat as Bill), no
/// near-date tier (not added speculatively).**
public enum DuplicateInvoiceRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-DUP-INV-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible duplicate invoice",
        category: .duplicateInvoice,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Two invoices to the same customer, same date, same amount are presumptively the same sale entered twice, which overstates revenue and accounts receivable.",
        sourceDependencies: [SourceDependency(entity: .invoice)]
    )

    public static let requirements = DataRequirements(
        entities: [.invoice],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let invoices = input.transactions.filter { $0.entityKind == .invoice && !$0.isVoided }
        var findings: [Finding] = []
        var consideredPairs: Set<Set<String>> = []

        for i in 0..<invoices.count {
            for j in (i + 1)..<invoices.count {
                let a = invoices[i]
                let b = invoices[j]

                if context.gatedTransactionIDs.contains(a.id) || context.gatedTransactionIDs.contains(b.id) { continue }

                guard let customerA = a.vendorName, customerA == b.vendorName else { continue }
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
                        "Go to Sales > Invoices, find the customer \(customerA)",
                        "Locate the duplicate Invoice (\(b.id))",
                        "Confirm this isn't two genuinely separate invoices that happen to share customer/date/amount",
                        "If it's a true duplicate: void the duplicate Invoice in QBO (if unpaid) — if already paid, this needs more care, see pitfalls"
                    ],
                    pitfalls: [
                        "If the duplicate Invoice has already been paid, voiding it alone leaves an orphaned Payment — check for a linked payment first",
                        "Void, not delete — voiding preserves the audit trail; deleting does not"
                    ],
                    doneCriteria: "Only one Invoice remains for this customer/date/amount combination"
                )

                let action = ProposedAction(
                    id: "void-duplicate-invoice",
                    title: "Void the duplicate Invoice in QBO",
                    resolution: .manualQBO,
                    guidedProcedure: procedure,
                    consequences: [
                        .reporting("revenue and accounts receivable decrease by \(a.totalAmount) once corrected"),
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
                    title: "Possible duplicate invoice — \(a.totalAmount)",
                    severity: Severity.derive(dollarExposure: a.totalAmount, materiality: context.materiality),
                    confidence: .high,
                    dollarExposure: a.totalAmount,
                    evidence: [
                        EvidenceItem(transactionID: a.id, highlightedFields: ["amount", "date", "customer"]),
                        EvidenceItem(transactionID: b.id, highlightedFields: ["amount", "date", "customer"])
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
            return .pass(coverage: input.coverage, checkedCount: invoices.count)
        }
        return .findings(findings)
    }
}
