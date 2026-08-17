import Foundation

/// `VL-VENDCREDIT-UNAPPLIED-001` — the vendor-refunds-and-credits cleanup
/// workflow, added by explicit owner request. Not part of the original
/// 27-rule backlog table; tracked here and in
/// `docs/phase-0/08_RULE_ENGINE.md` §8.8 directly.
///
/// When a vendor issues a credit (returned goods, an overcharge correction,
/// a promotional credit), QBO records a `VendorCredit`. That credit is only
/// useful once it's actually applied — to a future Bill, or refunded back
/// as cash. Left sitting, it's money the business is effectively owed but
/// isn't using: it doesn't reduce the next bill, doesn't show up as
/// available cash, and is easy to forget entirely (the credit itself
/// creates no reminder). This rule flags a `VendorCredit` whose `Balance`
/// (QBO's own "how much is still unapplied" field, verified live — not
/// derived from cross-referencing other entities) is still nonzero well
/// past its own date.
public enum UnappliedVendorCreditRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-VENDCREDIT-UNAPPLIED-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Unapplied vendor credit",
        category: .unappliedVendorCredit,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A vendor credit is an asset the business is owed — it should reduce a future bill or come back as cash. Left unapplied indefinitely, it neither reduces expenses nor shows up as available cash, and is easy to lose track of entirely since QBO surfaces no reminder on its own.",
        sourceDependencies: [SourceDependency(entity: .vendorCredit)]
    )

    public static let requirements = DataRequirements(
        entities: [.vendorCredit],
        requiredCoverage: .complete
    )

    /// Calendar days a vendor credit may sit unapplied before this rule
    /// considers it worth a look. Looser than a typical billing cycle
    /// (~30 days) so a credit still being actively worked through normal
    /// AP flow isn't flagged prematurely.
    private static let agingThresholdDays = 30

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        var findings: [Finding] = []

        for credit in input.vendorCredits {
            guard credit.balance.minorUnits > 0 else { continue }
            let ageDays = AccountingDate.daysBetween(credit.txnDate, context.asOfDate)
            guard ageDays > agingThresholdDays else { continue }
            guard credit.balance >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [credit.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let vendorName = credit.vendorName ?? "unknown vendor"
            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online, go to Expenses, find the vendor \(vendorName)",
                    "Locate the vendor credit dated \(credit.txnDate), \(credit.balance) still unapplied",
                    "Check whether there's an open bill from this vendor the credit could be applied to",
                    "If yes: apply the credit the next time you pay a bill from this vendor (Pay Bills, select both the bill and the credit)",
                    "If no open bill exists and the vendor owes a cash refund instead: record the refund as a Check or Expense using Accounts Payable as the category, linked to this credit"
                ],
                pitfalls: [
                    "Don't just delete or ignore the credit — it represents real money owed to the business",
                    "A cash refund needs the correct linking step in QBO (AP-categorized Check/Expense applied to the credit), not a plain deposit, or the vendor's balance won't reconcile"
                ],
                doneCriteria: "The vendor credit's balance is $0 — either applied to a bill or refunded and linked correctly"
            )

            let action = ProposedAction(
                id: "apply-or-refund-vendor-credit",
                title: "Apply the credit to a bill, or record the refund",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("accounts payable and vendor balances become accurate once applied or refunded"),
                    .auditTrail("Voice Ledger records your attestation; the application/refund itself is QBO's own record")
                ],
                reversal: .reversibleManually(procedure: "An applied credit can be unapplied, and a recorded refund edited, in QBO if done in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Unapplied vendor credit after \(ageDays) days — \(vendorName), \(credit.balance)",
                severity: Severity.derive(dollarExposure: credit.balance, materiality: context.materiality),
                confidence: .high,
                dollarExposure: credit.balance,
                evidence: [EvidenceItem(transactionID: credit.id, highlightedFields: ["balance", "txnDate"])],
                proposedActions: [action],
                provenance: [credit.provenance]
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: input.vendorCredits.count)
        }
        return .findings(findings)
    }
}
