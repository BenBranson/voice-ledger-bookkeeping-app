import Foundation

/// `VL-RECON-DIFF-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Bank/CC reconciliation differences." Distinct from `VL-RECON-MISSING-001`
/// (a single statement LINE with no matching posted transaction) and
/// `VL-VENDOR-MISMATCH-001` (a matched line whose vendor text looks wrong)
/// — this compares the statement's own stated ENDING BALANCE against QBO's
/// current balance for the same account, the aggregate check neither of
/// those two line-level rules performs.
///
/// **No new capability needed**: `LedgerAccount.currentBalance` is already
/// fetched on every sync (`sync()`'s `readAccounts` call), and
/// `OFXBankStatementImporter.Result.statedEndingBalance` was already being
/// extracted from the file's `<LEDGERBAL>` block — it was just being shown
/// to the user for a manual eyeball comparison
/// (`AppState.PendingOFXImport`'s old doc comment) and then discarded on
/// confirm, never persisted or compared. This rule is that comparison,
/// finally made real: `AppState.confirmOFXImport` now saves a
/// `BankStatementReconciliationSnapshot` per account, and this rule reads
/// it back.
///
/// **Known imprecision, disclosed rather than hidden**: `currentBalance`
/// reflects the account's balance AS OF THE SYNC (right now), while
/// `statedEndingBalance` reflects the statement's AS-OF DATE, which is
/// almost always earlier. Any real activity in between will show up here
/// as "drift" even when the account is genuinely reconciled — this rule
/// cannot tell the two apart, and says so in its own guided procedure.
/// It's still a useful check for what it actually catches well: a large,
/// otherwise-unexplained gap (a missed deposit, a duplicate entry, a typo)
/// that swamps whatever small amount of real between-dates activity would
/// otherwise explain a difference.
public enum BankReconciliationDriftRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-RECON-DIFF-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Bank statement ending balance doesn't match QBO",
        category: .bankReconciliationDifference,
        ruleClass: .categorization,
        page: .bankFeedCleanup,
        accountingPrinciple: "A bank or credit card account's balance in QBO should track its real-world statement balance closely. A large gap between the two — beyond what a few days of normal, unreconciled activity would explain — usually means something is missing, duplicated, or miscoded in the posted transactions for that account.",
        sourceDependencies: [SourceDependency(entity: .account)]
    )

    public static let requirements = DataRequirements(
        entities: [.account],
        requiredCoverage: .complete
    )

    /// A gap below this fraction of the statement balance is treated as
    /// plausibly explained by ordinary between-dates activity and not
    /// flagged, even if it clears the flat materiality floor — a $30 gap
    /// on a $50,000 balance is very likely just a few days of real
    /// transactions, not a real problem.
    static let minimumRelativeGap: Double = 0.02

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard !context.bankStatementSnapshots.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "No bank statement has been imported with a stated ending balance yet. Import an OFX/QFX file on the Bank Feed Cleanup page to enable this check."))
        }
        guard !input.accounts.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Accounts not loaded for this sync."))
        }

        let accountsByID = Dictionary(input.accounts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var findings: [Finding] = []
        for snapshot in context.bankStatementSnapshots.sorted(by: { $0.accountID < $1.accountID }) {
            guard let account = accountsByID[snapshot.accountID] else { continue }

            let gap = account.currentBalance - snapshot.statedEndingBalance
            let exposure = Money(minorUnits: abs(gap.minorUnits), currency: gap.currency)
            guard exposure >= context.materiality.absoluteFloor else { continue }

            let relativeGap = snapshot.statedEndingBalance.minorUnits != 0
                ? Double(exposure.minorUnits) / Double(abs(snapshot.statedEndingBalance.minorUnits))
                : 1.0
            guard relativeGap >= minimumRelativeGap else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [account.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let asOfText = snapshot.statedAsOfDate?.formatted ?? "an unspecified date"
            let procedure = GuidedProcedure(
                steps: [
                    "Open QBO's Reconcile tool for \(account.name) and compare against the same bank statement imported here",
                    "Look for transactions on the statement that never got posted to QBO, or posted transactions that don't appear on the statement",
                    "Check for duplicate postings or a miscoded amount around the statement's as-of date (\(asOfText))",
                    "If the gap is fully explained by real activity between \(asOfText) and today, no correction is needed"
                ],
                pitfalls: [
                    "QBO's current balance is as of RIGHT NOW, not the statement's as-of date — some of this gap may be genuine, real activity that happened after the statement, not an error",
                    "A gap that's a round number (e.g. exactly $100.00) often means a single missing or duplicate transaction, worth checking first"
                ],
                doneCriteria: "The gap is either fully explained by activity after the statement date, or the missing/duplicate/miscoded transaction has been found and corrected in QBO"
            )

            let action = ProposedAction(
                id: "review-bank-reconciliation-diff",
                title: "Investigate the balance gap for \(account.name)",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("\(account.name)'s QBO balance may be off by up to \(exposure) from what the bank actually shows")
                ],
                reversal: .reversibleManually(procedure: "Correct whatever missing/duplicate/miscoded transaction is found, once identified")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "\(account.name)'s QBO balance doesn't match the imported bank statement — off by \(exposure)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: account.id,
                    highlightedFields: ["balance"],
                    fieldValues: [
                        "account": account.name,
                        "qboCurrentBalance": account.currentBalance.description,
                        "statementEndingBalance": snapshot.statedEndingBalance.description,
                        "statementAsOfDate": asOfText,
                        "gap": exposure.description
                    ]
                )],
                proposedActions: [action],
                provenance: [.importedFile(documentID: "bank-statement-\(snapshot.accountID)", importedAt: snapshot.importedAt, extractionMethod: .deterministicParse, coverage: .complete)],
                narrative: "\(account.name)'s current QBO balance (\(account.currentBalance)) is off by \(exposure) from the \(snapshot.statedEndingBalance) ending balance stated on the bank statement imported for \(asOfText).",
                riskIfIgnored: "This gap stays unexplained — either as genuine later activity or as a real missing/duplicate/miscoded transaction — until someone runs QBO's own Reconcile tool against the same statement."
            ))
        }

        guard findings.isEmpty else {
            return .findings(findings)
        }
        return .pass(coverage: input.coverage, checkedCount: context.bankStatementSnapshots.count)
    }
}
