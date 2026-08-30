import Testing
@testable import Core

@Suite("CleanupCategory")
struct CleanupCategoryTests {
    /// Mirrors `AppState.cleanupAssessmentRuleIDs` (VoiceLedgerApp can't be
    /// imported from CoreTests without inverting the module boundary
    /// `check-module-boundaries.sh` enforces) — kept in sync manually.
    /// Every one of these must resolve to a real category, not `.other`:
    /// `.other` existing at all is a safety net for a rule added to the
    /// assessment later and forgotten here, not an acceptable steady state
    /// for a rule that's been in the set since this test was written.
    private static let cleanupAssessmentRuleIDs = [
        "VL-CC-PAYMENT-001", "VL-PAYROLL-LUMP-001", "VL-OBE-BALANCE-001", "VL-BS-NEGBAL-001",
        "VL-DUP-VEND-001", "VL-DUP-BILL-001", "VL-DUP-INV-001", "VL-DUP-PAY-001",
        "VL-BS-UNDEP-001", "VL-VENDCREDIT-UNAPPLIED-001", "VL-FORCED-RECON-001", "VL-REPORT-TIE-001",
        "VL-FEE-AVOIDABLE-001", "VL-PERIOD-CLOSED-001", "VL-PERSONAL-001", "VL-VEND-ANOMALY-001",
        "VL-CLOSED-PERIOD-DRIFT-001", "VL-VEND-PRICE-001", "VL-CAT-MISCODE-001", "VL-BS-DRCR-001",
        "VL-RELATIONSHIP-003", "VL-RELATIONSHIP-005"
    ]

    @Test("Every Cleanup Assessment rule ID resolves to a real category, never .other")
    func everyRuleHasACategory() {
        for ruleID in Self.cleanupAssessmentRuleIDs {
            #expect(CleanupCategory.category(forRuleID: ruleID) != .other, "\(ruleID) has no category mapping")
        }
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
}
