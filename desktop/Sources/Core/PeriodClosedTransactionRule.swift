import Foundation

/// `VL-PERIOD-CLOSED-001`. docs/phase-0/08_RULE_ENGINE.md §8.8's backlog
/// table: "Transactions dated in a closed period." Promotes the passive
/// warning list `Core/PeriodLock.swift`'s `PeriodLockCheck` already
/// computes for the Scope & Period Lock page into a real, first-class
/// `Finding` — with evidence, severity, and a guided procedure — so a
/// locked-period transaction also surfaces on Cleanup Assessment and the
/// Close Package, not just as a passive list on one page a bookkeeper has
/// to remember to check.
///
/// **"Closed" means Voice Ledger's own local `PeriodLock`, never QBO's
/// `BookCloseDate`** — unread in this sandbox (see `MonthEndChecklist
/// .swift`'s note). Setting a lock never touches QBO and never blocks a
/// QBO write; this rule only warns.
///
/// **The most common real trigger**: a bookkeeper locks April, later
/// re-syncs April to check something, and a stray transaction was added or
/// backdated into April after the lock — this rule catches it because
/// `NormalizedDataSet.transactions` is scoped to whatever period is
/// currently synced, so re-visiting a locked period is exactly when this
/// fires.
public enum PeriodClosedTransactionRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-PERIOD-CLOSED-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Transaction dated in a period Voice Ledger has locked",
        category: .transactionInLockedPeriod,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Once a period is closed, its transaction set should stop changing — that stability is what makes a closed period's reports trustworthy going forward. A transaction dated inside a period you've already locked means either a late entry slipped in after close, or an existing transaction was backdated into a period that should be settled.",
        sourceDependencies: []
    )

    public static let requirements = DataRequirements(
        entities: [],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard let lock = context.periodLock else {
            return .cannotEvaluate(.partialCoverage(reason: "No period lock has been set (docs/VOICE_LEDGER_SPEC.md Page 2). Set one on the Scope & Period Lock page to enable this check."))
        }

        // A statement line isn't a QBO-posted transaction — flagging it as
        // "dated in a closed period" wouldn't mean the same thing an actual
        // posted entry does, so it's excluded from the candidate set
        // entirely rather than compared.
        let candidates = input.transactions.filter { $0.entityKind != .importedBankStatementLine }
        let lockedTransactions = PeriodLockCheck.transactionsInLockedPeriod(candidates, lock: lock)

        var findings: [Finding] = []
        for txn in lockedTransactions {
            guard txn.totalAmount.minorUnits != 0 else { continue }
            let exposure = Money(minorUnits: abs(txn.totalAmount.minorUnits), currency: txn.totalAmount.currency)
            guard exposure >= context.materiality.absoluteFloor else { continue }

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
                    "Open QuickBooks Online and locate this transaction (\(txn.vendorName ?? "unknown"), \(txn.txnDate.formatted), \(txn.totalAmount))",
                    "Confirm whether it genuinely belongs in \(txn.txnDate.year)-\(String(format: "%02d", txn.txnDate.month)), a period you've locked through \(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month))",
                    "If it belongs in a later period, correct the date in QBO",
                    "If it genuinely belongs here, note why the lock needs revisiting for this period — Voice Ledger's lock is a local convention, not a QBO restriction, so this is a judgment call, not a system error"
                ],
                pitfalls: [
                    "Changing a transaction's date after reports were already generated for the locked period means those reports no longer reflect the current data",
                    "This lock is separate from QBO's own closing date — resolving this here does not require or imply anything about QBO's own period-close state"
                ],
                doneCriteria: "The transaction is either moved to its correct period, or you've confirmed it genuinely belongs here and accepted that the locked period's reports may need to be regenerated"
            )

            let action = ProposedAction(
                id: "resolve-locked-period-transaction",
                title: "Confirm or correct this transaction's period",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("reports already generated for the locked period may no longer match if this transaction is genuinely new"),
                    .auditTrail("Voice Ledger records your attestation; QBO's own record of any date change is authoritative")
                ],
                reversal: .reversibleManually(procedure: "A date change can be corrected again in QBO if done in error")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Transaction dated in a locked period — \(txn.vendorName ?? "unknown"), \(txn.totalAmount)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .high,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: txn.id,
                    highlightedFields: ["date", "amount"],
                    fieldValues: ["date": txn.txnDate.formatted, "amount": txn.totalAmount.description, "vendor": txn.vendorName ?? "unknown", "lockedThrough": "\(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month))"]
                )],
                proposedActions: [action],
                provenance: [txn.provenance],
                vendorName: txn.vendorName,
                narrative: "This \(txn.totalAmount) transaction\(txn.vendorName.map { " from \($0)" } ?? "") is dated \(txn.txnDate.formatted), inside the period you've locked through \(lock.lockedThrough.year)-\(String(format: "%02d", lock.lockedThrough.month)) — either it was entered or backdated after the lock was set.",
                riskIfIgnored: "Reports already generated for the locked period may silently no longer match what's actually posted in QBO for that period."
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
