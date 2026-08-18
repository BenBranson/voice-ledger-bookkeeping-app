import Testing
import Foundation
@testable import Core

@Suite("WriteVerificationResult")
struct WriteVerificationResultTests {
    @Test("Decodes a real-shaped verified:true response, matching the backend's live-verified JSON")
    func decodesVerifiedResponse() throws {
        let json = """
        {
          "verified": true,
          "purchaseId": "227",
          "lineId": "1",
          "oldAccountId": "1150040001",
          "newAccountId": "1150040014",
          "newSyncToken": "1",
          "unexpectedFieldChanges": [],
          "otherLinesUnchanged": true,
          "before": {},
          "after": {}
        }
        """
        let result = try JSONDecoder().decode(WriteVerificationResult.self, from: Data(json.utf8))
        #expect(result.verified == true)
        #expect(result.purchaseID == "227")
        #expect(result.oldAccountID == "1150040001")
        #expect(result.newAccountID == "1150040014")
        #expect(result.newSyncToken == "1")
        #expect(result.unexpectedFieldChanges.isEmpty)
        #expect(result.otherLinesUnchanged == true)
    }

    @Test("Decodes a verified:false response with populated unexpectedFieldChanges — the caller must be able to see WHY it failed")
    func decodesUnverifiedResponse() throws {
        let json = """
        {
          "verified": false,
          "purchaseId": "227",
          "lineId": "1",
          "oldAccountId": "1150040001",
          "newAccountId": "1150040014",
          "newSyncToken": "1",
          "unexpectedFieldChanges": ["DocNumber", "TotalAmt"],
          "otherLinesUnchanged": false
        }
        """
        let result = try JSONDecoder().decode(WriteVerificationResult.self, from: Data(json.utf8))
        #expect(result.verified == false)
        #expect(result.unexpectedFieldChanges == ["DocNumber", "TotalAmt"])
        #expect(result.otherLinesUnchanged == false)
    }

    @Test("A null newSyncToken and oldAccountId decode as nil, not a crash — the backend returns null when its own verification read failed to find the entity")
    func decodesNullOptionalFields() throws {
        let json = """
        {
          "verified": false,
          "purchaseId": "227",
          "lineId": "1",
          "oldAccountId": null,
          "newAccountId": "1150040014",
          "newSyncToken": null,
          "unexpectedFieldChanges": ["DocNumber", "PrivateNote", "TotalAmt", "EntityRef", "AccountRef", "TxnDate"],
          "otherLinesUnchanged": false
        }
        """
        let result = try JSONDecoder().decode(WriteVerificationResult.self, from: Data(json.utf8))
        #expect(result.oldAccountID == nil)
        #expect(result.newSyncToken == nil)
    }
}
