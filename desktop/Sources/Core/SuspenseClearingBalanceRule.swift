import Foundation

/// The suspense half of the owner's "Suspense & Uncategorized Sweeper"
/// (2026-09-29; uncategorized/Ask My Accountant is `VL-CAT-UNCAT-001`,
/// Opening Balance Equity is `VL-OBE-BALANCE-001`). Suspense and clearing
/// accounts are user-named, so matching is a substring on the name but
/// restricted to balance-sheet accounts — an expense like "Clearing House
/// Fees" is never swept in. Sandbox-proven via
/// spike/seeds/sweeper-and-near-duplicates.json.
public enum SuspenseClearingBalanceRule: Rule {
    enum Kind: String {
        case suspense, clearing
    }

    static func kind(of account: LedgerAccount) -> Kind? {
        guard account.accountType.isAssetOrLiability else { return nil }
        let name = account.name.lowercased()
        if name.contains("suspense") { return .suspense }
        if name.contains("clearing") { return .clearing }
        return nil
    }

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-BS-SUSPENSE-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Suspense or clearing account not zeroed",
        category: .suspenseOrClearingBalance,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Suspense and clearing accounts are temporary parking spots: suspense holds amounts nobody has identified yet, and a clearing account (payroll clearing, merchant clearing) should net back to zero once both sides of a transfer post. Any balance left at close is either an unidentified item or half of a transaction that never finished, and it misstates the Balance Sheet.",
        sourceDependencies: [SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard !input.accounts.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Accounts not loaded for this sync."))
        }
        var findings: [Finding] = []
        for account in input.accounts {
            guard let kind = kind(of: account), account.currentBalance.minorUnits != 0 else { continue }
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

            let procedure = GuidedProcedure(
                steps: kind == .suspense
                    ? [
                        "Run a Transaction Detail report for \(account.name) covering all dates",
                        "For each posting, identify what it really was (ask the client if needed)",
                        "Reclassify each one to its correct account until \(account.name) is zero"
                    ]
                    : [
                        "Run a Transaction Detail report for \(account.name) covering all dates",
                        "Match each posting in with the posting that should clear it out (e.g. the payroll run against the payroll funding transfer)",
                        "For anything unmatched, record the missing side or correct the miscoded one until \(account.name) is zero"
                    ],
                pitfalls: [
                    "Don't plug the balance with a single journal entry to an expense — that hides the real problem",
                    "An old balance may pre-date a closed period; if so, correct it in the current period rather than editing closed books"
                ],
                doneCriteria: "\(account.name) carries a zero balance"
            )
            let action = ProposedAction(
                id: "clear-\(kind.rawValue)-account",
                title: kind == .suspense ? "Identify and reclassify what's in \(account.name)" : "Find the unmatched side and clear \(account.name)",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [.reporting("the Balance Sheet carries \(exposure) that belongs somewhere else")],
                reversal: .reversibleManually(procedure: "Reverse the reclassification in QBO if it was wrong")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "\(account.name) has a \(exposure) balance — \(kind == .suspense ? "unidentified items in suspense" : "clearing account not zeroed")",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .high,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: account.id,
                    highlightedFields: ["currentBalance"],
                    fieldValues: ["account": account.name, "accountType": account.accountType.rawValue, "currentBalance": account.currentBalance.description, "kind": kind.rawValue]
                )],
                proposedActions: [action],
                provenance: [.qboAPI(readAt: Date())],
                narrative: kind == .suspense
                    ? "\(account.name) is holding \(exposure) that was never identified and moved to its real account."
                    : "\(account.name) should net to zero once both sides of each transfer post, but it's carrying \(exposure).",
                riskIfIgnored: "The Balance Sheet stays misstated by \(exposure), and whatever those amounts really were is missing from the right accounts."
            ))
        }
        if findings.isEmpty { return .pass(coverage: input.coverage, checkedCount: input.accounts.count) }
        return .findings(findings)
    }
}
