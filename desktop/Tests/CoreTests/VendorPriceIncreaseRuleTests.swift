import Testing
@testable import Core
import Foundation

@Suite("VL-VEND-PRICE-001 — VendorPriceIncreaseRule")
struct VendorPriceIncreaseRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String?,
        amountMinorUnits: Int64,
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
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(current: [LedgerTransaction], prior: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: current,
            priorPeriodTransactions: prior,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A vendor charging 20% more at the same transaction count produces a finding")
    func priceIncreaseProducesFinding() {
        let current = [purchase(id: "1", vendor: "Acme SaaS", amountMinorUnits: 120_000)]
        let prior = [purchase(id: "0", vendor: "Acme SaaS", amountMinorUnits: 100_000)]
        let outcome = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 20_000, currency: .usd))
        #expect(findings[0].confidence == .low)   // one charge vs one charge: weak evidence (v1.1)
    }

    @Test("v1.1: several consistent charges that all rose is a medium-confidence finding")
    func consistentRecurringChargesRise() {
        let prior = [purchase(id: "p1", vendor: "Acme SaaS", amountMinorUnits: 50_000), purchase(id: "p2", vendor: "Acme SaaS", amountMinorUnits: 52_000)]
        let current = [purchase(id: "c1", vendor: "Acme SaaS", amountMinorUnits: 66_000), purchase(id: "c2", vendor: "Acme SaaS", amountMinorUnits: 68_000)]
        guard case .findings(let findings) = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context()), findings.count == 1 else {
            Issue.record("expected one finding"); return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("v1.1: a vendor whose charges naturally vary (hardware store) is not a price increase")
    func variableVendorSkipped() {
        let prior = [purchase(id: "p1", vendor: "Hardware", amountMinorUnits: 8_000), purchase(id: "p2", vendor: "Hardware", amountMinorUnits: 24_000)]
        let current = [purchase(id: "c1", vendor: "Hardware", amountMinorUnits: 20_000), purchase(id: "c2", vendor: "Hardware", amountMinorUnits: 40_000)]
        if case .findings = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context()) { Issue.record("variable spending must not flag") }
    }

    @Test("v1.1: a big percentage on a small dollar change (under $50) does not flag")
    func smallDollarsSkipped() {
        let current = [purchase(id: "1", vendor: "Coffee", amountMinorUnits: 4_000)]
        let prior = [purchase(id: "0", vendor: "Coffee", amountMinorUnits: 2_500)]   // +60%, +$15
        if case .findings = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context()) { Issue.record("under the dollar floor") }
    }

    @Test("A vendor charging the same amount produces .pass")
    func sameAmountProducesPass() {
        let current = [purchase(id: "1", vendor: "Acme SaaS", amountMinorUnits: 10_000)]
        let prior = [purchase(id: "0", vendor: "Acme SaaS", amountMinorUnits: 10_000)]
        let outcome = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — no increase")
            return
        }
    }

    @Test("A below-threshold increase (5%) produces .pass")
    func smallIncreaseProducesPass() {
        let current = [purchase(id: "1", vendor: "Acme SaaS", amountMinorUnits: 10_500)]
        let prior = [purchase(id: "0", vendor: "Acme SaaS", amountMinorUnits: 10_000)]
        let outcome = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — 5% is below the 15% threshold")
            return
        }
    }

    @Test("A vendor billed twice as often at the same per-transaction price does not false-positive")
    func volumeIncreaseDoesNotFalsePositive() {
        let current = [
            purchase(id: "1", vendor: "Acme Supply", amountMinorUnits: 10_000),
            purchase(id: "2", vendor: "Acme Supply", amountMinorUnits: 10_000)
        ]
        let prior = [purchase(id: "0", vendor: "Acme Supply", amountMinorUnits: 10_000)]
        let outcome = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — transaction count differs, so this is a volume change, not a price change")
            return
        }
    }

    @Test("A vendor with no prior-period activity is not evaluated")
    func noPriorActivityExcluded() {
        let current = [purchase(id: "1", vendor: "New Vendor", amountMinorUnits: 50_000)]
        let prior: [LedgerTransaction] = []
        let outcome = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no prior period data fetched at all")
            return
        }
    }

    @Test("A Bill is excluded from both periods' comparison")
    func billExcluded() {
        let current = [purchase(id: "1", vendor: "Acme SaaS", amountMinorUnits: 20_000, entityKind: .bill)]
        let prior = [purchase(id: "0", vendor: "Acme SaaS", amountMinorUnits: 10_000, entityKind: .bill)]
        let outcome = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — bills are excluded, so this vendor has no comparable current-period purchases")
            return
        }
    }

    @Test("A voided current-period transaction is excluded")
    func voidedTransactionExcluded() {
        let current = [purchase(id: "1", vendor: "Acme SaaS", amountMinorUnits: 20_000, isVoided: true)]
        let prior = [purchase(id: "0", vendor: "Acme SaaS", amountMinorUnits: 10_000)]
        let outcome = VendorPriceIncreaseRule.evaluate(dataSet(current: current, prior: prior), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — the only current-period transaction is voided")
            return
        }
    }
}
