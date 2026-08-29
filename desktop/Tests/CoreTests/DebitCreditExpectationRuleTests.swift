import Testing
@testable import Core
import Foundation

@Suite("VL-BS-DRCR-001 — DebitCreditExpectationRule")
struct DebitCreditExpectationRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func account(id: String, name: String, type: LedgerAccountType, subType: String? = nil) -> LedgerAccount {
        LedgerAccount(id: id, name: name, accountType: type, accountSubType: subType, fullyQualifiedName: name)
    }

    func tbLine(_ label: String, debitCents: Int64?, creditCents: Int64?, isSummary: Bool = false) -> TrialBalanceLine {
        TrialBalanceLine(
            label: label,
            debit: debitCents.map { Money(minorUnits: $0, currency: .usd) },
            credit: creditCents.map { Money(minorUnits: $0, currency: .usd) },
            isSummary: isSummary
        )
    }

    func dataSet(accounts: [LedgerAccount], trialBalanceLines: [TrialBalanceLine], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: [], accounts: accounts,
            trialBalanceLines: trialBalanceLines,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("An Income account with a debit balance produces a finding — the real Pest Control Services case")
    func incomeAccountWithDebitBalanceProducesFinding() {
        let accounts = [account(id: "1", name: "Pest Control Services", type: .income, subType: "OtherPrimaryIncome")]
        let lines = [tbLine("Pest Control Services", debitCents: 3_000, creditCents: nil)]
        let outcome = DebitCreditExpectationRule.evaluate(dataSet(accounts: accounts, trialBalanceLines: lines), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .medium)
    }

    @Test("An Expense account with a credit balance produces a finding")
    func expenseAccountWithCreditBalanceProducesFinding() {
        let accounts = [account(id: "1", name: "Advertising", type: .expense, subType: "AdvertisingPromotional")]
        let lines = [tbLine("Advertising", debitCents: nil, creditCents: 5_000)]
        let outcome = DebitCreditExpectationRule.evaluate(dataSet(accounts: accounts, trialBalanceLines: lines), context: context())
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 5_000, currency: .usd))
    }

    @Test("An Income account with a normal credit balance produces .pass")
    func normalIncomeBalanceProducesPass() {
        let accounts = [account(id: "1", name: "Design income", type: .income, subType: "OtherPrimaryIncome")]
        let lines = [tbLine("Design income", debitCents: nil, creditCents: 100_000)]
        let outcome = DebitCreditExpectationRule.evaluate(dataSet(accounts: accounts, trialBalanceLines: lines), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — this is the normal, expected side")
            return
        }
    }

    @Test("The real contra-income account (DiscountsRefundsGiven) with a debit balance does not false-positive")
    func discountsGivenContraAccountExcluded() {
        let accounts = [account(id: "1", name: "Discounts given", type: .income, subType: "DiscountsRefundsGiven")]
        let lines = [tbLine("Discounts given", debitCents: 8_950, creditCents: nil)]
        let outcome = DebitCreditExpectationRule.evaluate(dataSet(accounts: accounts, trialBalanceLines: lines), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — DiscountsRefundsGiven is a real contra-income subtype, live-verified normal to carry a debit balance")
            return
        }
    }

    @Test("Asset and Liability accounts are excluded entirely — that's VL-BS-NEGBAL-001's territory")
    func assetAndLiabilityExcluded() {
        let accounts = [account(id: "1", name: "Checking", type: .bank), account(id: "2", name: "Loan Payable", type: .otherCurrentLiability)]
        let lines = [
            tbLine("Checking", debitCents: nil, creditCents: 300_000),
            tbLine("Loan Payable", debitCents: 400_000, creditCents: nil)
        ]
        let outcome = DebitCreditExpectationRule.evaluate(dataSet(accounts: accounts, trialBalanceLines: lines), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — Asset/Liability accounts are out of scope for this rule regardless of which side they're on")
            return
        }
    }

    @Test("Summary rows are excluded")
    func summaryRowsExcluded() {
        let accounts = [account(id: "1", name: "TOTAL", type: .income)]
        let lines = [tbLine("TOTAL", debitCents: 100, creditCents: 100, isSummary: true)]
        let outcome = DebitCreditExpectationRule.evaluate(dataSet(accounts: accounts, trialBalanceLines: lines), context: context())
        guard case .pass = outcome else {
            Issue.record("expected .pass — summary rows are excluded")
            return
        }
    }

    @Test("No Trial Balance loaded produces .cannotEvaluate")
    func noTrialBalanceCannotEvaluate() {
        let outcome = DebitCreditExpectationRule.evaluate(dataSet(accounts: [], trialBalanceLines: []), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no Trial Balance fetched")
            return
        }
    }
}
