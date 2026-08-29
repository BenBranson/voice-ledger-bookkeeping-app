import Testing
@testable import Core
import Foundation

@Suite("VL-RELATIONSHIP-003 — BankTransferMiscodedRule")
struct BankTransferMiscodedRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String? = nil,
        paymentAccountID: String?,
        lineAccountIDs: [String],
        amountMinorUnits: Int64 = 100_000,
        isVoided: Bool = false
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: paymentAccountID,
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            lineAccountIDs: lineAccountIDs,
            provenance: .qboAPI(readAt: Date())
        )
    }

    let accounts = [
        LedgerAccount(id: "checking", name: "Checking", accountType: .bank),
        LedgerAccount(id: "savings", name: "Savings", accountType: .bank),
        LedgerAccount(id: "office-expense", name: "Office Expenses", accountType: .expense)
    ]

    func dataSet(transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions, accounts: accounts,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A purchase coded to another bank account produces a finding")
    func lineToAnotherBankAccountProducesFinding() {
        let txn = purchase(id: "1", paymentAccountID: "checking", lineAccountIDs: ["savings"])
        let outcome = BankTransferMiscodedRule.evaluate(dataSet(transactions: [txn]), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A purchase coded to an expense account produces .pass")
    func normalExpenseProducesPass() {
        let txn = purchase(id: "1", paymentAccountID: "checking", lineAccountIDs: ["office-expense"])
        let outcome = BankTransferMiscodedRule.evaluate(dataSet(transactions: [txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — coded to a normal expense account")
            return
        }
    }

    @Test("A line coded to the same account it was paid from is excluded as nonsensical data")
    func selfReferencingLineExcluded() {
        let txn = purchase(id: "1", paymentAccountID: "checking", lineAccountIDs: ["checking"])
        let outcome = BankTransferMiscodedRule.evaluate(dataSet(transactions: [txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — self-referencing line, not a real transfer signal")
            return
        }
    }

    @Test("A voided transaction is excluded")
    func voidedTransactionExcluded() {
        let txn = purchase(id: "1", paymentAccountID: "checking", lineAccountIDs: ["savings"], isVoided: true)
        let outcome = BankTransferMiscodedRule.evaluate(dataSet(transactions: [txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — voided transaction excluded")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let txn = purchase(id: "1", paymentAccountID: "checking", lineAccountIDs: ["savings"], amountMinorUnits: 500)
        let outcome = BankTransferMiscodedRule.evaluate(dataSet(transactions: [txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — below materiality floor")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = BankTransferMiscodedRule.evaluate(
            dataSet(transactions: [], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
