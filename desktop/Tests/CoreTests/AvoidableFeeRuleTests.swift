import Testing
@testable import Core
import Foundation

@Suite("VL-FEE-AVOIDABLE-001 — AvoidableFeeRule")
struct AvoidableFeeRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func purchase(
        id: String,
        vendor: String?,
        memo: String? = nil,
        amountMinorUnits: Int64 = 5_000,
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
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A vendor name containing 'Overdraft' produces a finding")
    func overdraftInVendorNameProducesFinding() {
        let txn = purchase(id: "1", vendor: "Chase Bank Overdraft Fee")
        let outcome = AvoidableFeeRule.evaluate(dataSet([txn]), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A memo containing 'late fee' (vendor name unrelated) also produces a finding — both fields are checked")
    func lateFeeInMemoProducesFinding() {
        let txn = purchase(id: "1", vendor: "Acme Utility Co", memo: "Late fee assessed for prior month")
        let outcome = AvoidableFeeRule.evaluate(dataSet([txn]), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
    }

    @Test("A case-insensitive match still fires — 'NSF' vs 'nsf'")
    func caseInsensitiveMatch() {
        let txn = purchase(id: "1", vendor: "Bank NSF Charge")
        let outcome = AvoidableFeeRule.evaluate(dataSet([txn]), context: context())
        guard case .findings = outcome else {
            Issue.record("expected a finding regardless of case")
            return
        }
    }

    @Test("A legitimate vendor named 'ABC Filing Fee Services' does not false-positive on the bare word 'fee'")
    func bareWordFeeDoesNotFalsePositive() {
        let txn = purchase(id: "1", vendor: "ABC Filing Fee Services")
        let outcome = AvoidableFeeRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — 'fee' alone is not a fee-keyword match")
            return
        }
    }

    @Test("An ordinary vendor with no fee-related text produces .pass")
    func ordinaryVendorProducesPass() {
        let txn = purchase(id: "1", vendor: "VL Spike Permian Supply")
        let outcome = AvoidableFeeRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A voided transaction with fee-shaped text is excluded")
    func voidedTransactionExcluded() {
        let txn = purchase(id: "1", vendor: "Overdraft Fee", isVoided: true)
        let outcome = AvoidableFeeRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — voided transaction excluded")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let txn = purchase(id: "1", vendor: "Overdraft Fee", amountMinorUnits: 500) // $5, below $25 floor
        let outcome = AvoidableFeeRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — below materiality floor")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = AvoidableFeeRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
