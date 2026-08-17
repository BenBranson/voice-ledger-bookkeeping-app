import Testing
import Foundation
import Core
@testable import DB

@Suite("ClientStore")
struct ClientStoreTests {
    func tempRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "voiceledger-test-\(UUID().uuidString)")
    }

    func sampleFinding(id: String, realmID: RealmID) -> Finding {
        Finding(
            id: id,
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
    }

    @Test("Findings round-trip: upsert then load returns the same finding")
    func findingsRoundTrip() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let finding = sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))
        try await store.upsertFindings([finding])
        let loaded = try await store.loadFindings()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "abc123")
        #expect(loaded[0].status == .open)
    }

    @Test("Re-upserting a resolved finding does not silently reopen it")
    func upsertPreservesResolvedStatus() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        var finding = sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))
        try await store.upsertFindings([finding])

        finding.status = .resolved
        try await store.upsertFindings([finding])
        var loaded = try await store.loadFindings()
        #expect(loaded[0].status == .resolved)

        // Re-detecting the SAME finding (e.g. a rerun before the void's
        // isVoided exclusion has kicked in) must not flip it back to open.
        let redetected = sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))
        try await store.upsertFindings([redetected])
        loaded = try await store.loadFindings()
        #expect(loaded[0].status == .resolved)
    }

    @Test("§11.1's Branch B resolution path: a finding no longer re-detected by its rule resolves via reconciliation")
    func reconcileResolvesViaExclusion() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let ruleID = RuleID(rawValue: "VL-DUP-EXP-001")
        let finding = sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))
        try await store.upsertFindings([finding])

        // Simulate a resync where the duplicate is now voided — the rule's
        // isVoided exclusion means the pair no longer produces this finding
        // at all, so the current run's ID set is empty for this rule.
        try await store.reconcileAgainstLatestRun(currentRunFindingIDs: [], ruleID: ruleID)

        let loaded = try await store.loadFindings()
        #expect(loaded[0].status == .resolved)
    }

    @Test("Two realms never see each other's findings — isolation is a directory boundary, not a query filter")
    func realmIsolation() async throws {
        let root = tempRoot()
        let storeA = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: root)
        let storeB = try ClientStore(realmID: RealmID(rawValue: "realm-b"), rootDirectory: root)

        try await storeA.upsertFindings([sampleFinding(id: "only-in-a", realmID: RealmID(rawValue: "realm-a"))])
        try await storeB.upsertFindings([sampleFinding(id: "only-in-b", realmID: RealmID(rawValue: "realm-b"))])

        let aFindings = try await storeA.loadFindings()
        let bFindings = try await storeB.loadFindings()
        #expect(aFindings.map(\.id) == ["only-in-a"])
        #expect(bFindings.map(\.id) == ["only-in-b"])
    }

    @Test("Activity log is append-only and round-trips")
    func activityLogAppendOnly() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let entry = ActivityLogEntry(
            realmID: RealmID(rawValue: "realm-a"),
            actor: .user("Benjamin Branson"),
            kind: .manualCompletionAttested,
            findingID: "abc123",
            ruleID: RuleID(rawValue: "VL-DUP-EXP-001"),
            ruleVersion: RuleVersion(major: 1, minor: 0, patch: 0),
            note: "Confirmed with client, only one withdrawal occurred"
        )
        try await store.appendActivityLogEntry(entry)
        let loaded = try await store.loadActivityLog()
        #expect(loaded.count == 1)
        #expect(loaded[0].note == "Confirmed with client, only one withdrawal occurred")
    }

    func sampleStatementLine(id: String) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: .importedBankStatementLine, vendorName: "PERMIAN SUPPLY",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14), totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil,
            provenance: .importedFile(documentID: "doc-1", importedAt: Date(), extractionMethod: .deterministicParse, coverage: .complete)
        )
    }

    @Test("Imported statement lines round-trip: upsert then load returns the same lines")
    func importedStatementLinesRoundTrip() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        try await store.upsertImportedStatementLines([sampleStatementLine(id: "doc-1-row0")])
        let loaded = try await store.loadImportedStatementLines()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == "doc-1-row0")
        #expect(loaded[0].entityKind == .importedBankStatementLine)
    }

    @Test("Upserting imported statement lines is idempotent by id — reimporting the same file does not duplicate rows")
    func importedStatementLinesUpsertIsIdempotent() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        try await store.upsertImportedStatementLines([sampleStatementLine(id: "doc-1-row0")])
        try await store.upsertImportedStatementLines([sampleStatementLine(id: "doc-1-row0")])
        let loaded = try await store.loadImportedStatementLines()
        #expect(loaded.count == 1)
    }
}
