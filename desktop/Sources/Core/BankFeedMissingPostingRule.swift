import Foundation

/// `VL-RECON-MISSING-001`. docs/VOICE_LEDGER_SPEC.md Page 4 (Bank Feed
/// Cleanup, Type B): "analyzes posted QBO activity and compares it against
/// your imported CSV/OFX/QFX statement; detects duplicates and missing
/// postings." This rule is the "missing postings" half — an imported
/// statement line with no matching posted `Purchase`/`Bill` means the bank
/// activity was never entered in QBO at all.
///
/// **Two honest states, mirroring Page 5's own requirement (spec):**
/// no imported statement at all is `.cannotEvaluate`, never a silent
/// `.pass` — Type B pages cannot go green on API data alone (spec: "Cannot
/// see the 'For Review' queue... none of it is API-exposed").
///
/// **Deliberately does NOT auto-create the missing Purchase.** Spec's own
/// safety rule for this exact page: "if the statement shows a $500 expense
/// missing from posted QBO activity, the app *could* create that Purchase
/// via API — but if the same item later appears in the bank feed, it may
/// sit unmatched or get added twice. Missing statement items default to
/// import-required detection -> manual QBO bank-feed action, never silent
/// creation."
public enum BankFeedMissingPostingRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-RECON-MISSING-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Statement line with no matching QBO posting",
        category: .statementLineMissingPosting,
        ruleClass: .categorization,
        page: .bankFeedCleanup,
        accountingPrinciple: "Every real bank/card transaction should eventually appear as a posted entry in QBO. A statement line with no matching Purchase or Bill on the same account means that activity was never entered — cash actually moved, but the books don't reflect it yet.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    private static let nearDateWindowDays = 5

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let statementLines = input.transactions.filter { $0.entityKind == .importedBankStatementLine && !$0.isVoided }

        guard !statementLines.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "No statement imported for this period. Import a bank/card statement to run this check (docs/VOICE_LEDGER_SPEC.md Page 4)."))
        }

        let postedTransactions = input.transactions.filter { ($0.entityKind == .purchase || $0.entityKind == .bill) && !$0.isVoided }

        var findings: [Finding] = []

        for line in statementLines {
            let hasMatch = postedTransactions.contains { posted in
                posted.paymentAccountID == line.paymentAccountID
                    && posted.totalAmount == line.totalAmount
                    && AccountingDate.daysBetween(posted.txnDate, line.txnDate) <= nearDateWindowDays
            }
            guard !hasMatch else { continue }
            guard line.totalAmount.minorUnits != 0 else { continue }
            let exposure = Money(minorUnits: abs(line.totalAmount.minorUnits), currency: line.totalAmount.currency)
            guard exposure >= context.materiality.absoluteFloor else { continue }

            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [line.id]
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online",
                    "Check the bank feed's \"For Review\" queue for this transaction (\(line.vendorName ?? "unknown"), \(line.txnDate), \(line.totalAmount)) — it may already be sitting there unmatched",
                    "If it's in the queue: match or add it from there, using QBO's own bank-feed tools",
                    "If it's not in the queue: enter the transaction manually in QBO"
                ],
                pitfalls: [
                    "Voice Ledger does not create this Purchase automatically — a bank feed item can be added twice if both the app and QBO's own bank feed add it independently",
                    "Confirm this isn't already posted under a different amount or date before adding a new entry"
                ],
                doneCriteria: "A matching Purchase or Bill exists in QBO for this statement line, confirmed on the next sync"
            )

            let action = ProposedAction(
                id: "enter-missing-posting",
                title: "Enter or match this transaction in QBO",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reconciliation("this statement line can be matched during reconciliation once posted"),
                    .reporting("expenses/cash activity reflect this transaction once entered"),
                    .auditTrail("Voice Ledger records your attestation; QBO's own record of the entry is authoritative")
                ],
                reversal: .reversibleManually(procedure: "The entered transaction can be edited or voided in QBO if entered incorrectly")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Statement line not found in QBO — \(line.vendorName ?? "unknown"), \(line.totalAmount)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .high,
                dollarExposure: exposure,
                evidence: [EvidenceItem(transactionID: line.id, highlightedFields: ["amount", "date", "account"])],
                proposedActions: [action],
                provenance: [line.provenance]
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: statementLines.count)
        }
        return .findings(findings)
    }
}
