import Foundation

/// Completes the abnormal-balance family (owner feature list 2026-09-29):
/// assets/liabilities are `VL-BS-NEGBAL-001`, income/expense are
/// `VL-BS-DRCR-001`, Opening Balance Equity is `VL-OBE-BALANCE-001`. Only
/// contributed-capital subtypes are checked — draws, distributions, and
/// retained earnings legitimately carry debit balances (a draw, or an
/// accumulated loss), so flagging those would be noise, not a finding.
public enum EquityDebitBalanceRule: Rule {
    static let contributedCapitalSubTypes: Set<String> = [
        "CommonStock", "PreferredStock", "PaidInCapitalOrSurplus", "PartnerContributions"
    ]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-BS-EQUITY-DR-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Contributed-capital equity account with a debit balance",
        category: .debitCreditExpectationViolation,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Stock, paid-in capital, and partner contribution accounts record money owners put INTO the business, so they normally carry a credit balance. A debit balance usually means a draw, distribution, or personal expense was coded to the capital account instead of a draw/distribution account.",
        sourceDependencies: [SourceDependency(entity: .report), SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.report, .account],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard !input.trialBalanceLines.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Trial Balance report not loaded for this period. Visit the Trial Balance page (or resync) to run this check."))
        }
        guard !input.accounts.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Accounts not loaded for this sync."))
        }

        let accountsByFQN = Dictionary(input.accounts.compactMap { account in account.fullyQualifiedName.map { ($0, account) } }, uniquingKeysWith: { first, _ in first })

        var findings: [Finding] = []
        for line in input.trialBalanceLines where !line.isSummary {
            guard let account = accountsByFQN[line.label], account.accountType == .equity,
                  let subType = account.accountSubType, contributedCapitalSubTypes.contains(subType),
                  let debit = line.debit, debit.minorUnits > 0 else { continue }
            let exposure = debit
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
                    "Run a Transaction Detail report for \(account.name) covering all dates",
                    "Look for owner withdrawals, distributions, or personal purchases coded to \(account.name)",
                    "Reclassify those to the owner's draw / distributions account"
                ],
                pitfalls: [
                    "A genuine return of capital can reduce this account — confirm with the owner or CPA before reclassifying"
                ],
                doneCriteria: "\(account.name) shows a credit balance, or the debit is confirmed as an intended return of capital"
            )
            let action = ProposedAction(
                id: "review-equity-debit-balance",
                title: "Find what drove \(account.name) to a debit balance",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [.reporting("owner contributions and draws are misstated by up to \(exposure) on the Balance Sheet")],
                reversal: .reversibleManually(procedure: "Reverse the reclassification in QBO if it was wrong")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "\(account.name) (Equity) has a debit balance — \(exposure)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: account.id,
                    highlightedFields: ["trialBalance"],
                    fieldValues: ["account": account.name, "accountSubType": subType, "expectedSide": "credit", "wrongSideAmount": exposure.description]
                )],
                proposedActions: [action],
                provenance: [.qboAPI(readAt: Date())],
                narrative: "\(account.name) records owner capital put into the business and normally carries a credit balance, but the Trial Balance shows a \(exposure) debit.",
                riskIfIgnored: "The Balance Sheet understates owner capital and hides draws by up to \(exposure) until the miscoded entries are reclassified."
            ))
        }

        guard findings.isEmpty else { return .findings(findings) }
        return .pass(coverage: input.coverage, checkedCount: input.trialBalanceLines.count)
    }
}
