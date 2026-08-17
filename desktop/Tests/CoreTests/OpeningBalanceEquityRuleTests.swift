import Testing
@testable import Core
import Foundation

@Suite("VL-OBE-BALANCE-001 — OpeningBalanceEquityRule")
struct OpeningBalanceEquityRuleTests {
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

    @Test("A nonzero Opening Balance Equity account produces a .high-confidence finding")
    func nonzeroBalanceProducesFinding() {
        let obe = LedgerAccount(
            id: "34", name: "Opening Balance Equity", accountType: .equity,
            accountSubType: "OpeningBalanceEquity", currentBalance: Money(minorUnits: 833_750, currency: .usd)
        )
        let outcome = OpeningBalanceEquityRule.evaluate(dataSet([obe]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
        #expect(findings[0].dollarExposure == Money(minorUnits: 833_750, currency: .usd))
    }

    @Test("A zero-balance Opening Balance Equity account produces no finding")
    func zeroBalanceProducesNoFinding() {
        let obe = LedgerAccount(id: "34", name: "Opening Balance Equity", accountType: .equity, accountSubType: "OpeningBalanceEquity", currentBalance: .zero)
        let outcome = OpeningBalanceEquityRule.evaluate(dataSet([obe]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }

    @Test("A negative balance is also flagged, using its absolute value as the dollar exposure")
    func negativeBalanceIsFlaggedWithAbsoluteExposure() {
        let obe = LedgerAccount(id: "34", name: "Opening Balance Equity", accountType: .equity, accountSubType: "OpeningBalanceEquity", currentBalance: Money(minorUnits: -5_000, currency: .usd))
        let outcome = OpeningBalanceEquityRule.evaluate(dataSet([obe]), context: context())

        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 5_000, currency: .usd))
    }

    @Test("A regular Equity account with a nonzero balance (not Opening Balance Equity) produces no finding")
    func regularEquityAccountNotFlagged() {
        let retainedEarnings = LedgerAccount(id: "40", name: "Retained Earnings", accountType: .equity, accountSubType: "RetainedEarnings", currentBalance: Money(minorUnits: 1_000_000, currency: .usd))
        let outcome = OpeningBalanceEquityRule.evaluate(dataSet([retainedEarnings]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — this rule targets Opening Balance Equity specifically, not equity accounts generally")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let obe = LedgerAccount(id: "34", name: "Opening Balance Equity", accountType: .equity, accountSubType: "OpeningBalanceEquity", currentBalance: Money(minorUnits: 500, currency: .usd))
        let outcome = OpeningBalanceEquityRule.evaluate(dataSet([obe]), context: context())

        guard case .pass = outcome else {
            Issue.record("expected .pass — below the $25 floor")
            return
        }
    }

    @Test("The rule never claims .pass on incomplete coverage")
    func neverClaimsPassOnPartialCoverage() {
        let outcome = OpeningBalanceEquityRule.evaluate(
            dataSet([], coverage: .partial(reason: "sync incomplete")),
            context: context()
        )
        if case .pass = outcome {
            Issue.record("rule must not report .pass on partial coverage")
        }
    }
}
