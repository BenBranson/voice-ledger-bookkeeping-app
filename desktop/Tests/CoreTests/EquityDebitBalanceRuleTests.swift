import Testing
@testable import Core
import Foundation

@Suite("VL-BS-EQUITY-DR-001 — EquityDebitBalanceRule")
struct EquityDebitBalanceRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context() -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }

    func evaluate(_ accounts: [LedgerAccount], _ lines: [TrialBalanceLine]) -> RuleOutcome {
        EquityDebitBalanceRule.evaluate(
            NormalizedDataSet(realmID: realm, period: period, transactions: [], accounts: accounts, trialBalanceLines: lines,
                              coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)),
            context: context()
        )
    }

    func equity(_ name: String, _ subType: String) -> LedgerAccount {
        LedgerAccount(id: name, name: name, accountType: .equity, accountSubType: subType, fullyQualifiedName: name)
    }

    func debit(_ label: String, _ cents: Int64) -> TrialBalanceLine {
        TrialBalanceLine(label: label, debit: Money(minorUnits: cents, currency: .usd), credit: nil, isSummary: false)
    }

    @Test("Paid-in capital with a debit balance is flagged")
    func capitalDebitFlagged() {
        guard case .findings(let f) = evaluate([equity("Owner Investment", "PaidInCapitalOrSurplus")], [debit("Owner Investment", 250_000)]) else {
            Issue.record("expected a finding"); return
        }
        #expect(f.count == 1)
    }

    @Test("Draws, distributions, and retained earnings legitimately carry debits and are never flagged")
    func legitimateDebitsIgnored() {
        let accounts = [equity("Owner Draw", "OwnersEquity"), equity("Distributions", "PartnerDistributions"), equity("Retained Earnings", "RetainedEarnings")]
        let lines = [debit("Owner Draw", 900_000), debit("Distributions", 500_000), debit("Retained Earnings", 1_200_000)]
        guard case .pass = evaluate(accounts, lines) else { Issue.record("expected pass"); return }
    }

    @Test("No Trial Balance loaded is cannotEvaluate, never green")
    func noTrialBalanceCannotEvaluate() {
        guard case .cannotEvaluate = evaluate([equity("Owner Investment", "PaidInCapitalOrSurplus")], []) else {
            Issue.record("expected cannotEvaluate"); return
        }
    }
}
