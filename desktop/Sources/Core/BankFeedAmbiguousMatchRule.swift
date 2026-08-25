import Foundation

/// `VL-RECON-AMBIGUOUS-001`. docs/VOICE_LEDGER_SPEC.md Page 5
/// (Reconciliation, Type B+C): "...identifies unmatched and duplicate
/// items." `BankFeedMissingPostingRule` (`VL-RECON-MISSING-001`) is the
/// unmatched half; this is the duplicate half — but at the
/// statement-to-ledger boundary, not the posted-ledger-to-itself boundary
/// `DuplicatePostedExpenseRule` (`VL-DUP-EXP-001`) already covers.
///
/// **What this actually detects:** one imported statement line whose
/// (account, amount, near-date) matches 2 or more posted `Purchase`/`Bill`
/// records equally well — the exact same predicate
/// `BankFeedMissingPostingRule` uses to decide "matched," just counting
/// multiplicity instead of presence. Reconciliation can't tell which of
/// the matches this statement line actually clears. **This does not claim
/// the posted transactions ARE duplicates of each other** — it flags a
/// reconciliation ambiguity for a human to resolve, at `.medium`
/// confidence, never auto-resolved.
public enum BankFeedAmbiguousMatchRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-RECON-AMBIGUOUS-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Statement line matches more than one QBO posting",
        category: .statementLineAmbiguousMatch,
        ruleClass: .categorization,
        page: .bankFeedCleanup,
        accountingPrinciple: "Reconciliation assumes a one-to-one match between a bank line and a posted entry. When one statement line matches multiple posted transactions equally well, either one of those postings is a genuine duplicate, or two unrelated transactions coincidentally share the same account, amount, and date — either way, reconciliation cannot proceed on this line until a human picks the real match.",
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
            let matches = postedTransactions.filter { posted in
                posted.paymentAccountID == line.paymentAccountID
                    && posted.totalAmount == line.totalAmount
                    && AccountingDate.daysBetween(posted.txnDate, line.txnDate) <= nearDateWindowDays
            }
            guard matches.count > 1 else { continue }
            guard line.totalAmount.minorUnits != 0 else { continue }
            let exposure = Money(minorUnits: abs(line.totalAmount.minorUnits), currency: line.totalAmount.currency)
            guard exposure >= context.materiality.absoluteFloor else { continue }

            let sortedMatchIDs = matches.map(\.id).sorted()
            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: [line.id] + sortedMatchIDs
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let matchDescriptions = matches.map { "\($0.vendorName ?? "unknown"), \($0.txnDate.formatted), \($0.totalAmount) (id \($0.id))" }.joined(separator: "; ")

            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online",
                    "This statement line (\(line.vendorName ?? "unknown"), \(line.txnDate.formatted), \(line.totalAmount)) matches \(matches.count) posted transactions equally well: \(matchDescriptions)",
                    "Confirm which posted transaction this statement line actually clears during reconciliation",
                    "If more than one of the posted transactions represents the same real charge, void or delete the actual duplicate in QBO — never both"
                ],
                pitfalls: [
                    "Do not assume the earliest or first-listed match is correct — check dates and memos in QBO directly",
                    "If none of the matches is a true duplicate (e.g. two genuinely separate purchases of the same amount on the same day), no action is needed beyond manually matching the correct one during reconciliation"
                ],
                doneCriteria: "The statement line is matched to exactly one posted transaction during reconciliation, and any real duplicate posting has been voided in QBO"
            )

            let action = ProposedAction(
                id: "resolve-ambiguous-match",
                title: "Resolve which posting this statement line matches",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reconciliation("reconciliation cannot cleanly proceed on this line until the ambiguity is resolved"),
                    .reporting("if one of the matches is a real duplicate, expenses are overstated until it's voided"),
                    .auditTrail("Voice Ledger records your attestation; QBO's own record of any void is authoritative")
                ],
                reversal: .reversibleManually(procedure: "Any transaction voided in QBO to resolve this can be un-voided or re-entered if the resolution was wrong")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Statement line matches \(matches.count) postings — \(line.vendorName ?? "unknown"), \(line.totalAmount)",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: exposure,
                evidence: [EvidenceItem(
                    transactionID: line.id,
                    highlightedFields: ["amount", "date", "account"],
                    fieldValues: ["amount": line.totalAmount.description, "date": line.txnDate.formatted, "vendor": line.vendorName ?? "unknown", "matchCount": "\(matches.count)"]
                )],
                proposedActions: [action],
                provenance: [line.provenance],
                vendorName: line.vendorName,
                narrative: "A \(line.totalAmount) statement line\(line.vendorName.map { " from \($0)" } ?? "") dated \(line.txnDate.formatted) matches \(matches.count) posted transactions in QBO equally well (same account, amount, within \(Self.nearDateWindowDays) days) — reconciliation can't tell which one it actually clears.",
                riskIfIgnored: "If one of these matches is genuinely a duplicate posting, expenses stay overstated by \(line.totalAmount) until it's found and voided; if not, reconciliation for this line will keep stalling on an ambiguous match."
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
