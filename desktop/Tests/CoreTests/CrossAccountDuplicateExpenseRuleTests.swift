import Testing
@testable import Core
import Foundation

@Suite("VL-DUP-EXP-002 — CrossAccountDuplicateExpenseRule")
struct CrossAccountDuplicateExpenseRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(id: String, vendor: String = "Permian Supply", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620, account: String = "checking-1", isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: date,
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: account,
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("Same vendor/amount/near-date, DIFFERENT payment account, produces a .medium-confidence finding")
    func crossAccountMatchProducesFinding() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("SAME payment account does NOT match — that's VL-DUP-EXP-001's territory, not this rule's")
    func samePaymentAccountDoesNotMatch() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "checking-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — same-account matches belong to VL-DUP-EXP-001")
            return
        }
    }

    @Test("More than 3 days apart does not match")
    func beyondNearDateWindowDoesNotMatch() {
        let a = purchase(id: "1", date: AccountingDate(year: 2026, month: 7, day: 1), account: "checking-1")
        let b = purchase(id: "2", date: AccountingDate(year: 2026, month: 7, day: 10), account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — beyond the 3-day window")
            return
        }
    }

    @Test("A voided purchase is excluded")
    func voidedPurchaseExcluded() {
        let a = purchase(id: "1", account: "checking-1")
        let b = purchase(id: "2", account: "amex-1", isVoided: true)
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let a = purchase(id: "1", amountMinorUnits: 500, account: "checking-1")
        let b = purchase(id: "2", amountMinorUnits: 500, account: "amex-1")
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A Bill with the same vendor/date/amount as a Purchase does not trigger this rule — entity-scoped to Purchase")
    func billEntityDoesNotMatch() {
        let aPurchase = purchase(id: "1", account: "checking-1")
        let theBill = LedgerTransaction(
            id: "2", entityKind: .bill, vendorName: "Permian Supply",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "ap-1", docNumber: nil, isVoided: false, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(dataSet([aPurchase, theBill]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — a Bill must not pair with a Purchase in this rule")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = CrossAccountDuplicateExpenseRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
