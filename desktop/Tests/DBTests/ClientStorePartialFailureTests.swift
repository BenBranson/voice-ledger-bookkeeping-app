import Testing
import Foundation
import Core
@testable import DB

/// Gauntlet Loop, Gauntlet C round 8 (2026-08-24). `ClientStore` is one JSON
/// file per data type (findings.json, activity-log.json,
/// checklist-completions.json, mapping-hints.json,
/// client-memory-rules.json), each loaded independently and each capable of
/// throwing on its own (malformed/corrupt file) without affecting the
/// others. `AppState.loadFromDiskOnly()` used to call all five `load*()`
/// methods sequentially and publish each straight to a `self.` property as
/// it succeeded — NOT resolved into locals first, unlike the atomic block
/// `syncAndEvaluate()` was hardened into across rounds 4-6 — so a later call
/// throwing left earlier ones already published (fresh) while later ones
/// (and everything after them) silently kept their stale/default value, a
/// mixed fresh/stale state `RootView`'s Month-End Close screen read with no
/// staleness gating. Fixed the same way: all five loads now resolve into
/// locals before any `self.` assignment. This test proves the underlying
/// premise is a real, reachable `ClientStore` state (not contrived) — a
/// single corrupted file throws in isolation while sibling files stay
/// readable — which is what made the pre-fix bug possible.
@Suite("ClientStore partial-failure isolation")
struct ClientStorePartialFailureTests {
    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "voiceledger-gauntletc8-\(UUID().uuidString)")
    }

    @Test("A corrupt checklist-completions.json throws in isolation while findings.json and activity-log.json remain readable — proving AppState.loadFromDiskOnly()'s sequential self.-publishes can genuinely land in a mixed fresh/stale state")
    func partialFileCorruptionIsReachable() async throws {
        let realmID = RealmID(rawValue: "realm-gauntletc8")
        let root = tempRoot()
        let store = try ClientStore(realmID: realmID, rootDirectory: root)

        // Write real, valid data via the store's own normal write path —
        // this is exactly what loadFromDiskOnly's first two calls
        // (loadFindings/loadActivityLog) would read back successfully.
        let finding = Finding(
            id: "f1", ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realmID,
            period: AccountingPeriod(year: 2026, month: 7), title: "Possible duplicate expense",
            severity: .high, confidence: .high, dollarExposure: Money(minorUnits: 100, currency: .usd),
            evidence: [], proposedActions: [], provenance: []
        )
        try await store.upsertFindings([finding])
        try await store.appendActivityLogEntry(ActivityLogEntry(
            realmID: realmID, actor: .system, kind: .findingDetected, findingID: "f1",
            ruleID: finding.ruleID, ruleVersion: finding.ruleVersion, findingSummary: finding.title, note: nil
        ))

        // Now corrupt ONLY checklist-completions.json — simulating exactly
        // the kind of single-file corruption (partial disk write, crash
        // mid-save, external interference) this per-file JSON store is
        // structurally exposed to, since each data type is its own file
        // with its own independent write.
        let checklistURL = root.appending(path: realmID.rawValue, directoryHint: .isDirectory)
            .appending(path: "checklist-completions.json")
        try "{ this is not valid json ".data(using: .utf8)!.write(to: checklistURL)

        // The two calls loadFromDiskOnly makes BEFORE the corrupted one
        // still succeed with real, fresh data...
        let loadedFindings = try await store.loadFindings()
        let loadedActivityLog = try await store.loadActivityLog()
        #expect(loadedFindings.count == 1)
        #expect(loadedActivityLog.count == 1)

        // ...while the corrupted one throws, exactly where
        // loadFromDiskOnly's sequential `self.checklistCompletions = try
        // await store.loadChecklistCompletions()` would abort the `do`
        // block. In AppState, self.findings/self.activityLog would ALREADY
        // be published (real fresh data) at that point, but
        // self.checklistCompletions (and mappingHints/clientMemoryRules,
        // never reached) would remain at their init-time empty defaults —
        // a mixed fresh/stale combination, not an atomic all-or-nothing
        // publish. `loadState` becomes `.failed`, but nothing on the
        // default `.connection` screen (AppState.screen's initial value)
        // surfaces that — only `FindingsListView`'s `.list` screen reads
        // `loadState.failed` via `syncError`, and `.list` is not where the
        // app starts.
        await #expect(throws: (any Error).self) {
            _ = try await store.loadChecklistCompletions()
        }

        try? FileManager.default.removeItem(at: root)
    }
}
