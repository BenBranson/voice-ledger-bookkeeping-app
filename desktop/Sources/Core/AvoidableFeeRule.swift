import Foundation

/// `VL-FEE-AVOIDABLE-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Late fees, overdrafts, avoidable interest." Same keyword-matching
/// pattern as `PayrollLumpSumRule` — checks the vendor name AND the memo
/// (both already synced on every `LedgerTransaction`, no new capability
/// needed) for known fee-related terms, case-insensitive.
///
/// **No live positive example exists in this sandbox** (checked against
/// the real July data this was built against — none of the 24 synced
/// transactions carry a fee-shaped vendor name or memo). Shipped on unit
/// tests alone, same honest posture already used elsewhere in this
/// project when a rule is correct by construction but the sandbox has
/// never produced a live example to fire it against (e.g.
/// `VL-COA-DUPACCT-001`'s note, though that one was left unbuilt for a
/// different reason — false-positive risk, not absence of a live case;
/// this rule's keyword list has no equivalent false-positive risk since
/// "overdraft"/"nsf"/"late fee" are not legitimate business vendor names).
public enum AvoidableFeeRule: Rule {
    /// Lowercase substrings checked against vendor name and memo. Deliberately
    /// narrow and specific — general words like "fee" alone are too broad
    /// (a legitimate "Filing Fee" or "Service Fee" from a real vendor would
    /// false-positive), so every entry here names a SPECIFIC avoidable-fee
    /// concept, not just the word "fee".
    static let feeKeywords: [String] = [
        "late fee", "overdraft", "nsf", "insufficient funds",
        "returned item", "finance charge", "interest charge", "penalty fee"
    ]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-FEE-AVOIDABLE-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible avoidable fee (late fee, overdraft, or finance charge)",
        category: .avoidableFee,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Late fees, overdraft charges, and finance charges are avoidable costs, not the cost of doing business — flagging them (rather than letting them blend into a generic 'Bank Charges' total) gives the owner a chance to negotiate a waiver, fix whatever process caused it (a bill paid late, an account that ran low), or renegotiate terms.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        var findings: [Finding] = []

        for transaction in input.transactions.sorted(by: { $0.id < $1.id }) {
            guard !transaction.isVoided else { continue }
            let haystack = [transaction.vendorName, transaction.noteText]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            guard feeKeywords.contains(where: { haystack.contains($0) }) else { continue }
            guard transaction.totalAmount >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [transaction.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let procedure = GuidedProcedure(
                steps: [
                    "Open the transaction in QuickBooks Online and confirm it's actually a late fee, overdraft charge, or finance charge",
                    "Contact the bank or vendor to ask about a one-time courtesy waiver, especially if this is a first occurrence",
                    "If it's a recurring pattern, identify the root cause (a bill scheduled too late, a low account balance) and fix that instead of just paying the fee each time",
                    "If the fee is legitimate and unavoidable, no further action is needed — this is informational"
                ],
                pitfalls: [
                    "Some 'fee' line items are legitimate business costs (e.g. a real filing fee from a government agency) — confirm the actual cause before assuming it's avoidable"
                ],
                doneCriteria: "The fee has been reviewed, and either waived/refunded, or its root cause addressed to prevent recurrence"
            )

            let action = ProposedAction(
                id: "review-avoidable-fee",
                title: "Review this fee for a possible waiver or root-cause fix",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("\(transaction.totalAmount) is currently recorded as an ordinary expense rather than flagged as an avoidable cost")
                ],
                reversal: .reversibleManually(procedure: "Dispute or request a waiver from the bank/vendor; if granted, record the refund/credit when it posts")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Possible avoidable fee — \(transaction.vendorName ?? "unknown vendor"), \(transaction.totalAmount)",
                severity: Severity.derive(dollarExposure: transaction.totalAmount, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: transaction.totalAmount,
                evidence: [EvidenceItem(
                    transactionID: transaction.id,
                    highlightedFields: ["vendorName", "memo"],
                    fieldValues: [
                        "vendorName": transaction.vendorName ?? "unknown",
                        "memo": transaction.noteText,
                        "amount": transaction.totalAmount.description,
                        "date": transaction.txnDate.formatted
                    ]
                )],
                proposedActions: [action],
                provenance: [transaction.provenance],
                vendorName: transaction.vendorName,
                narrative: "A \(transaction.totalAmount) charge\(transaction.vendorName.map { " from \($0)" } ?? "") on \(transaction.txnDate.formatted) looks like a late fee, overdraft, or finance charge based on its vendor name or memo.",
                riskIfIgnored: "This \(transaction.totalAmount) stays blended into ordinary expenses rather than flagged as an avoidable cost worth disputing or fixing at the source."
            ))
        }

        guard findings.isEmpty else {
            return .findings(findings)
        }
        guard case .complete = input.coverage else {
            return .cannotEvaluate(.partialCoverage(reason: {
                if case .partial(let reason) = input.coverage { return reason }
                return "unknown"
            }()))
        }
        return .pass(coverage: input.coverage, checkedCount: input.transactions.count)
    }
}
