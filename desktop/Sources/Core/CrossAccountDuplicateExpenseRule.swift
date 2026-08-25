import Foundation

/// `VL-DUP-EXP-002`. docs/phase-0/08_RULE_ENGINE.md §8.8's note ("Q8, owner
/// decision 2026-08"): `VL-DUP-EXP-001` stays scoped to same-payment-account
/// matches on purpose — the cross-account case (paying the same bill from
/// checking, then again from a card) is real but has a different
/// false-positive profile, so it gets its own rule rather than being folded
/// into the slice.
///
/// Single tier, `.medium` confidence at best (per the backlog table) — a
/// same-vendor/same-amount/near-date match across *different* payment
/// accounts is more often a coincidence (recurring vendor, round invoice
/// amount) than `VL-DUP-EXP-001`'s same-account case, so this never reaches
/// `.high`.
public enum CrossAccountDuplicateExpenseRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-DUP-EXP-002"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible duplicate expense — paid from two different accounts",
        category: .duplicateExpense,
        ruleClass: .categorization,
        page: .page3Transactions,
        accountingPrinciple: "Each economic event should be recorded once. Two postings sharing vendor, amount, and a nearby date — even from different payment accounts — are presumptively the same bill paid twice (e.g. once by card, once by check), which overstates expense.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    private static let nearDateWindowDays = 3

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let purchases = input.transactions.filter { $0.entityKind == .purchase }

        var findings: [Finding] = []
        var consideredPairs: Set<Set<String>> = []

        for i in 0..<purchases.count {
            for j in (i + 1)..<purchases.count {
                let a = purchases[i]
                let b = purchases[j]

                if a.isVoided || b.isVoided { continue }
                if context.gatedTransactionIDs.contains(a.id) || context.gatedTransactionIDs.contains(b.id) { continue }

                // Gauntlet Loop hardening applied 2026-08-23, carried over
                // from VL-DUP-EXP-001's own hardening pass (same rule
                // shape, same class of gap found there first): a literal
                // `id` collision is a data-pipeline anomaly, never two
                // distinct real records — `id` is QBO's own primary key.
                guard a.id != b.id else { continue }

                guard let vendorA = a.vendorName, vendorA == b.vendorName else { continue }
                guard a.totalAmount == b.totalAmount else { continue }

                // The defining condition: DIFFERENT payment accounts — same
                // account is VL-DUP-EXP-001's territory, not this rule's.
                guard let acctA = a.paymentAccountID, let acctB = b.paymentAccountID, acctA != acctB else { continue }

                guard AccountingDate.daysBetween(a.txnDate, b.txnDate) <= nearDateWindowDays else { continue }

                // Compare/report on MAGNITUDE, not signed value — carried
                // over from VL-DUP-EXP-001's hardening: a negative-amount
                // Purchase pair (a vendor rebate/correction posted directly
                // as a negative Purchase) would otherwise bypass the
                // materiality floor by sign alone, regardless of size.
                let exposure = a.totalAmount.minorUnits < 0
                    ? Money(minorUnits: -a.totalAmount.minorUnits, currency: a.totalAmount.currency)
                    : a.totalAmount

                guard exposure >= context.materiality.absoluteFloor else { continue }

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

                let severity = Severity.derive(dollarExposure: exposure, materiality: context.materiality)

                // Evidence deliberately does NOT include "paymentAccount" —
                // carried over from VL-DUP-EXP-001's own T2 hardening fix:
                // this rule's own defining condition (above) REQUIRES the
                // two payment accounts to differ, so claiming
                // "paymentAccount" as matched evidence would be an outright
                // false statement, not merely incomplete.
                func fieldValues(for txn: LedgerTransaction) -> [String: String] {
                    ["amount": txn.totalAmount.description, "date": txn.txnDate.formatted, "vendor": vendorA]
                }
                let evidence = [
                    EvidenceItem(transactionID: a.id, highlightedFields: ["amount", "date"], fieldValues: fieldValues(for: a)),
                    EvidenceItem(transactionID: b.id, highlightedFields: ["amount", "date"], fieldValues: fieldValues(for: b))
                ]
                let narrative = "Two purchases from \(vendorA) for \(exposure) were posted \(AccountingDate.daysBetween(a.txnDate, b.txnDate) == 0 ? "on the same day" : "\(AccountingDate.daysBetween(a.txnDate, b.txnDate)) day\(AccountingDate.daysBetween(a.txnDate, b.txnDate) == 1 ? "" : "s") apart"), paid from two different accounts — this could be the same bill paid twice, or a coincidence (recurring vendor, round amount)."
                let riskIfIgnored = "This finding will keep reappearing on every future sync until it's resolved or dismissed. Until then, \(exposure) may be sitting in your books as a duplicate expense across two accounts."

                let procedure = GuidedProcedure(
                    steps: [
                        "Open QuickBooks Online",
                        "Go to Expenses, find the vendor \(vendorA)",
                        "Compare the two postings (\(a.id) and \(b.id)) — they were paid from different accounts",
                        "Check the bank/card statements for both accounts to confirm whether one or two payments actually cleared",
                        "If only one payment actually occurred: void the duplicate Purchase in QBO"
                    ],
                    pitfalls: [
                        "Cross-account matches are more often a coincidence than VL-DUP-EXP-001's same-account case — verify against both statements before voiding anything",
                        "Void, not delete — voiding preserves the audit trail; deleting does not"
                    ],
                    doneCriteria: "Statement evidence confirms one payment; the duplicate Purchase shows as Voided in QBO, TotalAmt $0.00"
                )

                let action = ProposedAction(
                    id: "verify-cross-account-duplicate",
                    title: "Verify against both statements, then void if duplicate",
                    resolution: .manualQBO,
                    guidedProcedure: procedure,
                    consequences: [
                        .reconciliation("removes \(exposure) from uncleared activity on one account, once confirmed and voided in QBO"),
                        .reporting("expenses decrease by \(exposure), once confirmed and voided in QBO"),
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
                    title: "Possible duplicate expense across accounts — \(exposure)",
                    severity: severity,
                    confidence: .medium,
                    dollarExposure: exposure,
                    evidence: evidence,
                    proposedActions: [action],
                    provenance: [a.provenance, b.provenance],
                    // Carried over from VL-DUP-EXP-001's hardening: every
                    // sibling rule with a clear single vendor sets this so
                    // Client Memory's "Always Dismiss for <vendor>" can
                    // actually match a finding from this rule.
                    vendorName: vendorA,
                    narrative: narrative,
                    riskIfIgnored: riskIfIgnored
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
            return .pass(coverage: input.coverage, checkedCount: purchases.count)
        }
        return .findings(findings)
    }
}
