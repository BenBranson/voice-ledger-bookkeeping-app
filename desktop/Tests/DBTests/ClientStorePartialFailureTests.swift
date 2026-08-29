import Testing
import Foundation
import Core
@testable import DB

/// Gauntlet Loop, Gauntlet C round 8 (2026-08-24). `ClientStore` used to be
/// one JSON file per data type, each loaded independently and each capable
/// of throwing on its own (malformed/corrupt file) without affecting the
/// others. `AppState.loadFromDiskOnly()` used to call all five `load*()`
/// methods sequentially and publish each straight to a `self.` property as
/// it succeeded — NOT resolved into locals first, unlike the atomic block
/// `syncAndEvaluate()` was hardened into across rounds 4-6 — so a later call
/// throwing left earlier ones already published (fresh) while later ones
/// (and everything after them) silently kept their stale/default value, a
/// mixed fresh/stale state `RootView`'s Month-End Close screen read with no
/// staleness gating. Fixed the same way: all five loads now resolve into
/// locals before any `self.` assignment (still true today — see
/// `AppState.loadFromDiskOnly`).
///
/// **Adapted 2026-08-29 for the SQLite-backed `ClientStore`** (§7.1's real
/// design, replacing the JSON-file substitute): there's no longer a
/// separate physical file per data type to corrupt independently, so this
/// test's original reproduction (write garbage bytes to one `.json` file)
/// no longer applies as written. The underlying invariant this test
/// actually protects — one key's stored value can fail to decode while a
/// SIBLING key's value decodes fine, so `AppState`'s locals-first fix still
/// matters — is still real and still worth testing: it's reproduced here
/// by writing an invalid JSON string directly into one `kv` row via
/// `SQLiteConnection` (bypassing `ClientStore`'s own encoder, the same way
/// the original test bypassed `ClientStore`'s own writer to corrupt one
/// file), while a sibling key's row is written normally through the store.
@Suite("ClientStore partial-failure isolation")
struct ClientStorePartialFailureTests {
    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "voiceledger-gauntletc8-\(UUID().uuidString)")
    }

    @Test("A corrupt checklist-completions row throws in isolation while findings/activity-log rows remain readable — proving AppState.loadFromDiskOnly()'s sequential self.-publishes can genuinely land in a mixed fresh/stale state")
    func partialRowCorruptionIsReachable() async throws {
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

        // Now corrupt ONLY the "checklist-completions" row's value —
        // simulating the kind of single-key corruption (a bug in whatever
        // wrote it, a hand-edited row) the `kv` design is structurally
        // exposed to, same shape the original per-file test used, adapted
        // to the new storage model's own unit of corruption (a row, not a
        // file).
        let dbPath = root.appending(path: realmID.rawValue, directoryHint: .isDirectory)
            .appending(path: "store.sqlite").path
        let rawConnection = try SQLiteConnection(path: dbPath)
        try rawConnection.setValue("{ this is not valid json ", forKey: "checklist-completions")

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
