import Testing
@testable import Core
import Foundation

@Suite("Search by Amount — balances and combinations")
struct AmountSearchBalanceTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    func txn(_ id: String, _ cents: Int64, account: String = "sw") -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: .purchase, vendorName: "V", txnDate: AccountingDate(year: 2026, month: 7, day: 1), totalAmount: usd(cents),
                          paymentAccountID: account, docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
    }

    @Test("An overdrawn balance is recognized as an account balance, with its postings")
    func balance() {
        let account = LedgerAccount(id: "sw", name: "Sweeper Checking", accountType: .bank, currentBalance: usd(-329_302))
        #expect(AmountSearch.accountsWithBalance(usd(329_302), in: [account]).map(\.id) == ["sw"])
        let txns = [txn("1", 200_000), txn("2", 129_302), txn("3", 5_000, account: "other")]
        #expect(AmountSearch.transactions(for: account, in: txns).map(\.id) == ["1", "2"])
    }

    @Test("A clearing/suspense account's postings are the transactions coded TO it, not just paid from it")
    func codedToAccount() {
        let clearing = LedgerAccount(id: "clr", name: "Payroll Clearing", accountType: .otherCurrentAsset, currentBalance: usd(142_000))
        let coded = LedgerTransaction(id: "t", entityKind: .purchase, vendorName: "V", txnDate: AccountingDate(year: 2026, month: 3, day: 15), totalAmount: usd(142_000),
                                      paymentAccountID: "bank", docNumber: nil, isVoided: false, memo: nil, lineAccountIDs: ["clr"], provenance: .qboAPI(readAt: Date()))
        #expect(AmountSearch.transactions(for: clearing, in: [coded]).map(\.id) == ["t"])
    }

    @Test("Finds two or three transactions that add up to the amount")
    func combination() {
        let txns = [txn("a", 100_000), txn("b", 29_302), txn("c", 200_000), txn("d", 7)]
        #expect(Set(AmountSearch.combination(matching: usd(329_302), in: txns)!.map(\.id)) == ["a", "b", "c"])
        #expect(Set(AmountSearch.combination(matching: usd(129_302), in: txns)!.map(\.id)) == ["a", "b"])
        #expect(AmountSearch.combination(matching: usd(1), in: txns) == nil)
    }
}
