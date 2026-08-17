import Testing
import Foundation
import Core
@testable import IntegrationsQuickBooks

/// No network access — decodes synthetic JSON in the real shape confirmed
/// against the live sandbox by Wave 1's `testPurchasesRead`
/// (docs/phase-0/SPIKE_QUEUE.md item 6). `isVoided` detection: verified
/// 2026-08-17 (spike item 51) — a manually-voided Purchase carries a
/// top-level `"status": "Voided"` field, absent entirely on non-voided
/// Purchases including the $0 VL-SPIKE-ZERO fixture that broke the earlier
/// `TotalAmt == 0` heuristic. See `QBORawPurchase.swift`'s doc comment.
@Suite("QBOSyncClient normalization")
struct QBOSyncClientTests {
    @Test("Decodes a real-shaped Purchase query response and normalizes vendor/date/amount/account/docNumber")
    func decodesAndNormalizesPurchase() throws {
        let json = """
        {
          "QueryResponse": {
            "Purchase": [
              {
                "Id": "145",
                "TxnDate": "2026-07-14",
                "TotalAmt": 486.20,
                "DocNumber": "4471",
                "PrivateNote": "spike seed",
                "AccountRef": { "value": "35", "name": "Checking" },
                "EntityRef": { "value": "62", "name": "Permian Supply" }
              }
            ],
            "startPosition": 1,
            "maxResults": 1
          },
          "time": "2026-08-16T21:00:00.000Z"
        }
        """
        let response = try JSONDecoder().decode(QBOPurchaseQueryResponse.self, from: Data(json.utf8))
        let raw = try #require(response.queryResponse.purchase?.first)
        let normalized = QBOSyncClient.normalize(raw)

        #expect(normalized.id == "145")
        #expect(normalized.vendorName == "Permian Supply")
        #expect(normalized.txnDate == AccountingDate(year: 2026, month: 7, day: 14))
        #expect(normalized.totalAmount == Money(minorUnits: 48_620, currency: .usd))
        #expect(normalized.paymentAccountID == "35")
        #expect(normalized.docNumber == "4471")
        #expect(normalized.isVoided == false) // no "status" field present
    }

    @Test("A TotalAmt of 0 with no status field is NOT treated as voided (Purchase #146, the legitimate $0 VL-SPIKE-ZERO fixture — the case that broke the old TotalAmt==0 heuristic)")
    func zeroTotalAmtWithoutStatusFieldIsNotVoided() throws {
        let json = """
        {
          "Id": "146", "TxnDate": "2026-07-01", "TotalAmt": 0,
          "AccountRef": { "value": "35" }, "EntityRef": { "value": "62", "name": "Permian Supply" },
          "PrivateNote": "VL-SPIKE-ZERO"
        }
        """
        let raw = try JSONDecoder().decode(QBORawPurchase.self, from: Data(json.utf8))
        #expect(QBOSyncClient.normalize(raw).isVoided == false)
    }

    @Test("A Purchase with status: Voided is treated as voided — the real, verified signal (Purchase #151, spike item 51)")
    func statusVoidedFieldIsTreatedAsVoided() throws {
        let json = """
        {
          "Id": "151", "TxnDate": "2026-07-14", "TotalAmt": 0, "DocNumber": "4471-DUP",
          "AccountRef": { "value": "1150040000" }, "EntityRef": { "value": "58", "name": "VL Spike Permian Supply" },
          "PrivateNote": "Voided - VL-SPIKE-DUP-B", "status": "Voided"
        }
        """
        let raw = try JSONDecoder().decode(QBORawPurchase.self, from: Data(json.utf8))
        #expect(raw.isVoided == true)
        #expect(QBOSyncClient.normalize(raw).isVoided == true)
    }

    @Test("Line-level AccountRef decodes into lineAccountIDs, for VL-CC-PAYMENT-001")
    func decodesLineAccountIDs() throws {
        let json = """
        {
          "Id": "1", "TxnDate": "2026-07-20", "TotalAmt": 500,
          "AccountRef": { "value": "35" }, "EntityRef": { "value": "62", "name": "Amex" },
          "Line": [
            { "Amount": 500, "DetailType": "AccountBasedExpenseLineDetail",
              "AccountBasedExpenseLineDetail": { "AccountRef": { "value": "expense-1" } } }
          ]
        }
        """
        let raw = try JSONDecoder().decode(QBORawPurchase.self, from: Data(json.utf8))
        #expect(raw.lineAccountIDs == ["expense-1"])
        #expect(QBOSyncClient.normalize(raw).lineAccountIDs == ["expense-1"])
    }

