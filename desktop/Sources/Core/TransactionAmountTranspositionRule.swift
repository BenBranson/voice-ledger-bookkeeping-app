import Foundation

/// `VL-TRANSPOSITION-001`. Owner directive (2026-08-31): "catch transposition
/// errors (like a $450 entry accidentally typed as $540)."
///
/// **Deliberately narrower than "any two amounts whose difference is
/// divisible by 9."** Any adjacent-digit transposition DOES produce a
/// difference that's a multiple of 9 (swap the tens and hundreds digit of
/// 450 → 540: difference is 90 = 9×10) — that direction of the math is real
/// arithmetic, not a heuristic. But the REVERSE isn't true: roughly 1 in 9
/// of ALL possible amount pairs share that property by pure chance, so
/// checking "divisible by 9" against every pair in a ledger would flag a
/// huge number of amounts that have nothing to do with each other — noise,
/// not signal, and a real risk of training the bookkeeper to ignore this
/// rule entirely. This only checks the divisible-by-9 condition WITHIN the
/// same tight candidate window `DuplicatePostedExpenseRule`'s own T3 tier
/// already uses (same vendor, same payment account, within 3 days) — the
/// same "these two postings are already suspicious for being the same
/// event" set an actual duplicate might hide in, just with a typo instead
/// of an exact match. `confidence: .medium` throughout, and the narrative
/// says "may indicate," never "is" — this is a pattern worth a human
/// glance, not proof of an error (CLAUDE.md rule 1: code computes the
/// arithmetic fact; it does not decide this IS a mistake).
public enum TransactionAmountTranspositionRule: Rule {
    static let dateWindowDays = 3

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-TRANSPOSITION-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible transposition error",
        category: .amountTransposition,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Swapping two adjacent digits in a dollar amount (e.g. entering $540 instead of $450) always changes the value by a multiple of 9 — a well-known property of positional number systems, not a coincidence. Two same-vendor, same-account postings within a few days of each other, whose amounts differ by a multiple of 9, are worth comparing against the source document for a possible data-entry error.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let purchases = input.transactions.filter { $0.entityKind == .purchase && !$0.isVoided }

        var findings: [Finding] = []
        var consideredPairs: Set<Set<String>> = []

        for i in 0..<purchases.count {
            for j in (i + 1)..<purchases.count {
                let a = purchases[i]
                let b = purchases[j]
                guard a.id != b.id else { continue }
                if context.gatedTransactionIDs.contains(a.id) || context.gatedTransactionIDs.contains(b.id) { continue }

                // Same exact-vendor-match discipline as
                // `DuplicatePostedExpenseRule` — fuzzy vendor matching is a
                // known false-positive source in this codebase (see that
                // rule's own doc comment); a pair where either side has no
                // vendor is excluded, not guessed toward a match.
                guard let vendorA = a.vendorName, vendorA == b.vendorName else { continue }
                guard let acctA = a.paymentAccountID, acctA == b.paymentAccountID else { continue }
                guard AccountingDate.daysBetween(a.txnDate, b.txnDate) <= dateWindowDays else { continue }

                // Exact-amount pairs are `DuplicatePostedExpenseRule`'s job,
                // not this rule's — a transposition is by definition two
                // DIFFERENT amounts.
                guard a.totalAmount.currency == b.totalAmount.currency else { continue }
                guard a.totalAmount.minorUnits != b.totalAmount.minorUnits else { continue }

                let diffMinorUnits = abs(a.totalAmount.minorUnits - b.totalAmount.minorUnits)
                guard diffMinorUnits > 0, diffMinorUnits % 9 == 0 else { continue }

                let diffMoney = Money(minorUnits: diffMinorUnits, currency: a.totalAmount.currency)
                guard diffMoney >= context.materiality.absoluteFloor else { continue }

                let pairKey: Set<String> = [a.id, b.id]
                guard !consideredPairs.contains(pairKey) else { continue }
                consideredPairs.insert(pairKey)

                let sortedIDs = [a.id, b.id].sorted()
                let findingID = FindingIDGenerator.makeID(
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    sortedAffectedIDs: sortedIDs
                )
                if context.dismissedFindingIDs.contains(findingID) { continue }

                // Larger side first, purely for a stable, readable finding
                // title/evidence order — not a claim about which side (if
                // either) is the mistake.
                let (larger, smaller) = a.totalAmount.minorUnits >= b.totalAmount.minorUnits ? (a, b) : (b, a)

                let procedure = GuidedProcedure(
                    steps: [
                        "Open both transactions in QuickBooks Online and compare each against its underlying bill or receipt for \(vendorA)",
                        "Confirm which amount (if either) matches the source document",
                        "If one was entered wrong, correct it in QBO to match the source document"
                    ],
                    pitfalls: [
                        "Two genuinely different, correctly-entered transactions can coincidentally have amounts that differ by a multiple of 9 — this flags a pattern worth checking, not proof either amount is wrong."
                    ],
                    doneCriteria: "Both amounts have been confirmed against their source documents"
                )
                let action = ProposedAction(
                    id: "review-possible-transposition",
                    title: "Compare both amounts against their source documents",
                    resolution: .manualQBO,
                    guidedProcedure: procedure,
                    consequences: [
                        .reporting("If one amount was mistyped, expenses are misstated by \(diffMoney) until it's corrected")
                    ],
                    reversal: .reversibleManually(procedure: "Correct the amount in QBO if one was entered wrong")
                )

                findings.append(Finding(
                    id: findingID,
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    title: "Possible transposition: \(larger.totalAmount.description) vs \(smaller.totalAmount.description) for \(vendorA)",
                    severity: Severity.derive(dollarExposure: diffMoney, materiality: context.materiality),
                    confidence: .medium,
                    dollarExposure: diffMoney,
                    evidence: [
                        EvidenceItem(
                            transactionID: larger.id,
                            highlightedFields: ["amount", "date"],
                            fieldValues: [
                                "amount": larger.totalAmount.description,
                                "date": Self.formatted(larger.txnDate),
                                "vendor": vendorA
                            ]
                        ),
                        EvidenceItem(
                            transactionID: smaller.id,
                            highlightedFields: ["amount", "date"],
                            fieldValues: [
                                "amount": smaller.totalAmount.description,
                                "date": Self.formatted(smaller.txnDate),
                                "vendor": vendorA
                            ]
                        )
                    ],
                    proposedActions: [action],
                    provenance: [larger.provenance, smaller.provenance],
                    vendorName: vendorA,
                    narrative: "\(vendorA) has two postings within \(dateWindowDays) days of each other, on the same account, for \(larger.totalAmount.description) and \(smaller.totalAmount.description) — a difference of \(diffMoney), which is evenly divisible by 9. That's the arithmetic signature of a transposed digit (e.g. \(larger.totalAmount.description) typed instead of \(smaller.totalAmount.description)). This may indicate a data-entry error — worth comparing both against the source document.",
                    riskIfIgnored: "If one amount was mistyped, this account stays misstated by \(diffMoney) until corrected."
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
        return .pass(coverage: input.coverage, checkedCount: purchases.count)
    }

    private static func formatted(_ date: AccountingDate) -> String {
        date.formatted
    }
}
