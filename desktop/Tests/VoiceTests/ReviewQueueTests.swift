import Testing
@testable import Voice
import Core
import Foundation

@Suite("ReviewQueue.build")
struct ReviewQueueTests {
    func finding(id: String, severity: Severity, exposure: Int64, status: FindingStatus = .open) -> Finding {
        var f = Finding(
            id: id, ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7), title: "Finding \(id)",
            severity: severity, confidence: .high, dollarExposure: Money(minorUnits: exposure, currency: .usd),
            evidence: [], proposedActions: [], provenance: []
        )
        f.status = status
        return f
    }

    @Test("Orders by severity first — high before low, regardless of dollar exposure")
    func ordersBySeverityFirst() {
        let findings = [
            finding(id: "low-big", severity: .low, exposure: 100_000),
            finding(id: "high-small", severity: .high, exposure: 100)
        ]
        let queue = ReviewQueue.build(from: findings)
        #expect(queue == ["high-small", "low-big"])
    }

    @Test("Within the same severity, orders by dollar exposure descending")
    func ordersByExposureWithinSeverity() {
        let findings = [
            finding(id: "small", severity: .high, exposure: 100),
            finding(id: "big", severity: .high, exposure: 10_000)
        ]
        let queue = ReviewQueue.build(from: findings)
        #expect(queue == ["big", "small"])
    }

    @Test("Excludes resolved and dismissed findings — only .open is queued")
    func excludesNonOpenFindings() {
        let findings = [
            finding(id: "open1", severity: .high, exposure: 100, status: .open),
            finding(id: "resolved1", severity: .high, exposure: 999_999, status: .resolved),
            finding(id: "dismissed1", severity: .high, exposure: 999_999, status: .dismissed)
        ]
        let queue = ReviewQueue.build(from: findings)
        #expect(queue == ["open1"])
    }

    @Test("An empty findings list produces an empty queue, not an error")
    func emptyFindingsProducesEmptyQueue() {
        #expect(ReviewQueue.build(from: []).isEmpty)
    }
}
