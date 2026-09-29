import Testing
@testable import Core
import Foundation

@Suite("VL-BS-SUSPENSE-001 — SuspenseClearingBalanceRule")
struct SuspenseClearingBalanceRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func evaluate(_ accounts: [LedgerAccount]) -> RuleOutcome {
        SuspenseClearingBalanceRule.evaluate(
            NormalizedDataSet(realmID: realm, period: period, transactions: [], accounts: accounts, coverage: .complete, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)),
            context: RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
        )
    }

    func account(_ name: String, _ type: LedgerAccountType, cents: Int64) -> LedgerAccount {
        LedgerAccount(id: name, name: name, accountType: type, currentBalance: Money(minorUnits: cents, currency: .usd))
    }

    @Test("The sandbox-seeded Suspense and Payroll Clearing balances are both flagged")
    func seededAccountsFlagged() {
        guard case .findings(let f) = evaluate([
            account("VL Spike Suspense", .otherCurrentAsset, cents: 87_500),
            account("VL Spike Payroll Clearing", .otherCurrentAsset, cents: 142_000)
        ]) else { Issue.record("expected findings"); return }
        #expect(f.count == 2)
    }

    @Test("A zeroed clearing account and an expense account named 'clearing' are not flagged")
    func zeroAndNonBalanceSheetIgnored() {
        guard case .pass = evaluate([
            account("Payroll Clearing", .otherCurrentLiability, cents: 0),
            account("Clearing House Fees", .expense, cents: 50_000)
        ]) else { Issue.record("expected pass"); return }
    }

    @Test("No accounts loaded is cannotEvaluate, never green")
    func noAccountsCannotEvaluate() {
        guard case .cannotEvaluate = evaluate([]) else { Issue.record("expected cannotEvaluate"); return }
    }
}
