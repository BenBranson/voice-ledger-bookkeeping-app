import Foundation

/// `VL-BS-NEGBAL-001`. docs/phase-0/08_RULE_ENGINE.md §8.8 (Page 8, Balance
/// Sheet Integrity), also independently listed in
/// docs/backlog/CLEANUP_MODE.md §1 as one of the Cleanup Assessment's own
/// checks ("Balance sheet: does it balance, are there negative assets").
///
/// A negative balance on an asset or liability account is structurally
/// abnormal: QBO's `CurrentBalance` shows liabilities as positive-when-owed,
/// so a negative liability balance means it's been overpaid, and a negative
/// asset balance means the account is overdrawn. Both are worth a human
/// look. Deliberately excludes Equity/Income/Expense — a negative balance
/// there is unremarkable (an owner's draw can legitimately exceed
/// contributions) and flagging it would just be noise.
public enum NegativeBalanceRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-BS-NEGBAL-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Negative asset or liability balance",
        category: .negativeAssetOrLiabilityBalance,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Asset and liability balances are conventionally non-negative in QBO's CurrentBalance sign convention. A negative asset balance means the account is overdrawn; a negative liability balance means it's been overpaid or miscoded — both indicate an error worth investigating, not a normal state.",
        sourceDependencies: [SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let candidates = input.accounts.filter { $0.accountType.isAssetOrLiability }
        var findings: [Finding] = []

        for account in candidates {
            guard account.currentBalance.minorUnits < 0 else { continue }
            let exposure = Money(minorUnits: abs(account.currentBalance.minorUnits), currency: account.currentBalance.currency)
            guard exposure >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [account.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let kind = [.bank, .accountsReceivable, .otherCurrentAsset, .fixedAsset, .otherAsset].contains(account.accountType)
                ? "asset" : "liability"

            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online, go to the Chart of Accounts",
                    "Open \(account.name) and review its recent transaction history",
                    kind == "asset"
                        ? "Determine why the balance went negative — common causes: a payment recorded before the corresponding deposit, or a miscoded transaction"
                        : "Determine why the balance went negative — common causes: an overpayment, a duplicate payment, or a miscoded transaction",
                    "Correct the underlying transaction(s) causing the negative balance, or confirm with the client whether this is expected (e.g. a genuine temporary overdraft)"
                ],
                pitfalls: [
                    "Do not adjust the balance directly with a journal entry without understanding the cause — that hides the underlying error rather than fixing it"
                ],
                doneCriteria: "\(account.name) shows a non-negative balance, or the negative balance is confirmed as an expected, temporary state"
            )

            let action = ProposedAction(
                id: "investigate-negative-balance",
                title: "Investigate the negative balance",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("balance sheet accuracy improves once the underlying cause is corrected"),
                    .auditTrail("Voice Ledger records your attestation; the correcting entries are QBO's own record")
                ],
                reversal: .reversibleManually(procedure: "Any correcting entry can itself be reversed in QBO if done in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "\(account.name) has a negative \(kind) balance — \(exposure)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .high,
                dollarExposure: exposure,
                evidence: [EvidenceItem(transactionID: account.id, highlightedFields: ["currentBalance"])],
                proposedActions: [action],
                provenance: []
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
