import Foundation

/// `VL-DUP-VEND-001`. docs/phase-0/08_RULE_ENGINE.md §8.8: duplicate vendor
/// records — the same real-world vendor entered twice under slightly
/// different names, which scatters that vendor's expense history across two
/// records and breaks any per-vendor analysis (totals, 1099 prep, price
/// tracking).
///
/// **Matching is deliberately conservative — normalized-EXACT, not fuzzy.**
/// `VL-COA-DUPACCT-001`'s investigation (docs/phase-0/08_RULE_ENGINE.md §8.8,
/// same date) found that naive same-name matching on real sandbox data
/// produces systematic false positives from QBO's own legitimate patterns.
/// Vendors don't have that specific failure mode (there's no "same vendor
/// name, different parent" pattern the way accounts have income/COGS
/// pairs), but a fuzzy/similarity-threshold matcher would still risk
/// flagging two genuinely different small vendors with similar names. This
/// rule only flags vendors whose names are IDENTICAL after normalizing case,
/// whitespace, punctuation, and common business-entity suffixes (Inc, LLC,
/// Corp, Co) — lower recall (a typo'd duplicate might not normalize to an
/// exact match) in exchange for zero false positives, which is the right
/// tradeoff for something that fires with no human review before it's shown.
public enum DuplicateVendorRule: Rule {
    public static let identity = RuleIdentity(
        id: RuleID(rawValue: "VL-DUP-VEND-001"),
        version: RuleVersion(major: 1, minor: 0, patch: 0),
        title: "Possible duplicate vendor record",
        category: .duplicateVendor,
        ruleClass: .categorization,
        page: .cleanupAssessment,
        accountingPrinciple: "Two vendor records for the same real-world payee split that vendor's transaction history across two IDs, which understates any per-vendor total, misses 1099 aggregation thresholds, and hides price trends over time.",
        sourceDependencies: [SourceDependency(entity: .vendor)]
    )

    public static let requirements = DataRequirements(
        entities: [.vendor],
        requiredCoverage: .complete
    )

    /// Lowercase, strip whitespace and punctuation, strip common trailing
    /// business-entity suffixes. `"ABC Plumbing, Inc."` and `"abc plumbing
    /// inc"` normalize to the same string; `"ABC Plumbing"` and `"ABC
    /// Plumbing Services"` deliberately do NOT (no substring/fuzzy matching).
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        s = s.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
        for suffix in [" inc", " llc", " corp", " co", " ltd", " company"] {
            if s.hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
            }
        }
        return s.replacingOccurrences(of: " ", with: "")
    }

    public static func evaluate(_ input: NormalizedDataSet, context: RuleContext) -> RuleOutcome {
        let activeVendors = input.vendors.filter(\.isActive)
        var byNormalized: [String: [LedgerVendor]] = [:]
        for vendor in activeVendors {
            let key = normalize(vendor.displayName)
            guard !key.isEmpty else { continue }
            byNormalized[key, default: []].append(vendor)
        }

        var findings: [Finding] = []
        for (_, group) in byNormalized.sorted(by: { $0.key < $1.key }) where group.count > 1 {
            let sortedIDs = group.map(\.id).sorted()
            let findingID = FindingIDGenerator.makeID(
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                sortedAffectedIDs: sortedIDs
            )
            if context.dismissedFindingIDs.contains(findingID) { continue }

            let namesList = group.map(\.displayName).joined(separator: ", ")
            let procedure = GuidedProcedure(
                steps: [
                    "Open QuickBooks Online, go to Expenses > Vendors",
                    "Find these vendor records: \(namesList)",
                    "Confirm they represent the same real-world payee (not a coincidental name match)",
                    "Decide which record to keep, then use QuickBooks' Merge feature to combine them (Chart of Accounts-style merge — this moves all transaction history to the surviving record)",
                    "Update the surviving vendor's details (address, terms) if the merged records had different information"
                ],
                pitfalls: [
                    "Merging is permanent and cannot be undone — verify these are truly the same vendor first",
                    "The record you merge INTO keeps its Id; make sure you're keeping the one with the correct/preferred details"
                ],
                doneCriteria: "Only one active vendor record remains for this payee"
            )

            let action = ProposedAction(
                id: "merge-duplicate-vendors",
                title: "Merge the duplicate vendor records",
                resolution: .manualQBO,
                guidedProcedure: procedure,
                consequences: [
                    .reporting("per-vendor totals, price history, and 1099 aggregation become accurate once merged"),
                    .auditTrail("Voice Ledger records your attestation; the merge itself is QBO's own permanent action")
                ],
                reversal: .irreversible
            )

            findings.append(Finding(
                id: findingID,
                ruleID: identity.id,
                ruleVersion: identity.version,
                realmID: input.realmID,
                period: input.period,
                title: "Possible duplicate vendor — \(namesList)",
                severity: .low, // no dollar exposure of its own — a data-quality finding, not a financial-error one
                confidence: .high,
                dollarExposure: .zero,
                evidence: group.map { EvidenceItem(transactionID: $0.id, highlightedFields: ["displayName"]) },
                proposedActions: [action],
                provenance: []
            ))
        }

        if findings.isEmpty {
            guard case .complete = input.coverage else {
                return .cannotEvaluate(.partialCoverage(reason: {
                    if case .partial(let reason) = input.coverage { return reason }
                    return "unknown"
                }()))
            }
            return .pass(coverage: input.coverage, checkedCount: activeVendors.count)
        }
        return .findings(findings)
    }
}
