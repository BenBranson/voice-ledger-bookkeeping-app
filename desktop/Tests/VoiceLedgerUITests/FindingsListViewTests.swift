import Testing
import Core
import DesignSystem
@testable import VoiceLedgerUI

/// Gauntlet Loop, Gauntlet C round 2 (2026-08-24): a fresh critic found a
/// real CLAUDE.md rule 5 violation — `FindingsListView`'s "EXCEPTIONS
/// FOUND" coverage-strip column used to render green (`.verified`) purely
/// from `state.findings.isEmpty`, independent of whether the data behind
/// it was actually current. A stale disk-loaded findings list (before any
/// sync in the current process) that happened to be empty rendered a green
/// checkmark right next to "DATA AVAILABLE: not synced yet" in the same
/// strip. This is the first test in this package able to exercise that
/// mapping directly — proving it previously required building a temporary
/// test target from scratch.
@Suite("FindingsListView.ViewState — coverage-strip honesty")
struct FindingsListViewTests {
    func sampleFinding(id: String = "abc123") -> Finding {
        Finding(
            id: id,
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: RealmID(rawValue: "realm-a"),
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Possible duplicate expense",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 48_620, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
    }

    @Test("An empty findings list with UNVERIFIED coverage (e.g. not synced yet) must NOT render green — this is the exact bug found")
    func emptyFindingsWithUnverifiedCoverageIsNotChecked() {
        let state = FindingsListView.ViewState(
            environment: .sandbox,
            coverageStatus: .notChecked,
            coverageDetail: "not synced yet",
            findings: []
        )
        #expect(state.exceptionsStatus == .notChecked, "an empty list backed by stale/unsynced data must never claim .verified")
        #expect(state.exceptionsDetail == "Not synced yet")
    }

    @Test("An empty findings list with VERIFIED coverage correctly renders green — the honest positive case")
    func emptyFindingsWithVerifiedCoverageIsVerified() {
        let state = FindingsListView.ViewState(
            environment: .sandbox,
            coverageStatus: .verified,
            coverageDetail: "synced just now",
            findings: []
        )
        #expect(state.exceptionsStatus == .verified)
        #expect(state.exceptionsDetail == "None")
    }

    @Test("A non-empty findings list always shows reviewNeeded with a real count, regardless of coverage status — reviewNeeded never claims currency, so it isn't gated the same way")
    func nonEmptyFindingsAlwaysReviewNeeded() {
        let unsynced = FindingsListView.ViewState(
            environment: .sandbox,
            coverageStatus: .notChecked,
            coverageDetail: "not synced yet",
            findings: [sampleFinding()]
        )
        #expect(unsynced.exceptionsStatus == .reviewNeeded)
        #expect(unsynced.exceptionsDetail == "1 open")

        let synced = FindingsListView.ViewState(
            environment: .sandbox,
            coverageStatus: .verified,
            coverageDetail: "synced just now",
            findings: [sampleFinding(), sampleFinding(id: "def456")]
        )
        #expect(synced.exceptionsStatus == .reviewNeeded)
        #expect(synced.exceptionsDetail == "2 open")
    }
}
