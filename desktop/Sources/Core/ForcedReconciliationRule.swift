import Foundation

/// `VL-FORCED-RECON-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Non-zero balance in Reconciliation Discrepancies — someone forced a
/// reconciliation to close rather than finding the cause."
///
/// **Live-verified 2026-08-18** against a real forced reconciliation the
/// owner performed in the sandbox UI (Checking account, statement ending
/// balance deliberately set to $1.00, "Add adjustment and finish" taken
/// despite a $4,264.76 difference). Two detection paths were tried and
/// disproven first: `Account.CurrentBalance` on the resulting
/// "Reconciliation Discrepancies" account read `0` despite the real
/// adjustment (a known QBO behavior for Expense-classified accounts — that
/// field isn't meaningful for them), and no `JournalEntry` was created for
/// it either (queried directly, none found). **The only place the API
/// actually surfaces this is the Profit & Loss report** — an "Other
/// Expenses" line literally named "Reconciliation Discrepancies" with the
/// real adjustment amount. This rule reads exactly that.
public enum ForcedReconciliationRule: Rule {
    static let discrepancyLineLabel = "Reconciliation Discrepancies"

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-FORCED-RECON-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Reconciliation was forced despite a discrepancy",
        category: .forcedReconciliation,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A reconciliation that doesn't balance to zero and is finished anyway with an adjustment means the underlying discrepancy was never actually explained — QBO posts the difference to its own \"Reconciliation Discrepancies\" account rather than resolving it, which papers over whatever mismatch caused it.",
        sourceDependencies: [SourceDependency(entity: .report)]
    )

    public static let requirements = DataRequirements(
        entities: [.report],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard !input.profitAndLossLines.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Profit & Loss report not loaded for this period. Visit the Profit & Loss page (or resync) to run this check."))
        }

        guard let discrepancyLine = input.profitAndLossLines.first(where: { $0.label == discrepancyLineLabel }),
              let amount = discrepancyLine.amount,
              amount.minorUnits != 0 else {
            return .pass(coverage: input.coverage, checkedCount: 1)
        }

        let exposure = amount.minorUnits < 0 ? Money(minorUnits: -amount.minorUnits, currency: amount.currency) : amount
        guard exposure >= context.materiality.absoluteFloor else {
            return .pass(coverage: input.coverage, checkedCount: 1)
        }

        let severity = Severity.derive(dollarExposure: exposure, materiality: context.materiality)
        let findingID = FindingIDGenerator.makeID(
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            sortedAffectedIDs: [discrepancyLineLabel]
        )
        if context.dismissedFindingIDs.contains(findingID) {
            return .pass(coverage: input.coverage, checkedCount: 1)
        }

        let procedure = GuidedProcedure(
            steps: [
                "Open QuickBooks Online → Accounting → Reconcile",
                "Find the reconciliation(s) that were finished with a difference — check the reconciliation history for each bank/credit card account",
                "Identify which transactions actually caused the mismatch (a missing deposit, a duplicate entry, a wrong amount)",
                "Undo the forced reconciliation if you can identify and fix the real cause, then redo it so it balances to $0.00 without an adjustment",
                "If the cause can't be found, at minimum document what happened and why the adjustment was accepted"
            ],
            pitfalls: [
                "Undoing a reconciliation can affect other already-reconciled periods if transactions were shared — check before undoing",
                "A small, immaterial adjustment may be a genuine rounding difference, not a real error — use judgment"
            ],
            doneCriteria: "The Reconciliation Discrepancies account carries no new unexplained balance for this period, or the adjustment has been reviewed and documented as accepted"
        )

        let action = ProposedAction(
            id: "review-forced-reconciliation",
            title: "Review the forced reconciliation adjustment",
            resolution: .manualQBO,
            guidedProcedure: procedure,
            consequences: [
                .reconciliation("the account's reconciled balance may not reflect its true state until the real cause is found"),
                .reporting("\(exposure) sits in Reconciliation Discrepancies (Other Expenses) instead of the account it actually belongs to"),
                .auditTrail("Voice Ledger records your attestation; QBO's own reconciliation history is authoritative")
            ],
            reversal: .reversibleManually(procedure: "Undo the reconciliation in QBO and redo it correctly, if the real cause is found")
        )

        let finding = Finding(
            id: findingID,
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            title: "Reconciliation Discrepancies carries a balance — \(exposure)",
            severity: severity,
            confidence: .high,
            dollarExposure: exposure,
            evidence: [EvidenceItem(transactionID: discrepancyLineLabel, highlightedFields: ["amount"], fieldValues: ["amount": exposure.description])],
            proposedActions: [action],
            provenance: [.qboAPI(readAt: Date())],
            narrative: "The Profit & Loss report shows \(exposure) in Reconciliation Discrepancies — a reconciliation was finished with a difference that QBO papered over with an adjustment rather than the underlying cause being found.",
            riskIfIgnored: "This \(exposure) will keep sitting in Reconciliation Discrepancies (Other Expenses) instead of wherever it actually belongs until the real cause is found and corrected."
        )
        return .findings([finding])
    }
}
