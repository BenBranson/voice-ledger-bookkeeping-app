import Testing
@testable import Core
import Foundation

@Suite("QBOWebLink")
struct QBOWebLinkTests {
    func txn(_ id: String, _ kind: QBOEntityKind, imported: Bool = false) -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: kind, vendorName: nil, txnDate: AccountingDate(year: 2026, month: 7, day: 1),
                          totalAmount: .zero, paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil,
                          provenance: imported ? .importedFile(documentID: "d", importedAt: Date(), extractionMethod: .deterministicParse, coverage: .complete) : .qboAPI(readAt: Date()))
    }

    @Test("Transactions route by entity type; sandbox uses the sandbox host")
    func transactionRoutes() {
        let txns = [txn("7", .bill), txn("8", .purchase), txn("9", .invoice)]
        #expect(QBOWebLink.url(forRecordID: "7", transactions: txns, accounts: [], isSandbox: true)?.absoluteString == "https://app.sandbox.qbo.intuit.com/app/bill?txnId=7")
        #expect(QBOWebLink.url(forRecordID: "8", transactions: txns, accounts: [], isSandbox: false)?.absoluteString == "https://app.qbo.intuit.com/app/expense?txnId=8")
        #expect(QBOWebLink.url(forRecordID: "9", transactions: txns, accounts: [], isSandbox: false)?.absoluteString == "https://app.qbo.intuit.com/app/invoice?txnId=9")
    }

    @Test("Balance sheet accounts open their register; P&L accounts fall back to the chart of accounts")
    func accountRoutes() {
        let accounts = [LedgerAccount(id: "34", name: "Opening Balance Equity", accountType: .equity), LedgerAccount(id: "5", name: "Advertising", accountType: .expense)]
        #expect(QBOWebLink.url(forRecordID: "34", transactions: [], accounts: accounts, isSandbox: false)?.absoluteString == "https://app.qbo.intuit.com/app/register?accountId=34")
        #expect(QBOWebLink.url(forRecordID: "5", transactions: [], accounts: accounts, isSandbox: false)?.absoluteString == "https://app.qbo.intuit.com/app/chartofaccounts")
    }

    @Test("Imported statement lines and unknown IDs get no link — there is no QBO record to open")
    func noLinkWithoutQBORecord() {
        #expect(QBOWebLink.url(forRecordID: "x", transactions: [txn("x", .purchase, imported: true)], accounts: [], isSandbox: false) == nil)
        #expect(QBOWebLink.url(forRecordID: "nope", transactions: [], accounts: [], isSandbox: false) == nil)
    }
}
