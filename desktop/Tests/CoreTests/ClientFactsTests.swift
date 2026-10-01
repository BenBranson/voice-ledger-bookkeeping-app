import Testing
@testable import Core
import Foundation

@Suite("ClientFacts — one set of answers for pages and Moneypenny")
struct ClientFactsTests {
    func usd(_ c: Int64) -> Money { Money(minorUnits: c, currency: .usd) }
    let period = AccountingPeriod(year: 2026, month: 7)
    func txn(_ id: String, _ cents: Int64, vendor: String = "V", account: String = "sw", month: Int = 7) -> LedgerTransaction {
        LedgerTransaction(id: id, entityKind: .purchase, vendorName: vendor, txnDate: AccountingDate(year: 2026, month: month, day: 5), totalAmount: usd(cents),
                          paymentAccountID: account, docNumber: nil, isVoided: false, memo: nil, provenance: .qboAPI(readAt: Date()))
    }
    func history(_ txns: [LedgerTransaction], accounts: [LedgerAccount]) -> HistorySnapshot {
        HistorySnapshot(realmID: RealmID(rawValue: "r"), fetchedAt: Date(), from: AccountingDate(year: 2025, month: 1, day: 1), through: AccountingDate(year: 2026, month: 7, day: 31),
                        transactions: txns, deposits: [], vendorCredits: [], accounts: accounts, monthlyProfitAndLoss: [], latestBalanceSheet: [], latestCashFlow: [], coverage: .complete)
    }

    @Test("Search sees the 24-month history, not just the current month — same as the Search by Amount page")
    func searchUsesHistory() throws {
        let old = txn("old", 142_000, month: 3)
        let data = ClientData(period: period, transactions: [txn("new", 5_000)], history: history([old], accounts: []))
        let result = try #require(ClientFacts.searchAmount(data, text: "$1,420.00").value)
        #expect(result.exact.map(\.id) == ["old"])
        #expect(ClientFacts.searchAmount(data, text: "$500").value?.exact.isEmpty == true)   // "$500" now parses
    }

    @Test("An account balance is answered with the balance, not 'sync the dashboard'")
    func balance() throws {
        let acct = LedgerAccount(id: "sw", name: "VL Spike Sweeper Checking", accountType: .bank, currentBalance: usd(-329_302))
        let data = ClientData(period: period, accounts: [acct], freshness: .cached(at: Date(timeIntervalSinceNow: -7_200)))
        let fact = ClientFacts.accountBalance(data, name: "sweeper")
        #expect(fact.value?.balance == usd(-329_302))
        #expect(fact.scope.sentence().contains("saved data"))
        #expect(ClientFacts.accountBalance(data, name: "nope").value == nil)
    }

    @Test("Balance-explaining search finds the account and its postings")
    func balanceSearch() throws {
        let acct = LedgerAccount(id: "sw", name: "Sweeper", accountType: .bank, currentBalance: usd(-300_000))
        let data = ClientData(period: period, transactions: [txn("a", 200_000), txn("b", 100_000)], accounts: [acct])
        let r = try #require(ClientFacts.searchAmount(data, text: "3000").value)
        #expect(r.exact.isEmpty && r.balanceAccounts.first?.postings.count == 2)
    }

    @Test("Finding groups use the SAME rule sets the pages use")
    func groups() {
        #expect(FactFindingGroup.cleanupAssessment.ruleIDs == CleanupCategory.ruleIDs)
        #expect(FactFindingGroup.balanceSheetIntegrity.ruleIDs == CleanupCategory.ruleIDs(in: .balanceSheetIntegrity))
        #expect(FactFindingGroup.allOpen.ruleIDs == nil)
    }

    @Test("What we owe a vendor comes from aged payables, split into current and past due")
    func amountOwed() throws {
        let row = AgingLine(label: "Norton Lumber and Building Materials", current: usd(75_693), days1to30: usd(0), days31to60: usd(0), days61to90: usd(0), days91AndOver: usd(139_300), total: usd(214_993), depth: 0, isSummary: false)
        let total = AgingLine(label: "TOTAL", current: usd(75_693), days1to30: nil, days31to60: nil, days61to90: nil, days91AndOver: usd(139_300), total: usd(214_993), depth: 0, isSummary: true)
        let data = ClientData(period: period, freshness: .synced(at: Date()), agedPayables: [row, total])
        let owed = try #require(ClientFacts.amountOwed(data, vendor: "norton lumber").value)
        #expect(owed.total == usd(214_993) && owed.current == usd(75_693) && owed.overdue == usd(139_300) && owed.over90 == usd(139_300))
        #expect(ClientFacts.amountOwed(data, vendor: "acme").value == nil)
        #expect(ClientFacts.amountOwed(ClientData(period: period), vendor: "norton").note?.contains("isn't loaded") == true)
    }

    @Test("Freshness reads the same everywhere: never / cached / synced")
    func freshness() {
        let now = Date()
        #expect(Freshness.neverSynced.sentence(now: now).hasPrefix("Not synced"))
        #expect(Freshness.cached(at: now.addingTimeInterval(-7_200)).sentence(now: now).contains("2 hours ago"))
        #expect(Freshness.synced(at: now.addingTimeInterval(-30)).sentence(now: now).contains("just now"))
    }
}
