import Foundation

/// `VL-BS-DRCR-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Debit/credit pattern vs. account expectation."
///
/// **Deliberately scoped to Income/Other Income/Expense/Other
/// Expense/Cost of Goods Sold only — never Asset/Liability.** An
/// Asset/Liability account on the "wrong" side of the Trial Balance is
/// the exact same fact `VL-BS-NEGBAL-001` already reports as a negative
/// balance (live-verified in this sandbox: `Checking` shows on the
/// CREDIT side of the Trial Balance and ALSO has a negative
/// `CurrentBalance` — one real fact, not two). Shipping both would mean
/// two rule IDs firing on the same evidence. Income/Expense accounts are
/// the genuine gap: `VL-BS-NEGBAL-001` explicitly excludes them (its own
/// doc comment: "a negative balance there is unremarkable"), but an
/// Expense account posting to the CREDIT side, or an Income account
/// posting to the DEBIT side, is a real structural anomaly that rule
/// never catches.
///
/// **`AccountSubType == "DiscountsRefundsGiven" is excluded — live-verified
/// 2026-08-28 as a real false-positive risk, not a hypothetical one.**
/// This sandbox's real "Discounts given" account (Income type) legitimately
/// carries a DEBIT balance ($89.50) — a contra-revenue account, where a
/// debit balance is the CORRECT, expected state (a discount reduces
/// income). A naive "Income always credit" rule would have flagged this
/// real, correct account. Checked the full account list for any
/// symmetric contra-Expense subtype in this sandbox and found none — if
/// one is discovered later, it needs the same exclusion added here rather
/// than silently false-positiving.
public enum DebitCreditExpectationRule: Rule {
    /// The one contra-type subtype confirmed live to legitimately violate
    /// the naive expectation — see the type's own doc comment.
    static let excludedSubTypes: Set<String> = ["DiscountsRefundsGiven"]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-BS-DRCR-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Income or Expense account on the wrong side of the Trial Balance",
        category: .debitCreditExpectationViolation,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "An Income account normally carries a credit balance and an Expense account normally carries a debit balance — that's what those account types mean. One showing up on the opposite side of the Trial Balance usually means a transaction was entered with the wrong sign, or coded as a negative amount instead of using a proper credit/refund transaction.",
        sourceDependencies: [SourceDependency(entity: .report), SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.report, .account],
        requiredCoverage: .complete
    )

    private static let incomeLikeTypes: Set<LedgerAccountType> = [.income, .otherIncome]
    private static let expenseLikeTypes: Set<LedgerAccountType> = [.expense, .otherExpense, .costOfGoodsSold]

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
            guard let account = accountsByFQN[line.label] else { continue }
            guard !Self.excludedSubTypes.contains(account.accountSubType ?? "") else { continue }

            let wrongSideAmount: Money?
            let expectedSide: String
            if incomeLikeTypes.contains(account.accountType) {
                expectedSide = "credit"
                wrongSideAmount = line.debit
            } else if expenseLikeTypes.contains(account.accountType) {
                expectedSide = "debit"
                wrongSideAmount = line.credit
            } else {
                continue
            }

            guard let wrongSideAmount, wrongSideAmount.minorUnits != 0 else { continue }
            let exposure = Money(minorUnits: abs(wrongSideAmount.minorUnits), currency: wrongSideAmount.currency)
            guard exposure >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [account.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let kind = incomeLikeTypes.contains(account.accountType) ? "Income" : "Expense"
            let wrongSide = expectedSide == "credit" ? "debit" : "credit"

            let procedure = GuidedProcedure(
                steps: [
                    "Run a Transaction Detail report for \(account.name) for this period",
                    "Look for a transaction entered with a negative amount, or a refund/credit posted directly to this account instead of through a proper credit memo or vendor credit",
                    "Correct the sign or reclassify the transaction so \(account.name) reflects a normal \(expectedSide) balance"
                ],
                pitfalls: [
                    "A genuine contra account (e.g. a discounts-given account) can legitimately carry the opposite balance — confirm this account isn't meant to work that way before treating it as an error"
                ],
                doneCriteria: "\(account.name) shows a normal \(expectedSide) balance, or the opposite balance is confirmed as this account's genuine, intended behavior"
            )

            let action = ProposedAction(
                id: "review-debit-credit-expectation",
                title: "Investigate this account's unexpected \(wrongSide) balance",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("\(kind) is currently misstated by up to \(exposure) if this is a sign or coding error")
                ],
                reversal: .reversibleManually(procedure: "Correct the underlying transaction in QBO once the cause is found")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "\(account.name) (\(kind)) has an unexpected \(wrongSide) balance — \(exposure)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: account.id,
                    highlightedFields: ["trialBalance"],
                    fieldValues: [
                        "account": account.name,
                        "accountType": kind,
                        "expectedSide": expectedSide,
                        "wrongSideAmount": exposure.description
                    ]
                )],
                proposedActions: [action],
                provenance: [.qboAPI(readAt: Date())],
                narrative: "\(account.name) is an \(kind) account, which normally carries a \(expectedSide) balance, but the Trial Balance shows \(exposure) on the \(wrongSide) side this period.",
                riskIfIgnored: "\(kind) stays potentially misstated by \(exposure) until the underlying sign or coding error is found and corrected."
            ))
        }

        guard findings.isEmpty else {
            return .findings(findings)
        }
        return .pass(coverage: input.coverage, checkedCount: input.trialBalanceLines.count)
    }
}
