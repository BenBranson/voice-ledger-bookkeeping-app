import Testing
import Foundation
@testable import Core

@Suite("NextBestAction")
struct NextBestActionTests {
    let period = AccountingPeriod(year: 2026, month: 7)

    func finding(id: String, status: FindingStatus, severity: Severity) -> Finding {
        Finding(
            id: id,
            ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: period,
            title: "Test finding",
            severity: severity,
            confidence: .high,
            dollarExposure: Money(minorUnits: 10_000, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: [],
            status: status
        )
    }

    @Test("Open high-severity findings take priority over everything else")
    func openHighSeverityFindingsTakePriority() {
        let findings = [
            finding(id: "1", status: .open, severity: .high),
            finding(id: "2", status: .open, severity: .low)
        ]
        let action = NextBestAction.compute(findings: findings, checklistCompletions: [], period: period, hasImportedStatement: true)
        #expect(action == .reviewHighSeverityFindings(count: 1))
    }

    @Test("A resolved or dismissed high-severity finding does not count")
    func resolvedOrDismissedHighSeverityDoesNotCount() {
        let findings = [
            finding(id: "1", status: .resolved, severity: .high),
            finding(id: "2", status: .dismissed, severity: .high)
        ]
        let action = NextBestAction.compute(findings: findings, checklistCompletions: [], period: period, hasImportedStatement: true)
        #expect(action != .reviewHighSeverityFindings(count: 1))
        #expect(action != .reviewHighSeverityFindings(count: 2))
    }

    @Test("With no open high-severity findings, an unimported bank statement is next")
    func noStatementImportedIsNextAfterFindings() {
        let action = NextBestAction.compute(findings: [], checklistCompletions: [], period: period, hasImportedStatement: false)
        #expect(action == .importBankStatement)
    }

    @Test("With a statement imported and no findings, the next unlocked incomplete checklist item is returned")
    func nextChecklistItemReturnedWhenClear() {
        let action = NextBestAction.compute(findings: [], checklistCompletions: [], period: period, hasImportedStatement: true)
        #expect(action == .completeChecklistItem(MonthEndChecklist.defaultItems[0]))
    }

    @Test("A locked checklist item (unmet prerequisites) is skipped in favor of the next unlocked one")
    func lockedChecklistItemIsSkipped() {
        let firstItemID = MonthEndChecklist.defaultItems[0].id
        let completions = [ChecklistItemCompletion(itemID: firstItemID, period: period, completedBy: "Test")]
        let action = NextBestAction.compute(findings: [], checklistCompletions: completions, period: period, hasImportedStatement: true)
        guard case .completeChecklistItem(let item) = action else {
            Issue.record("expected .completeChecklistItem")
            return
        }
        #expect(item.id != firstItemID)
        #expect(MonthEndChecklist.isUnlocked(item, completedItemIDs: [firstItemID]))
    }

    @Test("Every checklist item complete and no findings produces .allClear")
    func allClearWhenEverythingDone() {
        let completions = MonthEndChecklist.defaultItems.map { ChecklistItemCompletion(itemID: $0.id, period: period, completedBy: "Test") }
        let action = NextBestAction.compute(findings: [], checklistCompletions: completions, period: period, hasImportedStatement: true)
        #expect(action == .allClear)
    }

    @Test("Checklist completions for a different period do not count toward this period's status")
    func completionsForDifferentPeriodDoNotCount() {
        let otherPeriod = AccountingPeriod(year: 2026, month: 6)
        let completions = MonthEndChecklist.defaultItems.map { ChecklistItemCompletion(itemID: $0.id, period: otherPeriod, completedBy: "Test") }
        let action = NextBestAction.compute(findings: [], checklistCompletions: completions, period: period, hasImportedStatement: true)
        #expect(action == .completeChecklistItem(MonthEndChecklist.defaultItems[0]))
    }
}
