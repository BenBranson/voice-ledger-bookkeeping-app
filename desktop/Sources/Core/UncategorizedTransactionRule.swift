import Foundation

/// `VL-CAT-UNCAT-001`. docs/phase-0/08_RULE_ENGINE.md §8.8 (page 3).
///
/// QBO auto-creates three catch-all accounts in every company —
/// "Uncategorized Expense", "Uncategorized Income", "Uncategorized Asset" —
/// used as the fallback destination when a bank-feed transaction is added
/// without picking a real category. A posting still sitting in one of these
/// at period end means it was never actually categorized. Live-confirmed
/// present in this sandbox (Ids 31/30/32, `AccountSubType`s
/// `OtherMiscellaneousServiceCost` / `ServiceFeeIncome` / `OtherCurrentAssets`
/// — none of those subtypes is exclusive to this purpose the way
/// `OpeningBalanceEquity` is for `VL-OBE-BALANCE-001`, so this rule matches
/// on the account's exact `Name` instead. That's QBO's own reserved system
/// account name, not user-entered data, so an exact match here doesn't carry
/// `VL-COA-DUPACCT-001`'s false-positive risk (which was about fuzzy-matching
/// user-chosen names).
public enum UncategorizedTransactionRule: Rule {
    /// The exact set of QBO's default catch-all account names this rule
    /// matches against. Deliberately exact, not substring/fuzzy.
    static let uncategorizedAccountNames: Set<String> = [
        "Uncategorized Expense",
        "Uncategorized Income",
        "Uncategorized Asset"
    ]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-CAT-UNCAT-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Uncategorized transaction",
        category: .uncategorizedTransaction,
        ruleClass: .categorization,
        page: .page3Transactions,
        accountingPrinciple: "A transaction posted to QBO's default Uncategorized Expense/Income/Asset account was never assigned a real category. It's included in cash totals but not in any meaningful expense or income breakdown, which understates the accuracy of the P&L until it's recategorized.",
        sourceDependencies: [SourceDependency(entity: .purchase), SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase, .account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let uncategorizedAccountIDs = Set(
            input.accounts.filter { uncategorizedAccountNames.contains($0.name) }.map(\.id)
        )

        let candidates = input.transactions.filter { $0.entityKind == .purchase || $0.entityKind == .bill }
        var findings: [Finding] = []

        for txn in candidates {
            guard !txn.isVoided else { continue }
            guard !context.gatedTransactionIDs.contains(txn.id) else { continue }
            guard !uncategorizedAccountIDs.isEmpty else { continue }
            guard txn.lineAccountIDs.contains(where: { uncategorizedAccountIDs.contains($0) }) else { continue }
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
                    "Open QuickBooks Online, find this transaction (vendor: \(txn.vendorName ?? "unknown"), \(txn.txnDate), \(txn.totalAmount))",
                    "Determine the correct expense or income category based on what was actually purchased or received",
                    "Edit the transaction and change the category from Uncategorized Expense/Income/Asset to the correct account",
                    "Save the transaction"
                ],
                pitfalls: [
                    "Uncategorized transactions often accumulate from bank-feed auto-add rules — check whether a bank rule needs fixing too, or this will keep recurring"
                ],
                doneCriteria: "The transaction shows a real expense or income category, not Uncategorized Expense/Income/Asset"
            )

            let action = ProposedAction(
                id: "recategorize-uncategorized-transaction",
                title: "Assign the correct category",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("P&L accuracy improves once recategorized to the correct account"),
                    .auditTrail("Voice Ledger records your attestation; the recategorization itself is QBO's own record")
                ],
                reversal: .reversibleManually(procedure: "Category can be changed again in QBO if corrected wrongly")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Uncategorized transaction — \(txn.vendorName ?? "unknown vendor"), \(txn.totalAmount)",
                severity: Severity.derive(dollarExposure: txn.totalAmount, materiality: context.materiality),
                confidence: .high,
                dollarExposure: txn.totalAmount,
                evidence: [EvidenceItem(transactionID: txn.id, highlightedFields: ["lineAccount"])],
                proposedActions: [action],
                provenance: [txn.provenance]
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
