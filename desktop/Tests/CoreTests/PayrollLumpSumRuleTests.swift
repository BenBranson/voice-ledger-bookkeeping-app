import Testing
@testable import Core
import Foundation

@Suite("VL-PAYROLL-LUMP-001 — PayrollLumpSumRule")
struct PayrollLumpSumRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String,
        amountMinorUnits: Int64 = 991_200,
        lineAccountIDs: [String],
        isVoided: Bool = false
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id,
            entityKind: .purchase,
            vendorName: vendor,
            txnDate: AccountingDate(year: 2026, month: 7, day: 15),
            totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            lineAccountIDs: lineAccountIDs,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A known payroll processor paid on a single expense line produces a finding")
    func knownProcessorSingleLineProducesFinding() {
        let txn = purchase(id: "1", vendor: "ADP", lineAccountIDs: ["wages-1"])
        let outcome = PayrollLumpSumRule.evaluate(dataSet([txn]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
        #expect(findings[0].proposedActions.first?.resolution == .manualQBO)
    }

    @Test("A known processor already split across multiple lines produces no finding — someone already did the split")
    func alreadySplitProducesNoFinding() {
        let txn = purchase(id: "1", vendor: "Gusto", lineAccountIDs: ["wages-1", "employer-tax-1", "withholding-1"])
        let outcome = PayrollLumpSumRule.evaluate(dataSet([txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — already split, not the error this rule targets")
            return
        }
    }

    @Test("A non-payroll vendor on a single line produces no finding")
    func nonPayrollVendorProducesNoFinding() {
        let txn = purchase(id: "1", vendor: "Permian Supply", lineAccountIDs: ["exp-1"])
        let outcome = PayrollLumpSumRule.evaluate(dataSet([txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("Matching is case-insensitive and substring-based (e.g. 'QuickBooks Payroll' matches)")
    func caseInsensitiveSubstringMatch() {
        let txn = purchase(id: "1", vendor: "Intuit QuickBooks Payroll Services", lineAccountIDs: ["wages-1"])
        let outcome = PayrollLumpSumRule.evaluate(dataSet([txn]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].title.contains("Intuit QuickBooks Payroll Services"))
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let txn = purchase(id: "1", vendor: "ADP", amountMinorUnits: 500, lineAccountIDs: ["wages-1"])
        let outcome = PayrollLumpSumRule.evaluate(dataSet([txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — below materiality floor")
            return
        }
    }

    @Test("A voided transaction is excluded")
    func voidedTransactionExcluded() {
        let txn = purchase(id: "1", vendor: "ADP", lineAccountIDs: ["wages-1"], isVoided: true)
        let outcome = PayrollLumpSumRule.evaluate(dataSet([txn]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — voided")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = PayrollLumpSumRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
