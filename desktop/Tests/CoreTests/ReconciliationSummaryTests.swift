import Testing
import Foundation
@testable import Core

@Suite("ReconciliationSummary")
struct ReconciliationSummaryTests {
    func finding(id: String, exposureMinorUnits: Int64) -> Finding {
        Finding(
            id: id,
            ruleID: RuleID(rawValue: "VL-RECON-MISSING-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Statement line with no matching posted transaction",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: exposureMinorUnits, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
    }

    @Test("With no unmatched findings, everything is matched and unmatchedTotal is nil")
    func allMatched() {
        let summary = ReconciliationSummary.compute(totalStatementLines: 10, unmatchedFindings: [])
        #expect(summary.totalStatementLines == 10)
        #expect(summary.matchedCount == 10)
        #expect(summary.unmatchedCount == 0)
        #expect(summary.unmatchedTotal == nil)
    }

    @Test("Unmatched findings reduce matchedCount and sum into unmatchedTotal")
    func someUnmatched() {
        let findings = [finding(id: "a", exposureMinorUnits: 10_000), finding(id: "b", exposureMinorUnits: 5_000)]
        let summary = ReconciliationSummary.compute(totalStatementLines: 10, unmatchedFindings: findings)
        #expect(summary.matchedCount == 8)
        #expect(summary.unmatchedCount == 2)
        #expect(summary.unmatchedTotal == Money(minorUnits: 15_000, currency: .usd))
    }

    @Test("matchedCount never goes negative even if unmatchedFindings somehow exceeds totalStatementLines")
    func matchedCountNeverNegative() {
        let findings = [finding(id: "a", exposureMinorUnits: 1_000), finding(id: "b", exposureMinorUnits: 1_000), finding(id: "c", exposureMinorUnits: 1_000)]
        let summary = ReconciliationSummary.compute(totalStatementLines: 2, unmatchedFindings: findings)
        #expect(summary.matchedCount == 0)
    }
}
