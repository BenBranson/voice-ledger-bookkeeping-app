import Foundation

/// `VL-CAT-MISCODE-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Probable miscoding vs. vendor history." Reuses `input.priorPeriodTransactions`
/// (added for `VL-VEND-PRICE-001` — no new capability needed here either).
///
/// **Requires a genuinely unanimous prior-period pattern before flagging
/// anything.** A vendor is only a "history" once it has at least two
/// prior-period Purchases and every single one of them was coded to the
/// SAME account — a vendor that's legitimately been split across two
/// accounts before has no stable pattern to measure a "miscoding"
/// against, and flagging one of its normal accounts as wrong would be a
/// real false positive, not a cautious guess. Same discipline
/// `VL-VEND-DUPSVC-001`'s backlog note and `VL-COA-DUPACCT-001`'s
/// disproven naive-matching investigation both apply elsewhere in this
/// file: don't ship a rule that fires on a legitimate, existing pattern.
///
/// **Only single-line transactions are compared, on both sides.** A split
/// transaction (coded across multiple accounts) isn't "coded to one
/// place" in the first place — there's no single current account to
/// compare against a single historical one, and guessing which of several
/// lines is "the" miscoded one isn't a safe inference.
public enum CategoryMiscodeRule: Rule {
    /// Below this many prior-period transactions, "every one was the same
    /// account" isn't a real pattern yet — it could just as easily be
    /// coincidence from a single data point.
    static let minimumPriorTransactionsForHistory = 2

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-CAT-MISCODE-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Transaction coded differently than this vendor's usual account",
        category: .probableMiscoding,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A vendor that's always been coded to the same expense account probably belongs there again — a transaction from that vendor landing on a different account this period is more likely a miscoding slip than a real change in what's being purchased.",
        sourceDependencies: [SourceDependency(entity: .purchase), SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase, .account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard !input.priorPeriodTransactions.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Prior period's purchases not loaded for this sync — this check needs last period's coding history to compare against."))
        }

        let accountNamesByID = Dictionary(input.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        let priorByVendor = Self.groupSingleLineByVendor(input.priorPeriodTransactions)
        var baselineAccountByVendor: [String: String] = [:]
        for (vendorName, priorGroup) in priorByVendor where priorGroup.count >= minimumPriorTransactionsForHistory {
            let accountIDs = Set(priorGroup.map(\.accountID))
            guard accountIDs.count == 1, let onlyAccountID = accountIDs.first else { continue }
            baselineAccountByVendor[vendorName] = onlyAccountID
        }

        let currentSingleLine = Self.singleLineTransactions(input.transactions)

        var findings: [Finding] = []
        for txn in currentSingleLine.sorted(by: { $0.id < $1.id }) {
            guard let vendorName = txn.vendorName, let baselineAccountID = baselineAccountByVendor[vendorName] else { continue }
            let currentAccountID = txn.lineAccountIDs[0]
            guard currentAccountID != baselineAccountID else { continue }
            guard let currentAccountName = accountNamesByID[currentAccountID], let baselineAccountName = accountNamesByID[baselineAccountID] else { continue }
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
                    "Open this \(txn.totalAmount) transaction from \(vendorName), currently coded to \(currentAccountName)",
                    "Confirm whether it genuinely belongs on \(currentAccountName) this time, or should be \(baselineAccountName) like every other prior-period charge from this vendor",
                    "If it's a miscoding, recode the line to \(baselineAccountName) in QBO",
                    "If it's intentional (a genuinely different purchase from this vendor), no correction is needed"
                ],
                pitfalls: [
                    "A vendor CAN legitimately sell more than one type of product or service — this flag means \"different from this vendor's history,\" not \"definitely wrong\""
                ],
                doneCriteria: "The coding has been confirmed as correct, or recoded to match this vendor's established account"
            )

            let action = ProposedAction(
                id: "review-category-miscode",
                title: "Confirm or recode this transaction's account",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("If this is a miscoding, \(txn.totalAmount) is currently misclassified under \(currentAccountName) instead of \(baselineAccountName)")
                ],
                reversal: .reversibleManually(procedure: "Recode the line's account in QBO if it was coded in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "\(vendorName) coded to \(currentAccountName), usually \(baselineAccountName)",
                severity: Severity.derive(dollarExposure: txn.totalAmount, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: txn.totalAmount,
                evidence: [EvidenceItem(
                    transactionID: txn.id,
                    highlightedFields: ["account"],
                    fieldValues: [
                        "vendorName": vendorName,
                        "amount": txn.totalAmount.description,
                        "currentAccount": currentAccountName,
                        "usualAccount": baselineAccountName
                    ]
                )],
                proposedActions: [action],
                provenance: [txn.provenance],
                vendorName: vendorName,
                narrative: "\(vendorName)'s \(txn.totalAmount) transaction this period is coded to \(currentAccountName), but every prior-period charge from this vendor was coded to \(baselineAccountName) instead.",
                riskIfIgnored: "If this is a miscoding, it stays misclassified on the books until confirmed or recoded."
            ))
        }

        guard findings.isEmpty else {
            return .findings(findings)
        }
        return .pass(coverage: input.coverage, checkedCount: currentSingleLine.count)
    }

    private struct VendorCodedTransaction {
        let vendorName: String
        let accountID: String
    }

    private static func groupSingleLineByVendor(_ transactions: [LedgerTransaction]) -> [String: [VendorCodedTransaction]] {
        var byVendor: [String: [VendorCodedTransaction]] = [:]
        for txn in Self.singleLineTransactions(transactions) {
            guard let vendorName = txn.vendorName else { continue }
            byVendor[vendorName, default: []].append(VendorCodedTransaction(vendorName: vendorName, accountID: txn.lineAccountIDs[0]))
        }
        return byVendor
    }

    private static func singleLineTransactions(_ transactions: [LedgerTransaction]) -> [LedgerTransaction] {
        transactions.filter { !$0.isVoided && $0.entityKind == .purchase && $0.vendorName != nil && $0.lineAccountIDs.count == 1 }
    }
}
