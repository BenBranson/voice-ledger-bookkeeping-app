import Testing
import Foundation
import Core
@testable import DB

/// The SQLite migration (2026-08-29, `ClientStore.swift`'s doc comment)
/// promises existing realms' JSON-file data survives the storage engine
/// change automatically — this is the one genuinely new, risk-bearing
/// piece of logic in that migration (everything else is the same
/// load/save call pattern the JSON-file version already had, just backed
/// by a different store). A bug here means real accumulated findings,
/// activity log entries, etc. silently vanish on first launch after
/// upgrading, so it gets its own dedicated coverage rather than folding
/// into `ClientStoreTests`.
@Suite("ClientStore legacy JSON migration")
struct ClientStoreJSONMigrationTests {
    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "voiceledger-json-migration-\(UUID().uuidString)")
    }

    @Test("A pre-existing findings.json is imported into SQLite on first open")
    func migratesExistingFindingsJSON() async throws {
        let realmID = RealmID(rawValue: "realm-migration")
        let root = tempRoot()
        let realmDirectory = root.appending(path: realmID.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: realmDirectory, withIntermediateDirectories: true)

        // Write a legacy findings.json directly — simulating a realm that
        // was using the JSON-file store before the SQLite migration
        // shipped, with real accumulated data already on disk.
        let finding = Finding(
            id: "legacy-finding-1",
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            realmID: realmID,
            period: AccountingPeriod(year: 2026, month: 7),
            title: "Possible duplicate expense",
            severity: .high,
            confidence: .high,
            dollarExposure: Money(minorUnits: 48_620, currency: .usd),
            evidence: [],
            proposedActions: [],
            provenance: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([finding])
        try data.write(to: realmDirectory.appending(path: "findings.json"))

        // Opening ClientStore for the first time (no store.sqlite exists
        // yet) should migrate this legacy file in automatically.
        let store = try ClientStore(realmID: realmID, rootDirectory: root)
        let loaded = try await store.loadFindings()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "legacy-finding-1")

        try? FileManager.default.removeItem(at: root)
    }

    @Test("A legacy file is only migrated once — a later re-open does not re-import and overwrite newer SQLite data")
    func migrationIsOneTimeOnly() async throws {
        let realmID = RealmID(rawValue: "realm-migration-2")
        let root = tempRoot()
        let realmDirectory = root.appending(path: realmID.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: realmDirectory, withIntermediateDirectories: true)

        let oldFinding = Finding(
            id: "old-finding", ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realmID,
            period: AccountingPeriod(year: 2026, month: 7), title: "Old finding",
            severity: .high, confidence: .high, dollarExposure: Money(minorUnits: 100, currency: .usd),
            evidence: [], proposedActions: [], provenance: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([oldFinding]).write(to: realmDirectory.appending(path: "findings.json"))

        // First open: migrates the legacy file, then adds a NEW finding
        // through the store's own normal write path.
        let firstOpen = try ClientStore(realmID: realmID, rootDirectory: root)
        _ = try await firstOpen.loadFindings() // triggers nothing extra, just confirms migration ran
        let newFinding = Finding(
            id: "new-finding", ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realmID,
            period: AccountingPeriod(year: 2026, month: 7), title: "New finding",
            severity: .high, confidence: .high, dollarExposure: Money(minorUnits: 200, currency: .usd),
            evidence: [], proposedActions: [], provenance: []
        )
        try await firstOpen.upsertFindings([newFinding])

        // Re-opening (simulating a second app launch) must NOT re-import
        // the stale findings.json over the SQLite data that already
        // includes both findings now.
        let secondOpen = try ClientStore(realmID: realmID, rootDirectory: root)
        let loaded = try await secondOpen.loadFindings()
        #expect(loaded.count == 2)
        #expect(Set(loaded.map(\.id)) == ["old-finding", "new-finding"])

        try? FileManager.default.removeItem(at: root)
    }

    @Test("No legacy files at all — a brand-new realm starts with real empty defaults, not an error")
    func noLegacyFilesStartsEmpty() async throws {
        let realmID = RealmID(rawValue: "realm-brand-new")
        let root = tempRoot()
        let store = try ClientStore(realmID: realmID, rootDirectory: root)
        let loaded = try await store.loadFindings()
        #expect(loaded.isEmpty)
        try? FileManager.default.removeItem(at: root)
    }

    @Test("Multiple legacy files (findings and activity log) are both migrated in one open")
    func migratesMultipleLegacyFiles() async throws {
        let realmID = RealmID(rawValue: "realm-migration-multi")
        let root = tempRoot()
        let realmDirectory = root.appending(path: realmID.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: realmDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let finding = Finding(
            id: "f1", ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0), realmID: realmID,
            period: AccountingPeriod(year: 2026, month: 7), title: "A finding",
            severity: .high, confidence: .high, dollarExposure: Money(minorUnits: 100, currency: .usd),
            evidence: [], proposedActions: [], provenance: []
        )
        try encoder.encode([finding]).write(to: realmDirectory.appending(path: "findings.json"))

        let entry = ActivityLogEntry(realmID: realmID, actor: .system, kind: .findingDetected, findingID: "f1")
        try encoder.encode([entry]).write(to: realmDirectory.appending(path: "activity-log.json"))

        let store = try ClientStore(realmID: realmID, rootDirectory: root)
        let loadedFindings = try await store.loadFindings()
        let loadedActivity = try await store.loadActivityLog()
        #expect(loadedFindings.count == 1)
        #expect(loadedActivity.count == 1)

        try? FileManager.default.removeItem(at: root)
    }
}
