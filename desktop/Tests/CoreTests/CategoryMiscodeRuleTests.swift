import Testing
@testable import Core
import Foundation

@Suite("VL-CAT-MISCODE-001 — CategoryMiscodeRule")
struct CategoryMiscodeRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func account(id: String, name: String) -> LedgerAccount {
        LedgerAccount(id: id, name: name, accountType: .expense)
    }

    func purchase(
        id: String,
        vendor: String?,
        accountID: String?,
        amountMinorUnits: Int64 = 10_000,
        isVoided: Bool = false,
        entityKind: QBOEntityKind = .purchase
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: entityKind,
            vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            lineAccountIDs: accountID.map { [$0] } ?? [],
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(current: [LedgerTransaction], prior: [LedgerTransaction], accounts: [LedgerAccount], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: current, accounts: accounts,
            priorPeriodTransactions: prior,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    var accounts: [LedgerAccount] { [account(id: "acct-office", name: "Office Supplies"), account(id: "acct-travel", name: "Travel")] }

    @Test("A vendor consistently coded to one account, now coded elsewhere, produces a finding")
    func miscodeProducesFinding() {
        let prior = [
            purchase(id: "0", vendor: "Staples", accountID: "acct-office"),
            purchase(id: "-1", vendor: "Staples", accountID: "acct-office")
        ]
        let current = [purchase(id: "1", vendor: "Staples", accountID: "acct-travel")]
        let outcome = CategoryMiscodeRule.evaluate(dataSet(current: current, prior: prior, accounts: accounts), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A vendor coded to the same account as its history produces .pass")
    func consistentCodingProducesPass() {
        let prior = [
            purchase(id: "0", vendor: "Staples", accountID: "acct-office"),
            purchase(id: "-1", vendor: "Staples", accountID: "acct-office")
        ]
        let current = [purchase(id: "1", vendor: "Staples", accountID: "acct-office")]
        let outcome = CategoryMiscodeRule.evaluate(dataSet(current: current, prior: prior, accounts: accounts), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — coding matches history")
            return
        }
    }

    @Test("Only one prior-period transaction is not enough history to establish a pattern")
    func singlePriorTransactionInsufficientHistory() {
        let prior = [purchase(id: "0", vendor: "Staples", accountID: "acct-office")]
        let current = [purchase(id: "1", vendor: "Staples", accountID: "acct-travel")]
        let outcome = CategoryMiscodeRule.evaluate(dataSet(current: current, prior: prior, accounts: accounts), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — only one prior transaction, not a real pattern")
            return
        }
    }

    @Test("A vendor with a mixed prior-period coding history has no stable baseline, so no finding")
    func mixedHistoryHasNoBaseline() {
        let prior = [
            purchase(id: "0", vendor: "Staples", accountID: "acct-office"),
            purchase(id: "-1", vendor: "Staples", accountID: "acct-travel")
        ]
        let current = [purchase(id: "1", vendor: "Staples", accountID: "acct-office")]
        let outcome = CategoryMiscodeRule.evaluate(dataSet(current: current, prior: prior, accounts: accounts), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — the vendor's own history is mixed, so there's no single baseline to compare against")
            return
        }
    }

    @Test("A split (multi-line) current transaction is excluded, even against a clear history")
    func splitTransactionExcluded() {
        let prior = [
            purchase(id: "0", vendor: "Staples", accountID: "acct-office"),
            purchase(id: "-1", vendor: "Staples", accountID: "acct-office")
        ]
        let current = LedgerTransaction(
            id: "1", entityKind: .purchase, vendorName: "Staples",
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: 10_000, currency: .usd),
            paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil,
            lineAccountIDs: ["acct-office", "acct-travel"],
            provenance: .qboAPI(readAt: Date())
        )
        let outcome = CategoryMiscodeRule.evaluate(dataSet(current: [current], prior: prior, accounts: accounts), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — a split transaction has no single current account to compare")
            return
        }
    }

    @Test("No prior period data fetched produces .cannotEvaluate")
    func noPriorDataCannotEvaluate() {
        let current = [purchase(id: "1", vendor: "Staples", accountID: "acct-travel")]
        let outcome = CategoryMiscodeRule.evaluate(dataSet(current: current, prior: [], accounts: accounts), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no prior period data at all")
            return
        }
    }

    @Test("A Bill is excluded from both periods")
    func billExcluded() {
        let prior = [
            purchase(id: "0", vendor: "Staples", accountID: "acct-office", entityKind: .bill),
            purchase(id: "-1", vendor: "Staples", accountID: "acct-office", entityKind: .bill)
        ]
        let current = [purchase(id: "1", vendor: "Staples", accountID: "acct-travel", entityKind: .bill)]
        let outcome = CategoryMiscodeRule.evaluate(dataSet(current: current, prior: prior, accounts: accounts), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — bills are excluded from this rule entirely")
            return
        }
    }
}
