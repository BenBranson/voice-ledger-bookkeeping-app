import Testing
@testable import Core
import Foundation

@Suite("VL-RECON-DIFF-001 — BankReconciliationDriftRule")
struct BankReconciliationDriftRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func account(id: String, name: String, currentBalanceCents: Int64) -> LedgerAccount {
        LedgerAccount(id: id, name: name, accountType: .bank, accountSubType: "Checking", currentBalance: Money(minorUnits: currentBalanceCents, currency: .usd))
    }

    func snapshot(accountID: String, statedCents: Int64, asOf: AccountingDate? = nil) -> BankStatementReconciliationSnapshot {
        BankStatementReconciliationSnapshot(accountID: accountID, statedEndingBalance: Money(minorUnits: statedCents, currency: .usd), statedAsOfDate: asOf)
    }

    func dataSet(accounts: [LedgerAccount], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: [], accounts: accounts,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    func context(snapshots: [BankStatementReconciliationSnapshot]) -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), bankStatementSnapshots: snapshots)
    }

    @Test("A large gap between QBO balance and the statement produces a finding")
    func largeGapProducesFinding() {
        let accounts = [account(id: "1", name: "Checking", currentBalanceCents: 500_000)]
        let snapshots = [snapshot(accountID: "1", statedCents: 300_000)]
        let outcome = BankReconciliationDriftRule.evaluate(dataSet(accounts: accounts), context: context(snapshots: snapshots))
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 200_000, currency: .usd))
    }

    @Test("A matching balance produces .pass")
    func matchingBalanceProducesPass() {
        let accounts = [account(id: "1", name: "Checking", currentBalanceCents: 500_000)]
        let snapshots = [snapshot(accountID: "1", statedCents: 500_000)]
        let outcome = BankReconciliationDriftRule.evaluate(dataSet(accounts: accounts), context: context(snapshots: snapshots))
        guard case .pass = outcome else {
            Issue.record("expected .pass — balances match exactly")
            return
        }
    }

    @Test("A small gap below the relative threshold produces .pass even above the flat materiality floor")
    func smallRelativeGapProducesPass() {
        // $50 gap on a $50,000 balance = 0.1%, well under the 2% relative threshold,
        // even though $50 clears the flat $25 materiality floor.
        let accounts = [account(id: "1", name: "Checking", currentBalanceCents: 5_005_000)]
        let snapshots = [snapshot(accountID: "1", statedCents: 5_000_000)]
        let outcome = BankReconciliationDriftRule.evaluate(dataSet(accounts: accounts), context: context(snapshots: snapshots))
        guard case .pass = outcome else {
            Issue.record("expected .pass — 0.1% gap is plausibly ordinary between-dates activity")
            return
        }
    }

    @Test("No bank statement snapshot at all produces .cannotEvaluate")
    func noSnapshotCannotEvaluate() {
        let accounts = [account(id: "1", name: "Checking", currentBalanceCents: 500_000)]
        let outcome = BankReconciliationDriftRule.evaluate(dataSet(accounts: accounts), context: context(snapshots: []))
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no statement imported")
            return
        }
    }

    @Test("A snapshot for an account not in this sync's accounts is skipped, not crashed on")
    func unknownAccountSkipped() {
        let accounts = [account(id: "1", name: "Checking", currentBalanceCents: 500_000)]
        let snapshots = [snapshot(accountID: "unknown-account", statedCents: 100_000)]
        let outcome = BankReconciliationDriftRule.evaluate(dataSet(accounts: accounts), context: context(snapshots: snapshots))
        guard case .pass = outcome else {
            Issue.record("expected .pass — the snapshot's account doesn't match any synced account")
            return
        }
    }

    @Test("A dismissed finding does not reappear")
    func dismissedFindingExcluded() {
        let accounts = [account(id: "1", name: "Checking", currentBalanceCents: 500_000)]
        let snapshots = [snapshot(accountID: "1", statedCents: 300_000)]
        let ctx = RuleContext(
            period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false),
            dismissedFindingIDs: [FindingIDGenerator.makeID(ruleID: BankReconciliationDriftRule.identity.id, ruleVersion: BankReconciliationDriftRule.identity.version, realmID: realm, period: period, sortedAffectedIDs: ["1"])],
            bankStatementSnapshots: snapshots
        )
        let outcome = BankReconciliationDriftRule.evaluate(dataSet(accounts: accounts), context: ctx)
        guard case .pass = outcome else {
            Issue.record("expected .pass — the one possible finding was dismissed")
            return
        }
    }
}
