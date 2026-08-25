import Testing
@testable import Core

@Suite("ChartOfAccountsCleanup.findDuplicateCandidates")
struct ChartOfAccountsCleanupTests {
    private func makeAccount(id: String, name: String, type: LedgerAccountType, subType: String? = nil, fqn: String?) -> LedgerAccount {
        LedgerAccount(id: id, name: name, accountType: type, accountSubType: subType, currentBalance: .zero, fullyQualifiedName: fqn)
    }

    @Test("Two accounts with the identical normalized full path are a candidate group")
    func matchesOnFullyQualifiedName() {
        let a = makeAccount(id: "1", name: "Job Materials", type: .expense, subType: "SuppliesMaterialsCogs", fqn: "Job Costing:Job Materials")
        let b = makeAccount(id: "2", name: "Job Materials", type: .expense, subType: "SuppliesMaterialsCogs", fqn: "Job Costing:Job Materials")
        let groups = ChartOfAccountsCleanup.findDuplicateCandidates([a, b])
        #expect(groups.count == 1)
        #expect(groups[0].accounts.map(\.id).sorted() == ["1", "2"])
    }

    @Test("QBO's real false-positive pattern: same leaf name, Income vs Expense, does NOT match")
    func rejectsSameLeafNameAcrossTypes() {
        let income = makeAccount(id: "1", name: "Decks and Patios", type: .income, fqn: "Decks and Patios")
        let expense = makeAccount(id: "2", name: "Decks and Patios", type: .costOfGoodsSold, fqn: "Decks and Patios")
        let groups = ChartOfAccountsCleanup.findDuplicateCandidates([income, expense])
        #expect(groups.isEmpty)
    }

    @Test("Same leaf name under different parents, same type, does NOT match")
    func rejectsSameLeafNameDifferentParents() {
        let a = makeAccount(id: "1", name: "Repairs", type: .expense, fqn: "Vehicle Expenses:Repairs")
        let b = makeAccount(id: "2", name: "Repairs", type: .expense, fqn: "Building Expenses:Repairs")
        let groups = ChartOfAccountsCleanup.findDuplicateCandidates([a, b])
        #expect(groups.isEmpty)
    }

    @Test("An account with no fullyQualifiedName is excluded, never compared on leaf name")
    func excludesMissingFullyQualifiedName() {
        let a = makeAccount(id: "1", name: "Office Supplies", type: .expense, fqn: nil)
        let b = makeAccount(id: "2", name: "Office Supplies", type: .expense, fqn: nil)
        let groups = ChartOfAccountsCleanup.findDuplicateCandidates([a, b])
        #expect(groups.isEmpty)
    }

    @Test("Case and punctuation differences still match")
    func normalizesCaseAndPunctuation() {
        let a = makeAccount(id: "1", name: "Equipment Rental", type: .expense, fqn: "Job Costing:Equipment Rental")
        let b = makeAccount(id: "2", name: "equipment rental", type: .expense, fqn: "job costing: Equipment, Rental")
        let groups = ChartOfAccountsCleanup.findDuplicateCandidates([a, b])
        #expect(groups.count == 1)
    }

    @Test("A single account with no match anywhere produces no group")
    func noDuplicateNoGroup() {
        let a = makeAccount(id: "1", name: "Rent", type: .expense, fqn: "Overhead:Rent")
        #expect(ChartOfAccountsCleanup.findDuplicateCandidates([a]).isEmpty)
    }
}
