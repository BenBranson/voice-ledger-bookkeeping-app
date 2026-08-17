import Testing
@testable import Core
import Foundation

@Suite("VL-BS-NEGBAL-001 — NegativeBalanceRule")
struct NegativeBalanceRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func dataSet(_ accounts: [LedgerAccount], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: [], accounts: accounts,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("A negative bank (asset) balance produces a finding")
    func negativeAssetBalanceProducesFinding() {
        let checking = LedgerAccount(id: "35", name: "Checking", accountType: .bank, currentBalance: Money(minorUnits: -100_000, currency: .usd))
        let outcome = NegativeBalanceRule.evaluate(dataSet([checking]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
        #expect(findings[0].title.contains("asset"))
    }

    @Test("A negative accounts-payable (liability) balance produces a finding")
    func negativeLiabilityBalanceProducesFinding() {
        let ap = LedgerAccount(id: "33", name: "Accounts Payable (A/P)", accountType: .accountsPayable, currentBalance: Money(minorUnits: -171_267, currency: .usd))
        let outcome = NegativeBalanceRule.evaluate(dataSet([ap]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].title.contains("liability"))
    }

    @Test("A negative equity balance produces no finding — this rule is scoped to asset/liability only")
    func negativeEquityBalanceExcluded() {
        let draws = LedgerAccount(id: "50", name: "Owner's Draw", accountType: .equity, currentBalance: Money(minorUnits: -50_000, currency: .usd))
        let outcome = NegativeBalanceRule.evaluate(dataSet([draws]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — negative equity is not this rule's concern")
            return
        }
    }

    @Test("A positive balance produces no finding")
    func positiveBalanceProducesNoFinding() {
        let checking = LedgerAccount(id: "35", name: "Checking", accountType: .bank, currentBalance: Money(minorUnits: 100_000, currency: .usd))
        let outcome = NegativeBalanceRule.evaluate(dataSet([checking]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A small negative balance below the materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let checking = LedgerAccount(id: "35", name: "Checking", accountType: .bank, currentBalance: Money(minorUnits: -500, currency: .usd))
        let outcome = NegativeBalanceRule.evaluate(dataSet([checking]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — below the $25 floor")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = NegativeBalanceRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