    @Test("A line with no AccountBasedExpenseLineDetail (e.g. a different DetailType) is skipped, not guessed at")
    func skipsLinesWithoutAccountBasedDetail() throws {
        let json = """
        {
          "Id": "1", "TxnDate": "2026-07-20", "TotalAmt": 500,
          "Line": [
            { "Amount": 500, "DetailType": "ItemBasedExpenseLineDetail" }
          ]
        }
        """
        let raw = try JSONDecoder().decode(QBORawPurchase.self, from: Data(json.utf8))
        #expect(raw.lineAccountIDs.isEmpty)
    }

    @Test("Account decoding maps a real AccountType string to LedgerAccountType, and rejects an unrecognized one rather than guessing")
    func decodesAccountsAndRejectsUnknownType() throws {
        let json = """
        {
          "QueryResponse": {
            "Account": [
              { "Id": "1", "Name": "Amex", "AccountType": "Credit Card" },
              { "Id": "2", "Name": "Office Supplies", "AccountType": "Expense" },
              { "Id": "3", "Name": "Some New Type QBO Adds Later", "AccountType": "Something Unrecognized" }
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOAccountQueryResponse.self, from: Data(json.utf8))
        let rawAccounts = try #require(response.queryResponse.account)
        #expect(rawAccounts.count == 3)

        let normalized = rawAccounts.compactMap { QBOSyncClient.normalize($0) }
        #expect(normalized.count == 2) // the unrecognized type is dropped, not guessed at
        #expect(normalized.first { $0.id == "1" }?.accountType == .creditCard)
        #expect(normalized.first { $0.id == "2" }?.accountType == .expense)
        #expect(normalized.first { $0.id == "3" } == nil)
    }

    @Test("CompanyInfo decodes as a direct object, not a QueryResponse wrapper — verified against the live sandbox shape")
    func decodesCompanyInfo() throws {
        let json = """
        {
          "CompanyInfo": {
            "Id": "1",
            "CompanyName": "Sandbox Company US 1c1b"
          },
          "time": "2026-08-17T10:20:22.789-07:00"
        }
        """
        let response = try JSONDecoder().decode(QBORawCompanyInfoResponse.self, from: Data(json.utf8))
        #expect(response.companyInfo.companyName == "Sandbox Company US 1c1b")
        #expect(response.companyInfo.id == "1")
    }

    @Test("Decodes a real-shaped Invoice query response and normalizes customer/date/amount, entityKind == .invoice")
    func decodesAndNormalizesInvoice() throws {
        let json = """
        {
          "QueryResponse": {
            "Invoice": [
              {
                "Id": "220",
                "TxnDate": "2026-07-14",
                "TotalAmt": 500.00,
                "DocNumber": "1010",
                "CustomerRef": { "value": "1", "name": "Amy's Bird Sanctuary" }
              }
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOInvoiceQueryResponse.self, from: Data(json.utf8))
        let raw = try #require(response.queryResponse.invoice?.first)
        let normalized = QBOSyncClient.normalize(raw)

        #expect(normalized.id == "220")
        #expect(normalized.entityKind == .invoice)
        #expect(normalized.vendorName == "Amy's Bird Sanctuary")
        #expect(normalized.totalAmount == Money(minorUnits: 50_000, currency: .usd))
        #expect(normalized.isVoided == false)
    }

    @Test("Preferences decoding reads VendorAndPurchasesPrefs.UseCustomTxnNumbers")
    func decodesPreferences() throws {
        let json = """
        {
          "QueryResponse": {
            "Preferences": [
              { "VendorAndPurchasesPrefs": { "UseCustomTxnNumbers": true } }
            ]
          }
        }
        """
        let response = try JSONDecoder().decode(QBOPreferencesQueryResponse.self, from: Data(json.utf8))
        #expect(response.queryResponse.preferences?.first?.vendorAndPurchasesPrefs?.useCustomTxnNumbers == true)
    }

    @Test("Money conversion from QBO's decimal TotalAmt to integer minor units is exact")
    func minorUnitsConversionIsExact() {
        #expect(QBOSyncClient.minorUnits(from: Decimal(string: "486.20")!) == 48_620)
        #expect(QBOSyncClient.minorUnits(from: Decimal(string: "0.05")!) == 5)
        #expect(QBOSyncClient.minorUnits(from: Decimal(string: "1200")!) == 120_000)
    }

    @Test("dateRange computes correct month boundaries, including a 31-day and a 28-day month")
    func dateRangeMonthBoundaries() {
        let july = QBOSyncClient.dateRange(for: AccountingPeriod(year: 2026, month: 7))
        #expect(july.start == "2026-07-01")
        #expect(july.end == "2026-07-31")

        let feb = QBOSyncClient.dateRange(for: AccountingPeriod(year: 2026, month: 2))
        #expect(feb.start == "2026-02-01")
        #expect(feb.end == "2026-02-28") // 2026 is not a leap year
    }
}
