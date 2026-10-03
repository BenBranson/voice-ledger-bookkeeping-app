import Foundation

/// `VL-OBE-BALANCE-001`. docs/backlog/REDDIT_FEEDBACK_ASSESSMENT.md item B:
/// a non-zero balance in the system-created Opening Balance Equity account
/// is a classic signature of a file someone set up themselves — QBO parks
/// unreconciled opening-balance amounts there, and a real close should leave
/// it at zero.
///
/// **Design history worth keeping:** this rule was originally scoped as
/// `VL-OPENING-BAL-001` ("account has a non-zero opening balance entry, and
/// an equity contribution exists within N days of the opening date") per
/// `docs/backlog/CLEANUP_MODE.md` §2.5. That approach was tried against the
/// live sandbox and DISPROVEN before being built: `Account.OpeningBalance`
/// and `OpeningBalanceDate` are write-only on `Account` create — QBO
/// accepts them to seed `CurrentBalance` but never returns them on a
/// subsequent read, not even in the create response itself. There is no
/// field to read the "opening balance entry" back from. Pivoted to this
/// rule instead, which needs only an account balance already in the synced
/// chart of accounts — no new capability, no unreadable field.
public enum OpeningBalanceEquityRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-OBE-BALANCE-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Non-zero Opening Balance Equity",
        category: .openingBalanceEquity,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Opening Balance Equity is a temporary holding account QBO uses when a beginning balance is entered. A properly closed-out file has zero in this account — a nonzero balance means an opening balance was never reconciled to the actual books, a common signature of a self-set-up or never-fully-onboarded file.",
        sourceDependencies: [SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let obeAccounts = input.accounts.filter { $0.accountSubType == "OpeningBalanceEquity" }
        var findings: [Finding] = []

        for account in obeAccounts {
            let balance = input.periodEndBalance(of: account)
            guard balance.minorUnits != 0 else { continue }
            let exposure = Money(minorUnits: abs(balance.minorUnits), currency: balance.currency)
            guard exposure >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [account.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online, go to the Chart of Accounts",
                    "Open \(account.name) and review what's posted to it",
                    "Determine what the balance represents — usually an opening balance entered when the company file (or a bank/credit card account) was first set up",
                    "Work with the client or prior bookkeeper to identify the correct opening balance and reclassify the difference to the appropriate account",
                    "Confirm the account returns to zero once the correct entries are made"
                ],
                pitfalls: [
                    "Do not zero this out with an unexplained journal entry — the balance is a symptom of a real discrepancy that needs to be traced, not hidden",
                    "A nonzero Opening Balance Equity often pairs with other setup issues (duplicate opening entries, missing prior-period data) — check those too"
                ],
                doneCriteria: "Opening Balance Equity carries a zero balance"
            )

            let action = ProposedAction(
                id: "investigate-opening-balance-equity",
                title: "Investigate and clear the Opening Balance Equity balance",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("balance sheet accuracy improves once the true source of this balance is identified and correctly classified"),
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
                title: "Opening Balance Equity carries a nonzero balance — \(exposure)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .high,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: account.id,
                    highlightedFields: ["currentBalance"],
                    fieldValues: ["currentBalance": exposure.description, "account": account.name]
                )],
                proposedActions: [action],
                provenance: [],
                narrative: "\(account.name) carries a \(exposure) balance — Opening Balance Equity should be zero once a file is fully set up and reconciled.",
                riskIfIgnored: "Your balance sheet will keep showing this \(exposure) as an unresolved opening-balance discrepancy on every report until it's traced and reclassified."
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: obeAccounts.count)
        }
        return .findings(findings)
    }
}
