import Foundation

/// Owner decision 2026-09-29 (docs/VOICE_LEDGER_HANDOFF.md): a lower-
/// confidence tier for duplicates the exact rules miss — payee spelled
/// with different case/punctuation/"Inc"/"LLC", or posted up to 5 days
/// apart. Payee matching reuses `DuplicateVendorRule.normalize`
/// (normalized-exact); true typo-tolerant fuzzy matching stays rejected.
/// Pairs an exact rule already reports are skipped so nothing is flagged
/// twice.
public enum NearDuplicateTransactionRule: Rule {
    static let windowDays = 5

    private static let kinds: [QBOEntityKind] = [.purchase, .bill, .invoice, .payment]

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-DUP-NEAR-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible near-duplicate transaction",
        category: .duplicateExpense,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "The same charge is often entered twice with the payee typed slightly differently (\"Home Depot\" vs \"The Home Depot, Inc.\") or a few days apart when one copy comes from the bank feed and one is keyed by hand. Two same-type transactions for the identical amount, to the same payee after normalizing name formatting, within 5 days are worth a look before the books close.",
        sourceDependencies: [SourceDependency(entity: .purchase), SourceDependency(entity: .bill), SourceDependency(entity: .invoice), SourceDependency(entity: .payment)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase, .bill, .invoice, .payment],
        requiredCoverage: .complete
    )

    /// What the exact duplicate rules already report for this pair.
    static func alreadyCoveredByExactRule(_ a: LedgerTransaction, _ b: LedgerTransaction, days: Int) -> Bool {
        guard a.vendorName == b.vendorName else { return false }
        return a.entityKind == .purchase ? days <= 3 : days == 0
    }

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let candidates = input.transactions.filter { kinds.contains($0.entityKind) && !$0.isVoided && $0.vendorName != nil }
        var findings: [Finding] = []

        let groups = Dictionary(grouping: candidates) { "\($0.entityKind.rawValue)|\($0.totalAmount.minorUnits)|\($0.totalAmount.currency)" }
        for (_, group) in groups where group.count > 1 {
            let sorted = group.sorted { ($0.txnDate, $0.id) < ($1.txnDate, $1.id) }
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    let a = sorted[i]
                    let b = sorted[j]
                    guard a.id != b.id else { continue }
                    if context.gatedTransactionIDs.contains(a.id) || context.gatedTransactionIDs.contains(b.id) { continue }
                    let days = AccountingDate.daysBetween(a.txnDate, b.txnDate)
                    guard days <= windowDays else { continue }
                    guard let nameA = a.vendorName, let nameB = b.vendorName else { continue }
                    let keyA = DuplicateVendorRule.normalize(nameA)
                    guard !keyA.isEmpty, keyA == DuplicateVendorRule.normalize(nameB) else { continue }
                    guard a.totalAmount >= context.materiality.absoluteFloor else { continue }
                    guard !alreadyCoveredByExactRule(a, b, days: days) else { continue }

                    let findingID = FindingIDGenerator.makeID(
                        ruleID: identity.id,
                        ruleVersion: identity.version,
                        realmID: input.realmID,
                        period: input.period,
                        sortedAffectedIDs: [a.id, b.id].sorted()
                    )
                    if context.dismissedFindingIDs.contains(findingID) { continue }
                    findings.append(finding(id: findingID, a: a, b: b, days: days, input: input, context: context))
                }
            }
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
        return .findings(findings.sorted { $0.id < $1.id })
    }

    private static func noun(_ kind: QBOEntityKind) -> String {
        switch kind {
        case .bill: return "bill"
        case .invoice: return "invoice"
        case .payment: return "customer payment"
        default: return "expense"
        }
    }

    private static func finding(id: String, a: LedgerTransaction, b: LedgerTransaction, days: Int, input: NormalizedDataSet, context: RuleContext) -> Finding {
        let nameA = a.vendorName ?? ""
        let nameB = b.vendorName ?? ""
        let kind = noun(a.entityKind)
        let payeeDescription = nameA == nameB ? nameA : "\"\(nameA)\" and \"\(nameB)\""
        let gap = days == 0 ? "on the same day" : "\(days) day\(days == 1 ? "" : "s") apart"

        let procedure = GuidedProcedure(
            steps: [
                "Open both transactions in QuickBooks Online (\(a.id) on \(a.txnDate.formatted), \(b.id) on \(b.txnDate.formatted))",
                "Compare the memo, reference number, and attached receipt on each",
                "If they're the same \(kind) entered twice: void the copy that did NOT come from the bank feed",
                nameA == nameB ? "If they're genuinely separate (e.g. two identical orders), dismiss this finding" : "If the payee names are two records for one vendor, merge the vendor records too"
            ],
            pitfalls: [
                "A lower-confidence match: identical recurring charges (rent, subscriptions) can legitimately repeat — check the dates against the billing cycle",
                "Void, not delete — voiding preserves the audit trail"
            ],
            doneCriteria: "Only one of the two transactions remains active, or you've confirmed both are genuine"
        )
        let action = ProposedAction(
            id: "review-near-duplicate",
            title: "Compare both and void the duplicate in QBO",
            resolution: .manualQBO,
            guidedProcedure: procedure,
            consequences: [
                .reporting("the \(kind) total drops by \(a.totalAmount) if one copy is voided"),
                .auditTrail("Voice Ledger records your attestation; QBO's own record of the void is authoritative")
            ],
            reversal: .reversibleManually(procedure: "Un-void in QBO if done in error")
        )

        return Finding(
            id: id,
            ruleID: identity.id,
            ruleVersion: identity.version,
            realmID: input.realmID,
            period: input.period,
            title: "Possible near-duplicate \(kind) — \(a.totalAmount)",
            severity: Severity.derive(dollarExposure: a.totalAmount, materiality: context.materiality),
            confidence: .low,
            dollarExposure: a.totalAmount,
            evidence: [
                EvidenceItem(transactionID: a.id, highlightedFields: ["amount", "date", "vendor"], fieldValues: ["amount": a.totalAmount.description, "date": a.txnDate.formatted, "vendor": nameA]),
                EvidenceItem(transactionID: b.id, highlightedFields: ["amount", "date", "vendor"], fieldValues: ["amount": b.totalAmount.description, "date": b.txnDate.formatted, "vendor": nameB])
            ],
            proposedActions: [action],
            provenance: [a.provenance, b.provenance],
            vendorName: nameA,
            narrative: "Two \(kind)s to \(payeeDescription) for \(a.totalAmount) were posted \(gap). The exact-match checks didn't pair them because \(nameA == nameB ? "they're more than a few days apart" : "the payee is spelled differently"), but they may be the same \(kind) entered twice.",
            riskIfIgnored: "If this is a duplicate, the books overstate this \(kind) total by \(a.totalAmount) until one copy is voided."
        )
    }
}
