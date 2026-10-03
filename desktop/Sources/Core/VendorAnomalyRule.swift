import Foundation

/// `VL-VEND-ANOMALY-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Unusual vendor name, amount, or timing." **A real slice, not the
/// whole spec item** — this app has no cross-period transaction history
/// tracked anywhere (each sync only pulls the current period), so
/// "unusual timing" (e.g. a vendor never used before, or not used in
/// months) has no data to compute from yet. What IS built: a transaction
/// whose amount is a statistical outlier against the SAME vendor's OTHER
/// transactions in the SAME period — a real signal computable entirely
/// from data already synced, no new capability needed. "Unusual name" is
/// not attempted either — that would mean judging whether a vendor name
/// itself looks suspicious, which has no deterministic signal to key off
/// (unlike an amount, which is just arithmetic).
public enum VendorAnomalyRule: Rule {
    /// A vendor needs at least this many transactions in the period
    /// before "the median" means anything — with only 2 points, an
    /// "outlier" is just "the bigger one," not a real anomaly signal.
    static let minimumTransactionsForBaseline = 3
    /// A transaction at or above this multiple of its vendor's median
    /// amount this period is flagged. Deliberately conservative (most
    /// legitimate vendor relationships have SOME real variation in
    /// invoice size) — 3x is a large enough jump that it's worth a look,
    /// not a routine fluctuation.
    static let outlierMultiple: Double = 3.0

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-VEND-ANOMALY-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Unusually large amount for this vendor",
        category: .vendorAmountAnomaly,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "A transaction several times larger than the same vendor's typical amount this period is worth a second look — it could be a data-entry error (an extra digit, a decimal point in the wrong place), a duplicate that didn't match on exact amount, or a genuine one-time charge that's correctly entered but still worth confirming.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    /// How far back "normal for this vendor" looks when history is loaded.
    static let historyMonths = 12

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        // Money going out only: `vendorName` also carries the customer on invoices and payments.
        func isVendorCharge(_ t: LedgerTransaction) -> Bool { !t.isVoided && t.vendorName != nil && (t.entityKind == .purchase || t.entityKind == .bill) }
        let candidates = input.transactions.filter(isVendorCharge)
        var byVendor: [String: [LedgerTransaction]] = [:]
        for transaction in candidates {
            byVendor[transaction.vendorName!, default: []].append(transaction)
        }
        // Rewritten 2026-10-02 (owner test): "normal" used to be the median of the SAME month's
        // charges including the one being judged, so three bills in one month, two of them
        // duplicates, made the third look 4x "normal". Now the baseline is this vendor's charges
        // over the prior 12 months plus this month's OTHER charges, never the charge itself or
        // its exact duplicates (same amount, same day; the duplicate rules own those).
        var earliest = input.period
        for _ in 0..<Self.historyMonths { earliest = earliest.previousMonth }
        let earliestDate = AccountingDate(year: earliest.year, month: earliest.month, day: 1)
        let periodStart = AccountingDate(year: input.period.year, month: input.period.month, day: 1)
        var historyByVendor: [String: [Int64]] = [:]
        for t in input.historyTransactions where isVendorCharge(t) && t.txnDate >= earliestDate && t.txnDate < periodStart {
            historyByVendor[t.vendorName!, default: []].append(t.totalAmount.minorUnits)
        }

        var findings: [Finding] = []
        for (vendorName, group) in byVendor.sorted(by: { $0.key < $1.key }) {
            let history = historyByVendor[vendorName] ?? []
            for transaction in group.sorted(by: { $0.id < $1.id }) {
                let others = group.filter { $0.id != transaction.id && !($0.totalAmount == transaction.totalAmount && $0.txnDate == transaction.txnDate) }
                let baseline = (history + others.map(\.totalAmount.minorUnits)).sorted()
                guard baseline.count >= minimumTransactionsForBaseline else { continue }
                let median = Self.median(of: baseline)
                guard median > 0 else { continue }
                let ratio = Double(transaction.totalAmount.minorUnits) / Double(median)
                guard ratio >= outlierMultiple else { continue }
                guard transaction.totalAmount >= context.materiality.absoluteFloor else { continue }
                let basis = history.isEmpty ? "\(baseline.count) other charges this month" : "\(baseline.count) charges over the last \(Self.historyMonths) months"

                let findingID = FindingIDGenerator.makeID(
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    sortedAffectedIDs: [transaction.id]
                )
                if context.dismissedFindingIDs.contains(findingID) { continue }

                let medianMoney = Money(minorUnits: median, currency: transaction.totalAmount.currency)
                let procedure = GuidedProcedure(
                    steps: [
                        "Open the transaction in QuickBooks Online and confirm the amount is correct — check for an extra digit or misplaced decimal point",
                        "Compare against the underlying bill or receipt for \(vendorName) to confirm \(transaction.totalAmount) is the real amount",
                        "If correct, no further action is needed — this may just be a genuinely larger charge from this vendor this period"
                    ],
                    pitfalls: [
                        "A real one-time large purchase from a normally-small vendor is not itself a mistake — this flag means 'different from usual,' not 'wrong'"
                    ],
                    doneCriteria: "The amount has been confirmed against the source document"
                )

                let action = ProposedAction(
                    id: "review-vendor-amount-anomaly",
                    title: "Confirm this amount against the source document",
                    resolution: .manualQBO,
                    guidedProcedure: procedure,
                    consequences: [
                        .reporting("If this is a data-entry error, expenses are currently overstated by the difference between \(transaction.totalAmount) and the correct amount")
                    ],
                    reversal: .reversibleManually(procedure: "Correct the amount in QBO if it was entered wrong")
                )

                findings.append(Finding(
                    id: findingID,
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    title: "Unusually large amount for \(vendorName) — \(transaction.totalAmount)",
                    severity: Severity.derive(dollarExposure: transaction.totalAmount, materiality: context.materiality),
                    confidence: .medium,
                    dollarExposure: transaction.totalAmount,
                    evidence: [EvidenceItem(
                        transactionID: transaction.id,
                        highlightedFields: ["amount"],
                        fieldValues: [
                            "vendorName": vendorName,
                            "amount": transaction.totalAmount.description,
                            "date": transaction.txnDate.formatted,
                            "vendorTypicalAmount": medianMoney.description,
                            "comparedWith": basis
                        ]
                    )],
                    proposedActions: [action],
                    provenance: [transaction.provenance],
                    vendorName: vendorName,
                    narrative: "This \(transaction.totalAmount) charge from \(vendorName) is at least \(Int(outlierMultiple))x this vendor's typical \(medianMoney), based on \(basis).",
                    riskIfIgnored: "If this is a data-entry error, it stays overstating expenses by the difference until confirmed against the source document."
                ))
            }
        }

        guard findings.isEmpty else {
            return .findings(findings)
        }
        guard case .complete = input.coverage else {
            return .cannotEvaluate(.partialCoverage(reason: {
                if case .partial(let reason) = input.coverage { return reason }
                return "unknown"
            }()))
        }
        return .pass(coverage: input.coverage, checkedCount: candidates.count)
    }

    static func median(of sortedAmounts: [Int64]) -> Int64 {
        guard !sortedAmounts.isEmpty else { return 0 }
        let count = sortedAmounts.count
        if count % 2 == 1 {
            return sortedAmounts[count / 2]
        }
        return (sortedAmounts[count / 2 - 1] + sortedAmounts[count / 2]) / 2
    }
}
