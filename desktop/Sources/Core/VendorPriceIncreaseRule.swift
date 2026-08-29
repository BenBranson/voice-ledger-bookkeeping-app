import Foundation

/// `VL-VEND-PRICE-001`. docs/phase-0/08_RULE_ENGINE.md's backlog table:
/// "Vendor price increases."
///
/// **Also covers `VL-SUB-INCREASE-001` ("Recurring subscription
/// increased") under this one rule ID, deliberately not as a second rule.**
/// The two backlog items describe the exact same underlying, computable
/// fact — a vendor charging more per transaction than it did last period,
/// at a stable transaction count — through the exact same mechanism there
/// is only one honest way to detect from Purchase data. Shipping them as
/// two separate `Rule` types would mean the same evidence produces two
/// findings with two different rule IDs for the bookkeeper to dismiss
/// separately, which is worse than one, not more thorough. If a genuinely
/// distinct signal for "recurring" (e.g. a detected monthly cadence, not
/// just "same count both periods") gets built later, it can graduate into
/// its own rule; until then this is the real, single check.
///
/// **`VL-SUB-UNUSED-001` ("Recurring subscription appears unused") is
/// intentionally NOT built** — "unused" is a usage-data question (is
/// someone logging into this software, is this service being consumed),
/// and Voice Ledger has no API access to any vendor's usage data, only
/// QBO's own financial postings. There is no honest signal in Purchase
/// data alone that means "unused" rather than merely "still being
/// charged" (which is the normal, correct state for an active
/// subscription). Left as backlog, same posture as `VL-BS-SUSPENSE-001`
/// and `VL-COA-DUPACCT-001` — investigated, not shipped on a guess.
///
/// **Requires a STABLE transaction count** between the two periods before
/// comparing average amount — this is what distinguishes "the price went
/// up" from "we just bought more of it," which is a real, different, and
/// much less noteworthy fact. A vendor billed twice as often at the same
/// per-transaction price would otherwise false-positive as a 100% price
/// increase under a naive total-spend comparison.
public enum VendorPriceIncreaseRule: Rule {
    /// A per-transaction average at or above this fraction higher than
    /// last period's is flagged. 15% is deliberately above ordinary
    /// price creep (a few percent here and there is normal and not worth
    /// a bookkeeper's attention every month) but well below what a
    /// genuine repricing or billing error looks like.
    static let minimumIncreaseRatio: Double = 0.15

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-VEND-PRICE-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Vendor is charging more per transaction than last period",
        category: .vendorPriceIncrease,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "When a vendor bills the same number of times as last period but the average amount per charge is materially higher, that's a real price change worth confirming — either a legitimate rate increase (worth knowing about and budgeting for) or a billing error (worth catching before it repeats next month too).",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        guard !input.priorPeriodTransactions.isEmpty else {
            return .cannotEvaluate(.partialCoverage(reason: "Prior period's purchases not loaded for this sync — this check needs last period's data to compare against."))
        }

        let currentByVendor = Self.groupByVendor(input.transactions)
        let priorByVendor = Self.groupByVendor(input.priorPeriodTransactions)

        var findings: [Finding] = []
        for (vendorName, currentGroup) in currentByVendor.sorted(by: { $0.key < $1.key }) {
            guard let priorGroup = priorByVendor[vendorName] else { continue }
            guard currentGroup.count == priorGroup.count else { continue }

            let currentTotal = currentGroup.reduce(Money.zero) { $0 + $1.totalAmount }
            let priorTotal = priorGroup.reduce(Money.zero) { $0 + $1.totalAmount }
            guard priorTotal.minorUnits > 0 else { continue }

            let ratio = Double(currentTotal.minorUnits - priorTotal.minorUnits) / Double(priorTotal.minorUnits)
            guard ratio >= minimumIncreaseRatio else { continue }

            let exposure = currentTotal - priorTotal
            guard exposure >= context.materiality.absoluteFloor else { continue }

            let sortedIDs = currentGroup.map(\.id).sorted()
            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: sortedIDs
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let currentAvg = Money(minorUnits: currentTotal.minorUnits / Int64(currentGroup.count), currency: currentTotal.currency)
            let priorAvg = Money(minorUnits: priorTotal.minorUnits / Int64(priorGroup.count), currency: priorTotal.currency)
            let percentText = String(format: "%.0f%%", ratio * 100)

            let procedure = GuidedProcedure(
                steps: [
                    "Compare this period's \(currentGroup.count) charge\(currentGroup.count == 1 ? "" : "s") from \(vendorName) (averaging \(currentAvg)) against last period's \(priorGroup.count) (averaging \(priorAvg))",
                    "Check the vendor's invoice or billing notice for a rate change",
                    "If it's a real price increase, no correction is needed — just confirmed and noted for budgeting",
                    "If it looks like a billing error, contact the vendor and correct the transaction in QBO once resolved"
                ],
                pitfalls: [
                    "A one-time surcharge or a different item/service from the same vendor can look like a price increase without being one — check what was actually billed, not just the total"
                ],
                doneCriteria: "The increase has been confirmed as a real rate change or corrected as a billing error"
            )

            let action = ProposedAction(
                id: "review-vendor-price-increase",
                title: "Confirm this vendor's rate increase",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("If unconfirmed, this vendor's cost basis for budgeting stays understated by \(exposure) per period going forward")
                ],
                reversal: .reversibleManually(procedure: "No QBO change is proposed by this finding itself — any correction happens directly in QBO if a billing error is found")
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "\(vendorName) charged \(percentText) more than last period",
                severity: Severity.derive(dollarExposure: exposure, materiality: context.materiality),
                confidence: .medium,
                dollarExposure: exposure,
                evidence: currentGroup.map { txn in
                    EvidenceItem(
                        transactionID: txn.id,
                        highlightedFields: ["amount"],
                        fieldValues: [
                            "vendorName": vendorName,
                            "amount": txn.totalAmount.description,
                            "currentAverage": currentAvg.description,
                            "priorAverage": priorAvg.description,
                            "percentIncrease": percentText
                        ]
                    )
                },
                proposedActions: [action],
                provenance: currentGroup.map(\.provenance),
                vendorName: vendorName,
                narrative: "\(vendorName) billed \(currentGroup.count) time\(currentGroup.count == 1 ? "" : "s") this period averaging \(currentAvg), up \(percentText) from last period's \(priorAvg) average across the same number of charges.",
                riskIfIgnored: "This increase stays unconfirmed as either a legitimate rate change or a billing error until reviewed."
            ))
        }

        guard findings.isEmpty else {
            return .findings(findings)
        }
        return .pass(coverage: input.coverage, checkedCount: currentByVendor.count)
    }

    private static func groupByVendor(_ transactions: [LedgerTransaction]) -> [String: [LedgerTransaction]] {
        var byVendor: [String: [LedgerTransaction]] = [:]
        for transaction in transactions where !transaction.isVoided && transaction.vendorName != nil && transaction.entityKind == .purchase {
            byVendor[transaction.vendorName!, default: []].append(transaction)
        }
        return byVendor
    }
}
