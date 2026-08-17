import Testing
@testable import Core
import Foundation

@Suite("VL-DUP-PAY-001 — DuplicatePaymentRule")
struct DuplicatePaymentRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func payment(id: String, customer: String = "Cool Cars", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .payment,
            vendorName: customer,
            txnDate: date,
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: nil,
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

    @Test("Two payments — same customer, date, amount — produce a .medium-confidence finding")
    func exactMatchProducesFinding() {
        let a = payment(id: "1")
        let b = payment(id: "2")
        let outcome = DuplicatePaymentRule.evaluate(dataSet([a, b]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("Payments that differ by even one day do NOT match — no near-date tier")
    func differentDateDoesNotMatch() {
        let a = payment(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14))
        let b = payment(id: "2", date: AccountingDate(year: 2026, month: 7, day: 15))
        let outcome = DuplicatePaymentRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — no near-date tier in this rule")
            return
        }
    }

    @Test("An Invoice with the same customer/date/amount as a Payment does not trigger this rule — entity-scoped")
    func invoiceEntityDoesNotMatch() {
        let thePayment = payment(id: "1")
        let anInvoice = LedgerTransaction(
            id: "2", entityKind: .invoice, vendorName: "Cool Cars",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: nil, docNumber: nil, isVoided: false, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
        let outcome = DuplicatePaymentRule.evaluate(dataSet([thePayment, anInvoice]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — an Invoice must not pair with a Payment in this rule")
            return
        }
    }

    @Test("A voided payment is excluded")
    func voidedPaymentExcluded() {
        let a = payment(id: "1")
        let b = payment(id: "2", isVoided: true)
        let outcome = DuplicatePaymentRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let a = payment(id: "1", amountMinorUnits: 500)
        let b = payment(id: "2", amountMinorUnits: 500)
        let outcome = DuplicatePaymentRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = DuplicatePaymentRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
