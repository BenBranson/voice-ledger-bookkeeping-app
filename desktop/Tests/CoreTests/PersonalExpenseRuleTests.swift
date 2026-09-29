import Testing
@testable import Core
import Foundation

@Suite("VL-PERSONAL-001 — PersonalExpenseRule")
struct PersonalExpenseRuleTests {
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

    @Test("An owner draw already coded entirely to an equity account is correct — no finding")
    func drawCodedToEquityIsNotFlagged() {
        let draw = LedgerTransaction(id: "9", entityKind: .purchase, vendorName: "Owner Draw", txnDate: AccountingDate(year: 2026, month: 7, day: 25),
                                     totalAmount: Money(minorUnits: 150_000, currency: .usd), paymentAccountID: "checking-1", docNumber: nil,
                                     isVoided: false, memo: "Owner's draw", lineAccountIDs: ["eq-1"], provenance: .qboAPI(readAt: Date()))
        let data = NormalizedDataSet(realmID: realm, period: period, transactions: [draw],
                                     accounts: [LedgerAccount(id: "eq-1", name: "Owner's Draw", accountType: .equity)],
                                     coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        if case .findings = PersonalExpenseRule.evaluate(data, context: context()) { Issue.record("a correctly coded draw must not be flagged") }
    }

    @Test("A memo containing 'owner draw' produces a finding")
    func ownerDrawInMemoProducesFinding() {
        let txn = purchase(id: "1", vendor: "ATM Withdrawal", memo: "Owner draw for personal use")
        let outcome = PersonalExpenseRule.evaluate(dataSet([txn]), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("A vendor name containing 'shareholder distribution' produces a finding")
    func shareholderDistributionInVendorNameProducesFinding() {
        let txn = purchase(id: "1", vendor: "Shareholder Distribution")
        let outcome = PersonalExpenseRule.evaluate(dataSet([txn]), context: context())
        guard case .findings = outcome else {
            Issue.record("expected a finding")
            return
        }
    }

    @Test("A case-insensitive match still fires — 'OWNER DRAW' vs 'owner draw'")
    func caseInsensitiveMatch() {
        let txn = purchase(id: "1", vendor: "OWNER DRAW - CHECK")
        let outcome = PersonalExpenseRule.evaluate(dataSet([txn]), context: context())
        guard case .findings = outcome else {
            Issue.record("expected a finding regardless of case")
            return
        }
    }

    @Test("A legitimate vendor named 'Personal Touch Cleaning' does not false-positive on the bare word 'personal'")
    func bareWordPersonalDoesNotFalsePositive() {
        let txn = purchase(id: "1", vendor: "Personal Touch Cleaning")
        let outcome = PersonalExpenseRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — 'personal' alone is not a keyword match")
            return
        }
    }

    @Test("An ordinary vendor with no personal/draw-related text produces .pass")
    func ordinaryVendorProducesPass() {
        let txn = purchase(id: "1", vendor: "VL Spike Permian Supply")
        let outcome = PersonalExpenseRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A voided transaction with matching text is excluded")
    func voidedTransactionExcluded() {
        let txn = purchase(id: "1", vendor: "Owner Draw", isVoided: true)
        let outcome = PersonalExpenseRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — voided transaction excluded")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let txn = purchase(id: "1", vendor: "Owner Draw", amountMinorUnits: 500) // $5, below $25 floor
        let outcome = PersonalExpenseRule.evaluate(dataSet([txn]), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — below materiality floor")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = PersonalExpenseRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
