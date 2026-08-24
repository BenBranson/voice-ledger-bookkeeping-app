import Foundation

/// `VL-DUP-EXP-001`. docs/phase-0/11_VERTICAL_SLICE.md, docs/phase-0/08_RULE_ENGINE.md §8.8.
///
/// Three tiers: T1 exact match (always active), T2 reference/DocNumber match
/// (conditional on `.customTxnNumbersForPurchases` — §11.2, §8.2b), T3
/// near-date match (always active). Scoped to `Purchase` only, same payment
/// account only — deliberately narrower than "any duplicate" (§8.8's note on
/// `VL-DUP-EXP-002`, a separate rule — `CrossAccountDuplicateExpenseRule`,
/// built and live in `RuleRegistry.all`, not backlog).
public enum DuplicatePostedExpenseRule: MultiTierRule {
    public static let t1 = RuleTier(id: "T1", label: "Exact match", confidence: .high)
    public static let t2 = RuleTier(id: "T2", label: "Reference number match", confidence: .high)
    public static let t3 = RuleTier(id: "T3", label: "Near-date match", confidence: .medium)

    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-DUP-EXP-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible duplicate expense",
        category: .duplicateExpense,
        ruleClass: .categorization,
        page: .page3Transactions,
        accountingPrinciple: "Each economic event should be recorded once. Two postings sharing vendor, amount, date, and payment account are presumptively the same event recorded twice, which overstates expense and understates cash or accounts payable.",
        sourceDependencies: [SourceDependency(entity: .purchase)]
    )

    public static let requirements = DataRequirements(
        entities: [.purchase],
        requiredCoverage: .complete
    )

    /// docs/phase-0/08_RULE_ENGINE.md §8.2b — informational only, never a
    /// coverage gate. T1 and T3 keep the rule fully evaluable on their own.
    public static func tierApplicability(context: RuleContext) -> [TierStatus] {
        [
            TierStatus(
                tier: t1,
                active: true,
                reason: "Always active — exact match on vendor, date, amount, and payment account requires no company setting."
            ),
            TierStatus(
                tier: t2,
                active: context.companyFacts.customTxnNumbersForPurchases,
                reason: context.companyFacts.customTxnNumbersForPurchases
                    ? "Active — this client has Custom Transaction Numbers enabled for vendor/purchases (VendorAndPurchasesPrefs.UseCustomTxnNumbers), so same-DocNumber duplicates can exist."
                    : "Inactive — Custom Transaction Numbers is off in this client's QBO vendor/purchases settings, so QBO enforces unique DocNumber and this tier can never match."
            ),
            TierStatus(
                tier: t3,
                active: true,
                reason: "Always active — near-date match needs no company setting."
            )
        ]
    }

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let purchases = input.transactions.filter { $0.entityKind == .purchase }

        var findings: [Finding] = []
        var consideredPairs: Set<Set<String>> = []

        for i in 0..<purchases.count {
            for j in (i + 1)..<purchases.count {
                let a = purchases[i]
                let b = purchases[j]

                // Exclusion (§11.2): either already voided. This is the
                // intended Branch B resolution path (§11.1) — voiding the
                // duplicate in QBO and resyncing retires the finding via
                // exactly this exclusion, with no write of Voice Ledger's own.
                if a.isVoided || b.isVoided { continue }

                // §8.2a gating: either transaction already explained by a
                // relationship-class finding (e.g. it's actually a
                // credit-card payment, not a candidate expense at all).
                if context.gatedTransactionIDs.contains(a.id) || context.gatedTransactionIDs.contains(b.id) { continue }

                // Gauntlet Loop, Gauntlet A (2026-08-23): a literal `id`
                // collision between two array entries is a data-pipeline
                // anomaly (e.g. a pagination/merge double-fetch of the same
                // QBO row), never two distinct real records — `id` is QBO's
                // own primary key. Without this guard, such a collision
                // produces a phantom "duplicate" finding whose guided
                // procedure would tell a human to void the one real
                // transaction. Unlike vendor-name matching (deliberately
                // exact, not fuzzy — see below), this is a structural
                // invariant, not a trade-off: two rows can never legitimately
                // share a QBO id.
                guard a.id != b.id else { continue }

                // Vendor name match is deliberately EXACT, never fuzzy —
                // same lesson as `VL-DUP-VEND-001`/`VL-COA-DUPACCT-001`:
                // fuzzy matching produces systematic false positives.
                //
                // A pair where BOTH sides have no vendor at all (nil) is
                // deliberately EXCLUDED, not matched — Gauntlet Loop,
                // Gauntlet A (2026-08-23) raised this as worth documenting
                // explicitly rather than leaving as a silent accident of the
                // `guard let`. Two vendorless Purchases matching only on
                // date/amount/account is a weaker signal than two
                // same-named-vendor Purchases matching on the same fields —
                // without a vendor identity, any two unrelated no-vendor
                // transactions could coincidentally share those fields far
                // more easily. Kept conservative (no finding) rather than
                // guessed toward more findings; see
                // `DuplicatePostedExpenseRuleTests.nilVendorPairsAreNotMatched`.
                guard let vendorA = a.vendorName, vendorA == b.vendorName else { continue }
                guard a.totalAmount == b.totalAmount else { continue }

                var matchedTier: RuleTier?

                // T1 — exact: same date, same payment account.
                if a.txnDate == b.txnDate,
                   let acctA = a.paymentAccountID, acctA == b.paymentAccountID {
                    matchedTier = t1
                }

                // T2 — reference: same non-empty DocNumber. Conditional on
                // the company flag — see tierApplicability above.
                if matchedTier == nil,
                   context.companyFacts.customTxnNumbersForPurchases,
                   let docA = a.docNumber, let docB = b.docNumber,
                   !docA.isEmpty, docA == docB {
                    matchedTier = t2
                }

                // T3 — near-date: same payment account, within 3 days.
                if matchedTier == nil,
                   let acctA = a.paymentAccountID, acctA == b.paymentAccountID,
                   AccountingDate.daysBetween(a.txnDate, b.txnDate) <= 3 {
                    matchedTier = t3
                }

                guard let tier = matchedTier else { continue }

                // Gauntlet Loop, Gauntlet A (2026-08-23): compare on
                // MAGNITUDE, not signed value. `a.totalAmount >=
                // absoluteFloor` compared two `Money` values by raw signed
                // minor units — a negative-amount Purchase pair (e.g. a
                // vendor rebate/correction posted directly as a negative
                // Purchase, a real QBO shape distinct from a formal
                // VendorCredit) is always "less than" a positive floor no
                // matter how large its magnitude, silently exempting any
                // negative-amount duplicate from detection entirely. Same
                // exposure/severity derivation this project already uses
                // for VL-FORCED-RECON-001 and VL-REPORT-TIE-001.
                let exposure = a.totalAmount.minorUnits < 0
                    ? Money(minorUnits: -a.totalAmount.minorUnits, currency: a.totalAmount.currency)
                    : a.totalAmount

                // Exclusion (§11.2): below the materiality floor.
                guard exposure >= context.materiality.absoluteFloor else { continue }

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

                let severity = Severity.derive(dollarExposure: exposure, materiality: context.materiality)

                // Gauntlet Loop, Gauntlet A round 3 (2026-08-23): highlighted
                // fields must be branched PER TIER, not built from a shared
                // base with T2 only ever ADDING to it — T2's match condition
                // (above) never reads paymentAccountID and never compares
                // dates, and because T1 runs first and unconditionally
                // claims any pair matching both date AND account, every pair
                // that ever reaches T2 is guaranteed to differ on at least
                // one of {date, paymentAccount} by construction. The old
                // code claimed both as corroborating evidence on every T2
                // finding regardless — not merely incomplete but actively
                // wrong, since the guided procedure asks the human to
                // confirm against the bank statement and a fabricated
                // account/date match could misdirect that check.
                let highlighted: [String]
                switch tier.id {
                case "T2":
                    highlighted = ["amount", "docNumber"]
                default:
                    highlighted = ["amount", "date", "paymentAccount"]
                }

                let evidence = [
                    EvidenceItem(transactionID: a.id, highlightedFields: highlighted),
                    EvidenceItem(transactionID: b.id, highlightedFields: highlighted)
                ]

                // Gauntlet Loop, Gauntlet A round 4 (2026-08-23): the
                // original wording named `b.id` as "the duplicate Purchase"
                // as settled fact — but which of `a`/`b` is which is purely
                // an artifact of array-traversal order (i < j), never a real
                // signal (no created-timestamp, no "which account is
                // correct," nothing). The same real pair, fed in the
                // opposite array order, would have named the OTHER
                // transaction as "the duplicate" — a person following the
                // step literally could void either one depending on
                // incidental pagination/array order from the same
                // underlying data. Rewritten to present both candidates
                // neutrally and let the bank-statement check (which the
                // procedure already requires) — not array position —
                // determine which posting, if either, gets voided.
                let procedure = GuidedProcedure(
                    steps: [
                        "Open QuickBooks Online",
                        "Go to Expenses, find the vendor \(vendorA)",
                        "Locate both Purchases (\(a.id) and \(b.id)) — they are presumptively the same event recorded twice, not yet confirmed which one (if either) is the error",
                        "Confirm with the bank statement whether one or two withdrawals actually occurred",
                        "If one: void whichever of the two postings does NOT match a real withdrawal, keeping the one that does"
                    ],
                    pitfalls: [
                        "Void, not delete — voiding preserves the audit trail; deleting does not",
                        "Voice Ledger cannot tell which of the two postings is the error — only the bank statement can. Do not assume the second one entered is the duplicate.",
                        "Voice Ledger cannot verify this happened until the next sync"
                    ],
                    doneCriteria: "Whichever of the two postings didn't match a real withdrawal shows as Voided in QBO, TotalAmt $0.00"
                )

                let action = ProposedAction(
                    id: "void-duplicate",
                    title: "Void the duplicate in QBO",
                    resolution: .manualQBO,
                    guidedProcedure: procedure,
                    consequences: [
                        .reconciliation("removes \(exposure) from uncleared activity, once completed in QBO"),
                        .reporting("expenses decrease by \(exposure), once completed in QBO"),
                        .auditTrail("Voice Ledger records your attestation; QBO's own record of the void is authoritative")
                    ],
                    reversal: .reversibleManually(procedure: "Un-void in QBO if done in error")
                )

                findings.append(Finding(
                    id: findingID,
                    ruleID: identity.id,
                    ruleVersion: identity.version,
                    realmID: input.realmID,
                    period: input.period,
                    // Gauntlet Loop, Gauntlet A round 2 (2026-08-23): must
                    // read `exposure` (magnitude-corrected), not
                    // `a.totalAmount` (raw signed) — round 1's negative-
                    // amount fix updated dollarExposure/severity/consequences
                    // but missed this line, so a negative-amount pair's
                    // title showed a negative number contradicting its own
                    // (correctly positive) dollarExposure field right next
                    // to it in the same Finding.
                    title: "Possible duplicate expense — \(exposure)",
                    severity: severity,
                    confidence: tier.confidence,
                    dollarExposure: exposure,
                    evidence: evidence,
                    proposedActions: [action],
                    provenance: [a.provenance, b.provenance],
                    // Gauntlet Loop, Gauntlet A (2026-08-23): every sibling
                    // rule that has a clear single vendor already sets this
                    // (CreditCardPaymentMiscodedRule, PayrollLumpSumRule,
                    // UncategorizedTransactionRule,
                    // VendorDescriptionMismatchRule,
                    // UnappliedVendorCreditRule) — this rule's entire match
                    // key IS the vendor, and yet it was the one rule that
                    // never wired this. Without it, Client Memory's "Always
                    // Dismiss for <vendor>" (`ClientMemoryRule.matches`,
                    // which unconditionally returns false for a nil
                    // `findingVendorName`) could never suppress a recurring
                    // false positive from this rule on any later sync — the
                    // owner's explicit "stop flagging this" instruction
                    // would be silently ignored forever.
                    vendorName: vendorA
                ))
            }
        }

        if findings.isEmpty {
            // §8.1: a rule must never claim .pass on incomplete coverage.
            // The engine's own outcome-validation step (RuleEngineActor
            // step 5) would catch this and downgrade it if the rule got it
            // wrong, but the rule itself should not rely on that backstop —
            // see DuplicatePostedExpenseRuleTests.case05PartialCoverageNeverPasses,
            // which caught exactly this before this guard was added.
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: purchases.count)
        }
        return .findings(findings)
    }
}
