import Foundation

/// `VL-DUP-PAY-001`. docs/phase-0/08_RULE_ENGINE.md §8.8 — the customer-
/// payment counterpart to `VL-DUP-INV-001`. A duplicate `Payment` record
/// (not the same thing as a duplicate deposit — this only detects two
/// `Payment` entities, not whether both were actually deposited) overstates
/// cash received and understates the customer's open balance, the opposite
/// direction of error from a duplicate Purchase/Bill.
///
/// **Same single-tier shape as `VL-DUP-INV-001`/`VL-DUP-BILL-001`, for the
/// same reason: same customer, same date, same amount — no reference-number
/// tier (Payment has no `DocNumber` field the way Purchase/Bill/Invoice do),
/// no near-date tier (not added speculatively).**
public enum DuplicatePaymentRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-DUP-PAY-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible duplicate payment",
        category: .duplicatePayment,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Two Payment records from the same customer, same date, same amount are presumptively the same payment entered twice, which overstates cash received and understates the customer's actual open balance.",
        sourceDependencies: [SourceDependency(entity: .payment)]
    )

    public static let requirements = DataRequirements(
        entities: [.payment],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let payments = input.transactions.filter { $0.entityKind == .payment && !$0.isVoided }
        var findings: [Finding] = []
        var consideredPairs: Set<Set<String>> = []

        for i in 0..<payments.count {
            for j in (i + 1)..<payments.count {
                let a = payments[i]
                let b = payments[j]

                if context.gatedTransactionIDs.contains(a.id) || context.gatedTransactionIDs.contains(b.id) { continue }
                guard a.id != b.id else { continue }

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
                        "Go to Sales > Customers, find \(customerA)",
                        "Locate the duplicate Payment (\(b.id))",
                        "Confirm this isn't two genuinely separate payments that happen to share customer/date/amount",
                        "Confirm with the bank deposit records whether one or two payments actually cleared",
                        "If it's a true duplicate: delete or void the duplicate Payment in QBO, per pitfalls"
                    ],
                    pitfalls: [
                        "If the duplicate Payment has already been deposited (linked to a Deposit), removing it needs more care — check for a linked Deposit first",
                        "Payment doesn't behave like Purchase/Bill for voiding — confirm the correct removal method in QBO before acting"
                    ],
                    doneCriteria: "Only one Payment remains for this customer/date/amount combination, and bank deposit records confirm only one payment actually cleared"
                )

                let action = ProposedAction(
                    id: "verify-duplicate-payment",
                    title: "Verify against deposit records, then correct the duplicate in QBO",
                    resolution: .manualQBO,
                    guidedProcedure: procedure,
                    consequences: [
                        .reconciliation("removes \(a.totalAmount) from uncleared/undeposited activity once confirmed and corrected in QBO"),
                        .reporting("cash received and the customer's open balance become accurate once corrected"),
                        .auditTrail("Voice Ledger records your attestation; QBO's own record of the correction is authoritative")
                    ],
                    reversal: .reversibleManually(procedure: "Any correction can itself be reversed in QBO if done in error")
                )

                findings.append(Finding(
                    id: findingID,
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    title: "Possible duplicate payment — \(a.totalAmount)",
                    severity: Severity.derive(dollarExposure: a.totalAmount, materiality: context.materiality),
                    confidence: .medium, // no reference-number tier and no verified void signal for Payment — one notch below VL-DUP-INV-001/VL-DUP-BILL-001's .high
                    dollarExposure: a.totalAmount,
                    evidence: [
                        EvidenceItem(transactionID: a.id, highlightedFields: ["amount", "date", "customer"], fieldValues: ["amount": a.totalAmount.description, "date": a.txnDate.formatted, "customer": customerA]),
                        EvidenceItem(transactionID: b.id, highlightedFields: ["amount", "date", "customer"], fieldValues: ["amount": b.totalAmount.description, "date": b.txnDate.formatted, "customer": customerA])
                    ],
                    proposedActions: [action],
                    provenance: [a.provenance, b.provenance],
                    vendorName: customerA,
                    narrative: "Two payments from \(customerA) for \(a.totalAmount) were both dated \(a.txnDate.formatted) — check deposit records to confirm whether this is the same payment recorded twice.",
                    riskIfIgnored: "Cash received stays overstated and \(customerA)'s open balance stays understated by \(a.totalAmount) until this is verified against deposit records."
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
            return .pass(coverage: input.coverage, checkedCount: payments.count)
        }
        return .findings(findings)
    }
}
