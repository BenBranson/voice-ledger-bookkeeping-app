import Testing
@testable import Core

@Suite("Finding.priorityScore / FindingTriage")
struct FindingPriorityTests {
    static func makeFinding(
        id: String,
        severity: Severity,
        confidence: Confidence,
        exposureDollars: Int64,
        currency: CurrencyCode = .usd,
        resolution: ResolutionKind? = nil
    ) -> Finding {
        let proposedActions: [ProposedAction]
        if let resolution {
            proposedActions = [ProposedAction(
                id: "\(id)-action",
                title: "Test action",
                resolution: resolution,
                guidedProcedure: nil,
                consequences: [],
                reversal: .irreversible
            )]
        } else {
            proposedActions = []
        }
        return Finding(
            id: id,
            ruleID: RuleID(rawValue: "VL-TEST-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "9999"),
            period: AccountingPeriod(year: 2026, month: 8),
            title: "Test finding",
            severity: severity,
            confidence: confidence,
            dollarExposure: Money(minorUnits: exposureDollars * 100, currency: currency),
            evidence: [],
            proposedActions: proposedActions,
            provenance: []
        )
    }

    @Test("High severity + high confidence scores at least 80")
    func highSeverityHighConfidenceScoresHigh() {
        let finding = Self.makeFinding(id: "a", severity: .high, confidence: .high, exposureDollars: 3000)
        #expect(finding.priorityScore >= 80)
    }

    @Test("Low severity + low confidence scores well under a high-severity finding")
    func lowSeverityLowConfidenceScoresLow() {
        let low = Self.makeFinding(id: "a", severity: .low, confidence: .low, exposureDollars: 100)
        let high = Self.makeFinding(id: "b", severity: .high, confidence: .high, exposureDollars: 3000)
        #expect(low.priorityScore < high.priorityScore)
    }

    @Test("Score is always within 0...100")
    func scoreIsAlwaysInRange() {
        for severity in [Severity.low, .high] {
            for confidence in [Confidence.low, .medium, .high] {
                for dollars: Int64 in [0, 1, 2_500, 100_000] {
                    let finding = Self.makeFinding(id: "x", severity: severity, confidence: confidence, exposureDollars: dollars)
                    #expect((0...100).contains(finding.priorityScore))
                }
            }
        }
    }

    @Test("A larger dollar exposure outranks a smaller one at the same severity and confidence")
    func largerExposureOutranksSmallerAtSameBand() {
        let small = Self.makeFinding(id: "a", severity: .high, confidence: .high, exposureDollars: 3_000)
        let large = Self.makeFinding(id: "b", severity: .high, confidence: .high, exposureDollars: 40_000)
        #expect(large.priorityScore >= small.priorityScore)
    }

    @Test("A finding whose exposure currency doesn't match the materiality floor's currency does not crash — exposure just contributes nothing")
    func mismatchedCurrencyDoesNotCrash() {
        let finding = Self.makeFinding(id: "a", severity: .high, confidence: .medium, exposureDollars: 5_000, currency: CurrencyCode(rawValue: "EUR"))
        #expect((0...100).contains(finding.priorityScore))
    }

    @Test("FindingTriage.sorted orders highest priority first")
    func triageSortsHighestFirst() {
        let low = Self.makeFinding(id: "low", severity: .low, confidence: .low, exposureDollars: 50)
        let medium = Self.makeFinding(id: "medium", severity: .low, confidence: .high, exposureDollars: 500)
        let high = Self.makeFinding(id: "high", severity: .high, confidence: .high, exposureDollars: 50_000)

        let sorted = FindingTriage.sorted([low, high, medium])
        #expect(sorted.map(\.id) == ["high", "medium", "low"])
    }

    @Test("FindingTriage.sorted is a stable, deterministic total order for equal scores — ties break on id")
    func triageBreaksTiesById() {
        let a = Self.makeFinding(id: "b-finding", severity: .high, confidence: .high, exposureDollars: 3_000)
        let b = Self.makeFinding(id: "a-finding", severity: .high, confidence: .high, exposureDollars: 3_000)
        let sorted = FindingTriage.sorted([a, b])
        #expect(sorted.map(\.id) == ["a-finding", "b-finding"])
    }

    // MARK: isQuickWin / QuickWinTriage — 2026-08-30, Gemma's own suggestion
    // on Cleanup Assessment: rank by ease of fix (one-click Apply Fix
    // available) as well as severity/dollar impact.

    @Test("isQuickWin is true only when the first proposed action is stagedAPI")
    func isQuickWinReflectsResolutionKind() {
        let staged = Self.makeFinding(id: "a", severity: .high, confidence: .high, exposureDollars: 100, resolution: .stagedAPI)
        let manual = Self.makeFinding(id: "b", severity: .high, confidence: .high, exposureDollars: 100, resolution: .manualQBO)
        let none = Self.makeFinding(id: "c", severity: .high, confidence: .high, exposureDollars: 100)
        #expect(staged.isQuickWin)
        #expect(!manual.isQuickWin)
        #expect(!none.isQuickWin)
    }

    @Test("QuickWinTriage.sorted puts every stagedAPI finding ahead of every manualQBO finding, even when the manual one scores higher on priority")
    func quickWinTriagePutsStagedFirst() {
        let highManual = Self.makeFinding(id: "high-manual", severity: .high, confidence: .high, exposureDollars: 50_000, resolution: .manualQBO)
        let lowStaged = Self.makeFinding(id: "low-staged", severity: .low, confidence: .low, exposureDollars: 50, resolution: .stagedAPI)

        let sorted = QuickWinTriage.sorted([highManual, lowStaged])
        #expect(sorted.map(\.id) == ["low-staged", "high-manual"])
    }

    @Test("QuickWinTriage.sorted preserves FindingTriage's priority order within the quick-win group")
    func quickWinTriagePreservesPriorityOrderWithinGroup() {
        let bigStaged = Self.makeFinding(id: "big-staged", severity: .high, confidence: .high, exposureDollars: 40_000, resolution: .stagedAPI)
        let smallStaged = Self.makeFinding(id: "small-staged", severity: .low, confidence: .low, exposureDollars: 10, resolution: .stagedAPI)

        let sorted = QuickWinTriage.sorted([smallStaged, bigStaged])
        #expect(sorted.map(\.id) == ["big-staged", "small-staged"])
    }
}
