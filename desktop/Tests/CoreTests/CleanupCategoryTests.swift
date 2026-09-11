import Testing
@testable import Core

@Suite("CleanupCategory")
struct CleanupCategoryTests {
    /// Fixed 2026-09-06: this test used to hand-mirror `AppState
    /// .cleanupAssessmentRuleIDs` as a THIRD independently-typed copy of
    /// the same 23 rule IDs (`CleanupCategory`'s own category table below
    /// already had to list every one), since `VoiceLedgerApp` can't be
    /// imported from `CoreTests` without inverting the module boundary
    /// `check-module-boundaries.sh` enforces. Now iterates
    /// `CleanupCategory.ruleIDs` itself — derived from the same
    /// dictionary `category(forRuleID:)` reads, so this test can no longer
    /// silently drift from what it's supposed to be checking.
    @Test("Every Cleanup Assessment rule ID resolves to a real category, never .other")
    func everyRuleHasACategory() {
        for ruleID in CleanupCategory.ruleIDs {
            #expect(CleanupCategory.category(forRuleID: ruleID) != .other, "\(ruleID) has no category mapping")
        }
    }

    @Test("ruleIDs has the expected count and contains no surprises")
    func ruleIDsMatchesKnownSet() {
        #expect(CleanupCategory.ruleIDs.count == 23)
        #expect(CleanupCategory.ruleIDs.contains("VL-CC-PAYMENT-001"))
        #expect(CleanupCategory.ruleIDs.contains("VL-TRANSPOSITION-001"))
        #expect(!CleanupCategory.ruleIDs.contains("VL-CAT-UNCAT-001")) // a real rule, deliberately NOT a Cleanup Assessment one
    }

    @Test("An unknown rule ID falls back to .other rather than crashing")
    func unknownRuleFallsBackToOther() {
        #expect(CleanupCategory.category(forRuleID: "VL-NOT-A-REAL-RULE-999") == .other)
    }

    @Test("sortOrder is unique per case so category display order is stable")
    func sortOrderIsUnique() {
        let orders = CleanupCategory.allCases.map(\.sortOrder)
        #expect(Set(orders).count == orders.count)
    }

    /// Added 2026-09-11 alongside `ruleIDs(in:)`, built so
    /// `AppState.balanceSheetIntegrityRuleIDs` (Page 8's rule set) derives
    /// from this table instead of its own hand-typed literal — the literal
    /// had drifted (two rules filed here under `.balanceSheetIntegrity`
    /// were missing from it, so neither ever rendered on the actual page).
    /// This test pins the exact set so a similar drift is caught here
    /// again if it ever recurs.
    @Test("ruleIDs(in:) returns exactly the rules filed under that category")
    func ruleIDsInCategoryMatchesKnownSet() {
        let balanceSheetIntegrity = CleanupCategory.ruleIDs(in: .balanceSheetIntegrity)
        #expect(balanceSheetIntegrity == [
            "VL-OBE-BALANCE-001", "VL-BS-NEGBAL-001", "VL-BS-UNDEP-001",
            "VL-FORCED-RECON-001", "VL-REPORT-TIE-001", "VL-CLOSED-PERIOD-DRIFT-001",
            "VL-BS-DRCR-001"
        ])
    }

    @Test("ruleIDs(in:) partitions ruleIDs exactly — every rule in exactly one category's set")
    func ruleIDsInCategoryPartitionsAllRuleIDs() {
        let union = CleanupCategory.allCases.reduce(into: Set<String>()) { result, category in
            result.formUnion(CleanupCategory.ruleIDs(in: category))
        }
        #expect(union == CleanupCategory.ruleIDs)
        for ruleID in CleanupCategory.ruleIDs {
            let containingCategories = CleanupCategory.allCases.filter { CleanupCategory.ruleIDs(in: $0).contains(ruleID) }
            #expect(containingCategories.count == 1, "\(ruleID) should belong to exactly one category, found in \(containingCategories)")
        }
    }
}
