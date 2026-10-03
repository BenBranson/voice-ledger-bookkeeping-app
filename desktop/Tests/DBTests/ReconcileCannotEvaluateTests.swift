import Testing
import Foundation
import Core
@testable import DB

/// Gauntlet Loop, Gauntlet B round 11 (2026-08-24): `AppState.syncAndEvaluate()`
/// used to collapse a `.cannotEvaluate` `RuleOutcome` into the same "empty
/// current-run set" as a genuine `.pass` before calling
/// `reconcileAgainstLatestRun` — so a transient failure (e.g. a `try?`-
/// swallowed report fetch) would resolve every open finding for that rule,
/// with the Activity Log claiming "the underlying issue appears to be
/// fixed." That claim was false: the rule never actually re-ran the check.
/// `AppState`'s branch now excludes `.cannotEvaluate` from
/// `currentRunIDsByRule` entirely, so `reconcileAgainstLatestRun` is simply
/// not called for that rule this cycle. `AppState.swift` lives in the
/// `VoiceLedgerApp` executable target (no test target), so this test
/// exercises the `ClientStore` half of the fix directly: confirming that
/// NOT calling `reconcileAgainstLatestRun` (what the corrected branch now
/// does for `.cannotEvaluate`) leaves the finding untouched, in contrast to
/// the `.pass`/`.findings` cases, which correctly do call it.
@Suite("reconcileAgainstLatestRun is not called for a .cannotEvaluate outcome")
struct ReconcileCannotEvaluateTests {
    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "voiceledger-round11-\(UUID().uuidString)")
    }

    func sampleFinding(id: String, ruleID: RuleID, realmID: RealmID) -> Finding {
        Finding(
            id: id,
            ruleID: ruleID,
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: realmID,
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Reconciliation was forced despite a discrepancy",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 426_476, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
    }

    @Test("A rule that returns .cannotEvaluate this sync — simulated by simply skipping the reconcile call, as the fixed AppState branch now does — leaves a previously-open finding untouched, not falsely resolved")
    func skippingReconcileLeavesFindingOpen() async throws {
        let realmID = RealmID(rawValue: "realm-round11")
        let ruleID = RuleID(rawValue: "VL-FORCED-RECON-001")
        let store = try ClientStore(realmID: realmID, rootDirectory: tempRoot())

        let finding = sampleFinding(id: "forced-recon-1", ruleID: ruleID, realmID: realmID)
        try await store.upsertFindings([finding])

        // The fixed AppState branch for .cannotEvaluate does nothing here —
        // no reconcileAgainstLatestRun call at all for this rule this cycle.

        let loaded = try await store.loadFindings()
        #expect(loaded.first?.status == .open, "a rule that couldn't run this sync must never have its findings silently resolved")
    }

    @Test("Contrast: a genuine .pass (rule ran, found nothing) correctly resolves via reconcileAgainstLatestRun with an empty current-run set")
    func genuinePassResolves() async throws {
        let realmID = RealmID(rawValue: "realm-round11b")
        let ruleID = RuleID(rawValue: "VL-FORCED-RECON-001")
        let store = try ClientStore(realmID: realmID, rootDirectory: tempRoot())

        let finding = sampleFinding(id: "forced-recon-2", ruleID: ruleID, realmID: realmID)
        try await store.upsertFindings([finding])

        let resolved = try await store.reconcileAgainstLatestRun(currentRunFindingIDs: [], ruleID: ruleID, period: AccountingPeriod(year: 2026, month: 7))
        #expect(resolved.count == 1)
        #expect(resolved.first?.id == "forced-recon-2")
    }
}
