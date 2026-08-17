import Testing
@testable import Core
import Foundation

@Suite("VL-CAT-UNCAT-001 — UncategorizedTransactionRule")
struct UncategorizedTransactionRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func account(id: String, name: String) -> LedgerAccount {
        LedgerAccount(id: id, name: name, accountType: .expense, accountSubType: "OtherMiscellaneousServiceCost", currentBalance: .zero)
    }

    func purchase(id: String, lineAccountIDs: [String], amountMinorUnits: Int64 = 50_000, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: "Some Vendor",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            lineAccountIDs: lineAccountIDs,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(transactions: [LedgerTransaction], accounts: [LedgerAccount], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions, accounts: accounts,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A Purchase line-coded to 'Uncategorized Expense' produces a .high-confidence finding")
    func uncategorizedExpenseProducesFinding() {
        let uncategorized = account(id: "31", name: "Uncategorized Expense")
        let txn = purchase(id: "1", lineAccountIDs: ["31"])
        let outcome = UncategorizedTransactionRule.evaluate(dataSet(transactions: [txn], accounts: [uncategorized]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("A Purchase coded to a real, non-catch-all account does NOT match")
    func realAccountDoesNotMatch() {
        let realAccount = account(id: "50", name: "Office Supplies")
        let txn = purchase(id: "1", lineAccountIDs: ["50"])
        let outcome = UncategorizedTransactionRule.evaluate(dataSet(transactions: [txn], accounts: [realAccount]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("An account merely named similarly (e.g. 'Uncategorized Expenses - Old') does NOT match — exact name only")
    func similarButNotExactNameDoesNotMatch() {
        let similar = account(id: "60", name: "Uncategorized Expenses - Old")
        let txn = purchase(id: "1", lineAccountIDs: ["60"])
        let outcome = UncategorizedTransactionRule.evaluate(dataSet(transactions: [txn], accounts: [similar]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — exact match only, no substring matching")
            return
        }
    }

    @Test("A voided transaction is excluded")
    func voidedTransactionExcluded() {
        let uncategorized = account(id: "31", name: "Uncategorized Expense")
        let txn = purchase(id: "1", lineAccountIDs: ["31"], isVoided: true)
        let outcome = UncategorizedTransactionRule.evaluate(dataSet(transactions: [txn], accounts: [uncategorized]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let uncategorized = account(id: "31", name: "Uncategorized Expense")
        let txn = purchase(id: "1", lineAccountIDs: ["31"], amountMinorUnits: 500)
        let outcome = UncategorizedTransactionRule.evaluate(dataSet(transactions: [txn], accounts: [uncategorized]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("No Uncategorized-named account present at all in this client's chart of accounts — no false match on an empty candidate set")
    func noUncategorizedAccountAtAll() {
        let realAccount = account(id: "50", name: "Office Supplies")
        let txn = purchase(id: "1", lineAccountIDs: ["50"])
        let outcome = UncategorizedTransactionRule.evaluate(dataSet(transactions: [txn], accounts: [realAccount]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = UncategorizedTransactionRule.evaluate(
            dataSet(transactions: [], accounts: [], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
