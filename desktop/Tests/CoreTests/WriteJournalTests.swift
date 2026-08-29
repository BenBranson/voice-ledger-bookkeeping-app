import Testing
import Foundation
@testable import Core

@Suite("WriteJournalResolution.resolve")
struct WriteJournalTests {
    func entry(syncTokenBeforeWrite: String = "3", targetAccountID: String = "acct-office") -> WriteJournalEntry {
        WriteJournalEntry(
            findingID: "f1", purchaseID: "p1", lineID: "l1",
            syncTokenBeforeWrite: syncTokenBeforeWrite, targetAccountID: targetAccountID
        )
    }

    @Test("id is deterministic from purchaseID and lineID, not a random UUID")
    func idIsDeterministic() {
        let e = entry()
        #expect(e.id == "p1:l1")
    }

    @Test("An unchanged SyncToken resolves to .failed — the write did not land")
    func unchangedSyncTokenResolvesFailed() {
        let result = WriteJournalResolution.resolve(entry: entry(), currentSyncToken: "3", currentAccountID: "acct-travel")
        #expect(result == .failed)
    }

    @Test("A changed SyncToken with the account matching the target resolves to .success")
    func changedSyncTokenMatchingTargetResolvesSuccess() {
        let result = WriteJournalResolution.resolve(entry: entry(targetAccountID: "acct-office"), currentSyncToken: "4", currentAccountID: "acct-office")
        #expect(result == .success)
    }

    @Test("A changed SyncToken with the account NOT matching the target resolves to .ambiguous — never guessed")
    func changedSyncTokenNotMatchingTargetResolvesAmbiguous() {
        let result = WriteJournalResolution.resolve(entry: entry(targetAccountID: "acct-office"), currentSyncToken: "4", currentAccountID: "acct-travel")
        #expect(result == .ambiguous)
    }

    @Test("A purchase that can no longer be found (nil SyncToken) resolves to .ambiguous, never guessed either way")
    func missingPurchaseResolvesAmbiguous() {
        let result = WriteJournalResolution.resolve(entry: entry(), currentSyncToken: nil, currentAccountID: nil)
        #expect(result == .ambiguous)
    }

    @Test("WriteJournalEntry round-trips through Codable, including a resolved state")
    func writeJournalEntryRoundTripsThroughCodable() throws {
        var e = entry()
        e.state = .unknown
        let data = try JSONEncoder().encode(e)
        let decoded = try JSONDecoder().decode(WriteJournalEntry.self, from: data)
        #expect(decoded.state == .unknown)
        #expect(decoded.id == "p1:l1")
    }
}
