import Testing
@testable import Core
import Foundation

@Suite("VL-RELATIONSHIP-005 — LoanPaymentLumpSumRule")
struct LoanPaymentLumpSumRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String? = nil,
        memo: String? = nil,
        lineAccountIDs: [String] = ["acct-1"],
        amountMinorUnits: Int64 = 100_000,
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
            memo: memo,
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

    @Test("A single-line loan payment produces a finding")
    func singleLineLoanPaymentProducesFinding() {
        let txn = purchase(id: "1", vendor: "First National Bank", memo: "Loan payment for equipment note")
        let outcome = LoanPaymentLumpSumRule.evaluate(dataSet([txn]), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A vendor name match alone (no memo) still produces a finding")
    func vendorNameMatchAlone() {
        let txn = purchase(id: "1", vendor: "Mortgage Payment - Wells Fargo")
        let outcome = LoanPaymentLumpSumRule.evaluate(dataSet([txn]), context: context())
        guard case .findings = outcome else {
            Issue.record("expected a finding from a vendor-name match")
            return
        }
    }

    @Test("An already-split loan payment (multiple lines) does not fire")
    func alreadySplitDoesNotFire() {
        let txn = purchase(id: "1", vendor: "First National Bank", memo: "Loan payment", lineAccountIDs: ["principal-acct", "interest-acct"])
        let outcome = LoanPaymentLumpSumRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — already split across two lines")
            return
        }
    }

    @Test("An ordinary vendor with no loan-related text produces .pass")
    func ordinaryVendorProducesPass() {
        let txn = purchase(id: "1", vendor: "VL Spike Permian Supply")
        let outcome = LoanPaymentLumpSumRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A bare word 'loan' alone does not false-positive")
    func bareWordLoanDoesNotFalsePositive() {
        let txn = purchase(id: "1", vendor: "Loan Star Consulting")
        let outcome = LoanPaymentLumpSumRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — 'loan' alone is not a keyword match")
            return
        }
    }

    @Test("A voided transaction with matching text is excluded")
    func voidedTransactionExcluded() {
        let txn = purchase(id: "1", vendor: "Loan Payment", isVoided: true)
        let outcome = LoanPaymentLumpSumRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — voided transaction excluded")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = LoanPaymentLumpSumRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
