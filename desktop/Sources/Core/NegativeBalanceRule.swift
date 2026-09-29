import Foundation

/// `VL-BS-NEGBAL-001`. docs/phase-0/08_RULE_ENGINE.md §8.8 (Page 8, Balance
/// Sheet Integrity), also independently listed in
/// docs/backlog/CLEANUP_MODE.md §1 as one of the Cleanup Assessment's own
/// checks ("Balance sheet: does it balance, are there negative assets").
///
/// A balance on the wrong side of an asset or liability account is
/// structurally abnormal: a negative asset balance means the account is
/// overdrawn; a liability that shows a debit balance has been overpaid.
///
/// **Sign convention, verified against the sandbox 2026-09-29**
/// (`voiceledger-devtool balances-check 2026 7`): QBO's `Account.CurrentBalance`
/// reports liability and credit-card accounts as NEGATIVE when money is
/// owed (Notes Payable -25,000.00, Loan Payable -4,000.00, Mastercard
/// -157.72 — all shown positive on the Balance Sheet report). v1.0 assumed
/// the opposite and flagged every normal liability; v1.1 flags a liability
/// only when `CurrentBalance > 0`. Both are worth a human
/// look. Deliberately excludes Equity/Income/Expense — a negative balance
/// there is unremarkable (an owner's draw can legitimately exceed
/// contributions) and flagging it would just be noise.
public enum NegativeBalanceRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-BS-NEGBAL-001"),
        version: RuleVersion(major: 1, minor: 1, patch: 0),
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
            guard isAbnormal(account) else { continue }
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

            let kind = isAsset(account.accountType) ? "asset" : "liability"

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
                title: kind == "asset" ? "\(account.name) is overdrawn — \(exposure)" : "\(account.name) shows more paid than owed — \(exposure)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .high,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: account.id,
                    highlightedFields: ["currentBalance"],
                    fieldValues: ["currentBalance": account.currentBalance.description, "account": account.name]
                )],
                proposedActions: [action],
                provenance: [],
                narrative: kind == "asset"
                    ? "\(account.name) is below zero by \(exposure) as of the latest sync. An asset account normally can't go below zero; this is usually a real overdraft or a payment recorded before its deposit, and needs review."
                    : "\(account.name) shows \(exposure) more paid than owed as of the latest sync. This is unusual and needs review — it can be an overpayment, a credit, a misclassified payment, or a missing bill.",
                riskIfIgnored: "The underlying cause stays uncorrected and \(account.name)'s balance stays wrong until this is investigated — this could be masking a real overdraft, overpayment, or miscoded transaction."
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

    static func isAsset(_ type: LedgerAccountType) -> Bool {
        [.bank, .accountsReceivable, .otherCurrentAsset, .fixedAsset, .otherAsset].contains(type)
    }

    /// Assets: below zero. Liabilities: above zero in QBO's CurrentBalance
    /// (which reports money owed as negative — see the type comment).
    static func isAbnormal(_ account: LedgerAccount) -> Bool {
        isAsset(account.accountType) ? account.currentBalance.minorUnits < 0 : account.currentBalance.minorUnits > 0
    }
}
