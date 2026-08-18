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

    @Test("dismissFinding marks an open finding dismissed")
    func dismissFindingMarksDismissed() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        try await store.upsertFindings([sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))])
        try await store.dismissFinding(id: "abc123")
        let loaded = try await store.loadFindings()
        #expect(loaded[0].status == .dismissed)
    }

    @Test("dismissFinding is a no-op for an unknown id — no crash, nothing created")
    func dismissFindingUnknownIDIsNoOp() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        try await store.dismissFinding(id: "does-not-exist")
        let loaded = try await store.loadFindings()
        #expect(loaded.isEmpty)
    }

    @Test("dismissFinding does not override an already-resolved finding's status")
    func dismissFindingDoesNotOverrideResolved() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        var finding = sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))
        finding.status = .resolved
        try await store.upsertFindings([finding])
        try await store.dismissFinding(id: "abc123")
        let loaded = try await store.loadFindings()
        #expect(loaded[0].status == .resolved)
    }

    @Test("A re-detected finding upserted after being dismissed carries the dismissed status forward, not silently reopened")
    func upsertPreservesDismissedStatus() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        try await store.upsertFindings([sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))])
        try await store.dismissFinding(id: "abc123")
        // Same rule redetects the exact same finding on the next sync.
        try await store.upsertFindings([sampleFinding(id: "abc123", realmID: RealmID(rawValue: "realm-a"))])
        let loaded = try await store.loadFindings()
        #expect(loaded[0].status == .dismissed)
    }

    @Test("Client memory rules round-trip: add then load returns the same rule")
    func clientMemoryRulesRoundTrip() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let rule = ClientMemoryRule(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), vendorName: "VL Spike Amex", createdBy: "Benjamin Branson")
        try await store.addClientMemoryRule(rule)
        let loaded = try await store.loadClientMemoryRules()
        #expect(loaded.count == 1)
        #expect(loaded[0].id == rule.id)
        #expect(loaded[0].vendorName == "VL Spike Amex")
    }

    @Test("Adding two different client memory rules keeps both")
    func addingMultipleRulesKeepsBoth() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        try await store.addClientMemoryRule(ClientMemoryRule(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), vendorName: "VL Spike Amex", createdBy: "Test"))
        try await store.addClientMemoryRule(ClientMemoryRule(ruleID: RuleID(rawValue: "VL-PAYROLL-LUMP-001"), vendorName: "VL Spike ADP", createdBy: "Test"))
        let loaded = try await store.loadClientMemoryRules()
        #expect(loaded.count == 2)
    }

    @Test("removeClientMemoryRule is the reverse of addClientMemoryRule")
    func removeClientMemoryRuleReversesAdd() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let rule = ClientMemoryRule(ruleID: RuleID(rawValue: "VL-CC-PAYMENT-001"), vendorName: "VL Spike Amex", createdBy: "Test")
        try await store.addClientMemoryRule(rule)
        try await store.removeClientMemoryRule(id: rule.id)
        let loaded = try await store.loadClientMemoryRules()
        #expect(loaded.isEmpty)
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

    @Test("Checklist completions round-trip: upsert then load returns the same completion")
    func checklistCompletionsRoundTrip() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let completion = ChecklistItemCompletion(
            itemID: ChecklistItemID(rawValue: "resolve-cleanup-assessment"),
            period: AccountingPeriod(year: 2026, month: 7),
            completedBy: "Benjamin Branson"
        )
        try await store.upsertChecklistCompletion(completion)
        let loaded = try await store.loadChecklistCompletions()
        #expect(loaded.count == 1)
        #expect(loaded[0].completedBy == "Benjamin Branson")
    }

    @Test("Re-upserting a completion for the same item and period replaces the prior one, not duplicates it")
    func checklistCompletionUpsertReplacesPrior() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let itemID = ChecklistItemID(rawValue: "resolve-cleanup-assessment")
        let period = AccountingPeriod(year: 2026, month: 7)
        try await store.upsertChecklistCompletion(ChecklistItemCompletion(itemID: itemID, period: period, completedBy: "First Name"))
        try await store.upsertChecklistCompletion(ChecklistItemCompletion(itemID: itemID, period: period, completedBy: "Corrected Name"))
        let loaded = try await store.loadChecklistCompletions()
        #expect(loaded.count == 1)
        #expect(loaded[0].completedBy == "Corrected Name")
    }

    @Test("The same item completed in two different periods produces two separate completions")
    func sameItemDifferentPeriodsAreSeparate() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let itemID = ChecklistItemID(rawValue: "resolve-cleanup-assessment")
        try await store.upsertChecklistCompletion(ChecklistItemCompletion(itemID: itemID, period: AccountingPeriod(year: 2026, month: 6), completedBy: "Benjamin Branson"))
        try await store.upsertChecklistCompletion(ChecklistItemCompletion(itemID: itemID, period: AccountingPeriod(year: 2026, month: 7), completedBy: "Benjamin Branson"))
        let loaded = try await store.loadChecklistCompletions()
        #expect(loaded.count == 2)
    }

    @Test("Removing a checklist completion is the reverse of upserting it")
    func removeChecklistCompletion() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let itemID = ChecklistItemID(rawValue: "resolve-cleanup-assessment")
        let period = AccountingPeriod(year: 2026, month: 7)
        try await store.upsertChecklistCompletion(ChecklistItemCompletion(itemID: itemID, period: period, completedBy: "Benjamin Branson"))
        try await store.removeChecklistCompletion(itemID: itemID, period: period)
        let loaded = try await store.loadChecklistCompletions()
        #expect(loaded.isEmpty)
    }

    @Test("Mapping hints round-trip: upsert then load returns the learned fields")
    func mappingHintsRoundTrip() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let headers = ["Date", "Description", "Amount"]
        try await store.upsertMappingHint(headers: headers, fields: [.date, .description, .amount])
        let loaded = try await store.loadMappingHints()
        #expect(loaded.count == 1)
        #expect(loaded[0].headers == headers)
        #expect(loaded[0].fields == [.date, .description, .amount])
        #expect(loaded[0].timesUsed == 1)
    }

    @Test("Re-upserting the same header shape increments timesUsed and replaces fields, rather than accumulating duplicates")
    func mappingHintUpsertIncrementsAndReplaces() async throws {
        let store = try ClientStore(realmID: RealmID(rawValue: "realm-a"), rootDirectory: tempRoot())
        let headers = ["Date", "Description", "Amount"]
        try await store.upsertMappingHint(headers: headers, fields: [.date, .description, .amount])
        // A correction: the human decides "Description" should actually be ignored this time.
        try await store.upsertMappingHint(headers: headers, fields: [.date, .ignored, .amount])
        let loaded = try await store.loadMappingHints()
        #expect(loaded.count == 1)
        #expect(loaded[0].timesUsed == 2)
        #expect(loaded[0].fields == [.date, .ignored, .amount])
    }

    @Test("A header row differing only in case/whitespace still matches the same hint id")
    func mappingHintIDIsCaseAndWhitespaceInsensitive() {
        let a = MappingHint.makeID(headers: ["Date", "Description", "Amount"])
        let b = MappingHint.makeID(headers: [" date ", "DESCRIPTION", "amount"])
        #expect(a == b)
    }

    @Test("A different header shape (reordered or renamed) produces a different hint id — never fuzzy-matched")
    func mappingHintIDDiffersForDifferentHeaderShape() {
        let a = MappingHint.makeID(headers: ["Date", "Description", "Amount"])
        let reordered = MappingHint.makeID(headers: ["Description", "Date", "Amount"])
        let renamed = MappingHint.makeID(headers: ["Date", "Memo", "Amount"])
        #expect(a != reordered)
        #expect(a != renamed)
    }
}
