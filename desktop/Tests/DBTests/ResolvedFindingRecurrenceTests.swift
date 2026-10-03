import Testing
import Foundation
import Core
@testable import DB

/// Gauntlet Loop, Gauntlet B round 12 (2026-08-24): a real, confirmed gap,
/// documented here and in `docs/VOICE_LEDGER_HANDOFF.md` rather than fixed
/// in this run — it's a change to resolve/reopen semantics (`ClientStore
/// .upsertFindings`'s "preserve status across resync" rule exists on
/// purpose, to stop a stale re-detection from flip-flopping a finding back
/// open), not a rendering/logging gap like this run's other fixes, and
/// changing it blind risks a new false-positive class the owner hasn't
/// weighed in on. A finding that goes `.open` -> `.resolved` and later
/// genuinely recurs (the rule re-detects the identical affected-transaction
/// set, so `FindingIDGenerator`'s pure hash produces the identical id — a
/// real QBO shape: e.g. someone un-voids a transaction that had previously
/// triggered an `isVoided` exclusion) is silently and permanently stuck
/// `.resolved`. No Activity Log entry marks the recurrence either — the
/// original `findingResolved` note ("the underlying issue appears to be
/// fixed") is left standing, now false, with nothing correcting it. Kept
/// permanently (not deleted as scratch) since it demonstrates real,
/// reachable behavior worth protecting from silent regression either
/// direction — if someone "fixes" this without a real design decision, this
/// test will flag the behavior change for review.
@Suite("Documented landmine: a resolved finding that recurs stays stuck resolved")
struct ResolvedFindingRecurrenceTests {
    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "voiceledger-round12-\(UUID().uuidString)")
    }

    func sampleFinding(id: String, ruleID: RuleID, realmID: RealmID) -> Finding {
        Finding(
            id: id,
            ruleID: ruleID,
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: realmID,
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Two purchases from Acme look like duplicates",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 42_600, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
    }

    @Test("A resolved finding that recurs with the SAME deterministic id is re-upserted as still .resolved, not reopened")
    func recurrenceStaysResolved() async throws {
        let realmID = RealmID(rawValue: "realm-round12")
        let ruleID = RuleID(rawValue: "VL-DUP-EXP-001")
        let store = try ClientStore(realmID: realmID, rootDirectory: tempRoot())

        // Cycle 1: rule detects it.
        let finding = sampleFinding(id: "dup-exp-recur-1", ruleID: ruleID, realmID: realmID)
        try await store.upsertFindings([finding])
        #expect(try await store.loadFindings().first?.status == .open)

        // Cycle 2: exclusion fires (e.g. isVoided), rule stops producing it,
        // AppState's loop calls reconcileAgainstLatestRun with an empty
        // current-run set for this rule -> resolved, logged.
        let resolved = try await store.reconcileAgainstLatestRun(currentRunFindingIDs: [], ruleID: ruleID, period: AccountingPeriod(year: 2026, month: 7))
        #expect(resolved.map(\.id) == ["dup-exp-recur-1"])
        #expect(try await store.loadFindings().first?.status == .resolved)

        // Cycle 3: the underlying condition genuinely recurs (e.g. someone
        // un-voids the duplicate) — the rule re-detects the EXACT same
        // affected-transaction set, so FindingIDGenerator (a pure hash of
        // ruleID+version+realm+period+sortedAffectedIDs) produces the
        // identical id "dup-exp-recur-1" again. This mirrors exactly what
        // AppState.syncAndEvaluate's `.findings` branch does: it calls
        // store.upsertFindings(ruleFindings) unconditionally.
        try await store.upsertFindings([finding])

        let after = try await store.loadFindings()
        #expect(after.count == 1, "still just one row for this id, not a duplicate")
        // THE GAP: this is the crux. upsertFindings's documented contract
        // ("a new detection of an already-resolved problem should not
        // silently reopen it") means status stays .resolved even though the
        // rule just re-detected it as a live finding this cycle.
        #expect(after.first?.status == .resolved, "confirms: status is NOT reopened on recurrence — silently stuck resolved")

        // Now check whether AppState's own findingDetected logic (which
        // this test cannot exercise directly, no test target for
        // VoiceLedgerApp) would even have a chance to log the recurrence.
        // AppState loads `priorFindingIDs` from ALL findings on disk
        // (status-unfiltered) BEFORE the .findings branch runs, so
        // "dup-exp-recur-1" is already a member of priorFindingIDs (it was
        // on disk, as a .resolved row, before this cycle's upsert) ->
        // AppState's `for finding in ruleFindings where
        // !priorFindingIDs.contains(finding.id)` guard means NO
        // findingDetected entry would be logged for this recurrence either.
        let priorFindingIDs = Set(after.map(\.id)) // same set AppState would have loaded pre-upsert in a hypothetical cycle 4
        #expect(priorFindingIDs.contains("dup-exp-recur-1"), "id is already known -> findingDetected's guard would suppress logging even on a genuine future recurrence")
    }
}
