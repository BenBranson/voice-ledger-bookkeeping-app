import Testing
@testable import Core
import Foundation

@Suite("VL-DUP-INV-001 — DuplicateInvoiceRule")
struct DuplicateInvoiceRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func invoice(id: String, customer: String = "Amy's Bird Sanctuary", date: AccountingDate = AccountingDate(year: 2026, month: 7, day: 14), amountMinorUnits: Int64 = 48_620, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .invoice,
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

    @Test("Two invoices — same customer, date, amount — produce a .high-confidence finding")
    func exactMatchProducesFinding() {
        let a = invoice(id: "1")
        let b = invoice(id: "2")
        let outcome = DuplicateInvoiceRule.evaluate(dataSet([a, b]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("Invoices that differ by even one day do NOT match — this rule has no near-date tier")
    func differentDateDoesNotMatch() {
        let a = invoice(id: "1", date: AccountingDate(year: 2026, month: 7, day: 14))
        let b = invoice(id: "2", date: AccountingDate(year: 2026, month: 7, day: 15))
        let outcome = DuplicateInvoiceRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — no near-date tier in this rule")
            return
        }
    }

    @Test("A Bill with the same customer/date/amount as an Invoice does not trigger this rule — entity-scoped")
    func billEntityDoesNotMatch() {
        let theInvoice = invoice(id: "1")
        let aBill = LedgerTransaction(
            id: "2", entityKind: .bill, vendorName: "Amy's Bird Sanctuary",
            txnDate: AccountingDate(year: 2026, month: 7, day: 14),
            totalAmount: Money(minorUnits: 48_620, currency: .usd),
            paymentAccountID: "ap-1", docNumber: nil, isVoided: false, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
        let outcome = DuplicateInvoiceRule.evaluate(dataSet([theInvoice, aBill]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — a Bill must not pair with an Invoice in this rule")
            return
        }
    }

    @Test("A voided invoice is excluded")
    func voidedInvoiceExcluded() {
        let a = invoice(id: "1")
        let b = invoice(id: "2", isVoided: true)
        let outcome = DuplicateInvoiceRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let a = invoice(id: "1", amountMinorUnits: 500)
        let b = invoice(id: "2", amountMinorUnits: 500)
        let outcome = DuplicateInvoiceRule.evaluate(dataSet([a, b]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = DuplicateInvoiceRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
