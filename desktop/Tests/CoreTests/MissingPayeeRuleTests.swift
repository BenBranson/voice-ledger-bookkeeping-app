import Testing
@testable import Core
import Foundation

@Suite("VL-MISSING-PAYEE-001 — MissingPayeeRule")
struct MissingPayeeRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(id: String, vendorName: String?, amountMinorUnits: Int64 = 50_000, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendorName,
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            lineAccountIDs: [],
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions, accounts: [],
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A Purchase with no vendor at all produces a .high-confidence finding")
    func purchaseWithNoVendorProducesFinding() {
        let txn = purchase(id: "1", vendorName: nil)
        let outcome = MissingPayeeRule.evaluate(dataSet(transactions: [txn]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
        #expect(findings[0].vendorName == nil)
    }

    @Test("A Purchase WITH a vendor does NOT match")
    func purchaseWithVendorDoesNotMatch() {
        let txn = purchase(id: "1", vendorName: "Real Vendor")
        let outcome = MissingPayeeRule.evaluate(dataSet(transactions: [txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A voided transaction with no vendor is excluded")
    func voidedTransactionExcluded() {
        let txn = purchase(id: "1", vendorName: nil, isVoided: true)
        let outcome = MissingPayeeRule.evaluate(dataSet(transactions: [txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A zero-amount transaction with no vendor is excluded — the spec is 'dollar amount > $0'")
    func zeroAmountExcluded() {
        let txn = purchase(id: "1", vendorName: nil, amountMinorUnits: 0)
        let outcome = MissingPayeeRule.evaluate(dataSet(transactions: [txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let txn = purchase(id: "1", vendorName: nil, amountMinorUnits: 500)
        let outcome = MissingPayeeRule.evaluate(dataSet(transactions: [txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A non-Purchase entity (e.g. a Bill) is not evaluated by this rule")
    func nonPurchaseEntityIgnored() {
        let bill = LedgerTransaction(
            id: "1", entityKind: .bill, vendorName: nil,
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 50_000, currency: .usd),
            paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil,
            lineAccountIDs: [], provenance: .qboAPI(readAt: Date())
        )
        let outcome = MissingPayeeRule.evaluate(dataSet(transactions: [bill]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — this rule is scoped to Purchase only")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = MissingPayeeRule.evaluate(
            dataSet(transactions: [], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }

    @Test("Two identical missing-payee findings across syncs produce the same finding id — deterministic re-detection")
    func deterministicFindingID() {
        let txn = purchase(id: "1", vendorName: nil)
        let outcomeA = MissingPayeeRule.evaluate(dataSet(transactions: [txn]), context: context())
        let outcomeB = MissingPayeeRule.evaluate(dataSet(transactions: [txn]), context: context())
        guard case .findings(let a) = outcomeA, case .findings(let b) = outcomeB else {
            Issue.record("expected findings both times")
            return
        }
        #expect(a[0].id == b[0].id)
    }
}
