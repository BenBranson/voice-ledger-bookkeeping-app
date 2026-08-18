import Foundation

/// `VL-VENDOR-MISMATCH-001`. docs/phase-0/08_RULE_ENGINE.md §8.8: "Statement's
/// original bank description diverges from QBO's cleaned-up vendor name."
/// Previously blocked on the Import Bridge (Universal Ingestion §9), which
/// now exists — this rule reuses the exact same statement-to-posted matching
/// `VL-RECON-MISSING-001` already does (same account, amount, within the
/// near-date window), but for the OPPOSITE case: a statement line that DOES
/// have a match, where the raw bank description and QBO's vendor name for
/// that match don't obviously refer to the same payee.
///
/// **Conservative by design, same lesson as `VL-DUP-VEND-001` and
/// `VL-COA-DUPACCT-001`'s false-positive finding:** flags only when the two
/// names share ZERO normalized word in common — "AMEX EPAYMENT 8827" vs "VL
/// Spike Amex" share "amex" and do NOT match; "SQ *COFFEE SHOP" vs "Random
/// Vendor LLC" share nothing and DO match. A single shared word is enough to
/// stay silent — this is meant to catch a QBO auto-match gone genuinely
/// wrong (matched to the wrong vendor entirely), not to nitpick every
/// bank-vs-books wording difference.
public enum VendorDescriptionMismatchRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-VENDOR-MISMATCH-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Statement description doesn't match QBO's vendor name",
        category: .vendorDescriptionMismatch,
        ruleClass: .categorization,
        page: .page3Transactions,
        accountingPrinciple: "A posted transaction's vendor should be the entity that actually appears on the bank statement. If a statement line was matched to a QBO posting with a completely unrelated vendor name, the match itself may be wrong — a real error, not just a wording difference.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    private static let nearDateWindowDays = 5
    private static let stopWords: Set<String> = ["the", "inc", "llc", "corp", "co", "ltd", "company", "and"]

    static func normalizedWords(_ text: String) -> Set<String> {
        let lowered = text.lowercased()
        let cleaned = lowered.replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
        let words = cleaned.split(separator: " ").map(String.init).filter { $0.count >= 3 && !stopWords.contains($0) }
        return Set(words)
    }

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let statementLines = input.transactions.filter { $0.entityKind == .importedBankStatementLine && !$0.isVoided }
        guard !statementLines.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "No statement imported for this period. Import a bank/card statement to run this check."))
        }

        let postedTransactions = input.transactions.filter { ($0.entityKind == .purchase || $0.entityKind == .bill) && !$0.isVoided }

        var findings: [Finding] = []

        for line in statementLines {
            guard let statementDescription = line.vendorName, !statementDescription.isEmpty else { continue }
            guard context.gatedTransactionIDs.contains(line.id) == false else { continue }

            let match = postedTransactions.first { posted in
                posted.paymentAccountID == line.paymentAccountID
                    && posted.totalAmount == line.totalAmount
                    && AccountingDate.daysBetween(posted.txnDate, line.txnDate) <= nearDateWindowDays
            }
            guard let match, let postedVendor = match.vendorName, !postedVendor.isEmpty else { continue }

            let statementWords = normalizedWords(statementDescription)
            let postedWords = normalizedWords(postedVendor)
            guard !statementWords.isEmpty, !postedWords.isEmpty else { continue }
            guard statementWords.isDisjoint(with: postedWords) else { continue }

            guard line.totalAmount >= context.materiality.absoluteFloor else { continue }

            let sortedIDs = [line.id, match.id].sorted()
            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: sortedIDs
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online",
                    "Find the posted transaction for \(postedVendor), \(match.txnDate), \(match.totalAmount)",
                    "Compare it against the bank statement description: \"\(statementDescription)\"",
                    "Confirm whether this is really \(postedVendor), or whether QBO (or a prior bookkeeper) matched it to the wrong vendor",
                    "If wrong: correct the vendor on the posted transaction in QBO"
                ],
                pitfalls: [
                    "Some legitimate vendors process payments under a different name than their storefront (a payment processor's own descriptor, a parent company name) — confirm before assuming an error"
                ],
                doneCriteria: "The posted transaction's vendor is confirmed correct, or corrected in QBO"
            )

            let action = ProposedAction(
                id: "review-vendor-mismatch",
                title: "Confirm the vendor match against the statement",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("per-vendor totals become accurate once confirmed or corrected"),
                    .auditTrail("Voice Ledger records your attestation; QBO's own record of the correction, if any, is authoritative")
                ],
                reversal: .reversibleManually(procedure: "The vendor field can be changed again in QBO if corrected wrongly")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Statement description doesn't match \(postedVendor) — \"\(statementDescription)\"",
                severity: Severity.derive(dollarExposure: line.totalAmount, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: line.totalAmount,
                evidence: [
                    EvidenceItem(transactionID: line.id, highlightedFields: ["description"]),
                    EvidenceItem(transactionID: match.id, highlightedFields: ["vendor"])
                ],
                proposedActions: [action],
                provenance: [line.provenance, match.provenance],
                vendorName: postedVendor
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
