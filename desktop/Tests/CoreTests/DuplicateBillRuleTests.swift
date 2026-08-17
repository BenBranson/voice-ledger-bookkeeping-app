import Testing
@testable import Core
import Foundation

@Suite("VL-DUP-BILL-001 — DuplicateBillRule")
struct DuplicateBillRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func bill(id: String, vendor: String = "Permian Supply", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .bill,
            vendorName: vendor,
            txnDate: date,
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "ap-1",
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

    @Test("Two bills — same vendor, date, amount — produce a .high-confidence finding")
    func exactMatchProducesFinding() {
        let a = bill(id: "1")
        let b = bill(id: "2")
        let outcome = DuplicateBillRule.evaluate(dataSet([a, b]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("Bills that differ by even one day do NOT match — this rule has no near-date tier, unlike VL-DUP-EXP-001")
    func differentDateDoesNotMatch() {
        let a = bill(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14))
        let b = bill(id: "2", date: AccountingDate(year: 2026, month: 7, day: 15))
        let outcome = DuplicateBillRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — no near-date tier in this rule")
            return
        }
    }

    @Test("A Purchase with the same vendor/date/amount as a Bill does not trigger this rule — entity-scoped")
    func purchaseEntityDoesNotMatch() {
        let theBill = bill(id: "1")
        let aPurchase = LedgerTransaction(
            id: "2", entityKind: .purchase, vendorName: "Permian Supply",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "checking-1", docNumber: nil, isVoided: false, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
        let outcome = DuplicateBillRule.evaluate(dataSet([theBill, aPurchase]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — a Purchase must not pair with a Bill in this rule")
            return
        }
    }

    @Test("A voided bill is excluded")
    func voidedBillExcluded() {
        let a = bill(id: "1")
        let b = bill(id: "2", isVoided: true)
        let outcome = DuplicateBillRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let a = bill(id: "1", amountMinorUnits: 500)
        let b = bill(id: "2", amountMinorUnits: 500)
        let outcome = DuplicateBillRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = DuplicateBillRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
