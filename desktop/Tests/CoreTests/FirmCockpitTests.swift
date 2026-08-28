import Testing
import Foundation
@testable import Core

@Suite("FirmCockpit.summarize")
struct FirmCockpitTests {
    let period = AccountingPeriod(year: 2026, month: 7)

    func client(realmID: String = "realm-a") -> ConnectedClient {
        ConnectedClient(
            realmID: RealmID(rawValue: realmID),
            companyName: "Test Co",
            environment: .sandbox,
            writeEnabled: false,
            lastHealthCheckAt: nil,
            lastHealthCheckStatus: .green
        )
    }

    func finding(id: String, status: FindingStatus, severity: Severity) -> Finding {
        Finding(
            id: id,
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
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

    @Test("Counts open findings, and urgent as open+high only")
    func countsOpenAndUrgentFindings() {
        let findings = [
            finding(id: "1", status: .open, severity: .high),
            finding(id: "2", status: .open, severity: .low),
            finding(id: "3", status: .resolved, severity: .high),
            finding(id: "4", status: .dismissed, severity: .high)
        ]
        let summary = FirmCockpit.summarize(client: client(), findings: findings, checklistCompletions: [], period: period, importedStatementLineCount: 0, activityLog: [])
        #expect(summary.openFindingsCount == 2)
        #expect(summary.urgentFindingsCount == 1)
    }

    @Test("Checklist completion reflects MonthEndChecklist.completionStatus for the given period")
    func checklistCompletionMatchesMonthEndChecklist() {
        let completion = ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "resolve-cleanup-assessment"), period: period, completedBy: "Ben")
        let summary = FirmCockpit.summarize(client: client(), findings: [], checklistCompletions: [completion], period: period, importedStatementLineCount: 0, activityLog: [])
        #expect(summary.checklistCompleted == 1)
        #expect(summary.checklistTotal == MonthEndChecklist.defaultItems.count)
    }

    @Test("A checklist completion for a DIFFERENT period is not counted")
    func checklistCompletionForDifferentPeriodNotCounted() {
        let otherPeriod = AccountingPeriod(year: 2026, month: 6)
        let completion = ChecklistItemCompletion(itemID: ChecklistItemID(rawValue: "resolve-cleanup-assessment"), period: otherPeriod, completedBy: "Ben")
        let summary = FirmCockpit.summarize(client: client(), findings: [], checklistCompletions: [completion], period: period, importedStatementLineCount: 0, activityLog: [])
        #expect(summary.checklistCompleted == 0)
    }

    @Test("Passes through the imported statement line count unchanged")
    func passesThroughImportedStatementLineCount() {
        let summary = FirmCockpit.summarize(client: client(), findings: [], checklistCompletions: [], period: period, importedStatementLineCount: 42, activityLog: [])
        #expect(summary.importedStatementLineCount == 42)
    }

    @Test("lastLocalActivityAt is the max recordedAt across the activity log")
    func lastLocalActivityIsMaxRecordedAt() {
        let earlier = ActivityLogEntry(realmID: RealmID(rawValue: "realm-a"), recordedAt: Date(timeIntervalSince1970: 1000), actor: .system, kind: .findingDetected)
        let later = ActivityLogEntry(realmID: RealmID(rawValue: "realm-a"), recordedAt: Date(timeIntervalSince1970: 2000), actor: .system, kind: .findingResolved)
        let summary = FirmCockpit.summarize(client: client(), findings: [], checklistCompletions: [], period: period, importedStatementLineCount: 0, activityLog: [earlier, later])
        #expect(summary.lastLocalActivityAt == later.recordedAt)
    }

    @Test("lastLocalActivityAt is nil when the activity log is empty — never a guessed date")
    func lastLocalActivityNilWhenEmpty() {
        let summary = FirmCockpit.summarize(client: client(), findings: [], checklistCompletions: [], period: period, importedStatementLineCount: 0, activityLog: [])
        #expect(summary.lastLocalActivityAt == nil)
    }

    @Test("The summary carries the same client identity it was given")
    func summaryCarriesClientIdentity() {
        let c = client(realmID: "specific-realm")
        let summary = FirmCockpit.summarize(client: c, findings: [], checklistCompletions: [], period: period, importedStatementLineCount: 0, activityLog: [])
        #expect(summary.client.realmID.rawValue == "specific-realm")
        #expect(summary.id == "specific-realm")
    }
}
