import Testing
import Foundation
@testable import Core

/// Gauntlet Loop, Gauntlet B round 8 (2026-08-24): the identical bug class
/// round 7 found and fixed in `Finding`/`EvidenceItem`, found again in
/// `LedgerTransaction` by the round-8 critic while independently verifying
/// round 7's fix. `lineAccountIDs`/`lines` are non-optional with only an
/// `init(...)` parameter default — synthesized `Decodable` does not honor
/// that default for a missing key. Worse impact than the `Finding` case:
/// `ClientStore.loadImportedStatementLines()` is called un-guarded inside
/// `AppState.syncAndEvaluate()`'s main `do` block, so a decode failure here
/// fails the ENTIRE sync silently, not just the findings list.
@Suite("LedgerTransaction backward compatibility")
struct LedgerTransactionBackwardCompatibilityTests {
    static let oldFormatJSON = """
    {
      "id": "stmt-1",
      "entityKind": "Purchase",
      "vendorName": "Acme Co",
      "txnDate": { "year": 2026, "month": 3, "day": 1 },
      "totalAmount": { "minorUnits": 1000, "currency": "USD" },
      "paymentAccountID": null,
      "docNumber": null,
      "isVoided": false,
      "memo": null,
      "provenance": { "qboAPI": { "readAt": 780000000 } }
    }
    """

    @Test("A LedgerTransaction written before lineAccountIDs/lines existed decodes without throwing, defaulting both to empty")
    func decodesOldFormatJSON() throws {
        let txn = try JSONDecoder().decode(LedgerTransaction.self, from: Data(Self.oldFormatJSON.utf8))
        #expect(txn.lineAccountIDs == [])
        #expect(txn.lines == [])
        #expect(txn.syncToken == nil)
        #expect(txn.id == "stmt-1")
        #expect(txn.vendorName == "Acme Co")
    }

    @Test("A LedgerTransaction encoded with the current init and re-decoded round-trips exactly, including lineAccountIDs/lines/syncToken")
    func currentFormatRoundTrips() throws {
        let txn = LedgerTransaction(
            id: "p1",
            entityKind: .purchase,
            vendorName: "Acme Co",
            txnDate: AccountingDate(year: 2026, month: 3, day: 1),
            totalAmount: Money(minorUnits: 1000, currency: .usd),
            paymentAccountID: "35",
            docNumber: "REF-1",
            isVoided: false,
            memo: "note",
            lineAccountIDs: ["60"],
            lines: [LedgerTransactionLine(id: "1", accountID: "60")],
            syncToken: "0",
            provenance: .qboAPI(readAt: Date(timeIntervalSince1970: 780_000_000))
        )
        let data = try JSONEncoder().encode(txn)
        let decoded = try JSONDecoder().decode(LedgerTransaction.self, from: data)
        #expect(decoded == txn)
    }
}
