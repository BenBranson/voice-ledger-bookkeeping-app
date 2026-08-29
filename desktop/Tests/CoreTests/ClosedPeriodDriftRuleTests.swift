import Testing
@testable import Core
import Foundation

@Suite("VL-CLOSED-PERIOD-DRIFT-001 — ClosedPeriodDriftRule")
struct ClosedPeriodDriftRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 7)

    func context(lock: PeriodLock? = nil, snapshot: PeriodLockSnapshot? = nil) -> RuleContext {
        RuleContext(
            period: period,
            materiality: .defaultPolicy,
            companyFacts: CompanyFacts(customTxnNumbersForPurchases: false),
            periodLock: lock,
            periodLockSnapshot: snapshot
        )
    }

    func trialBalanceLine(_ label: String, debitCents: Int64?, creditCents: Int64?, isSummary: Bool = false) -> TrialBalanceLine {
        TrialBalanceLine(
            label: label,
            debit: debitCents.map { Money(minorUnits: $0, currency: .usd) },
            credit: creditCents.map { Money(minorUnits: $0, currency: .usd) },
            isSummary: isSummary
        )
    }

    func dataSet(trialBalanceLines: [TrialBalanceLine], period: AccountingPeriod? = nil, coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period ?? self.period, transactions: [],
            trialBalanceLines: trialBalanceLines,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 7), lockedBy: "Ben")

    @Test("An unchanged Trial Balance since lock produces .pass")
    func unchangedProducesPass() {
        let lines = [trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil)]
        let snapshot = PeriodLockSnapshot.capture(lockedThrough: period, from: lines)
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: lines), context: context(lock: lock, snapshot: snapshot))
        guard case .pass = outcome else {
            Issue.record("expected .pass — nothing changed")
            return
        }
    }

    @Test("A materially changed line since lock produces a finding")
    func materialChangeProducesFinding() {
        let lockedLines = [trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil)]
        let snapshot = PeriodLockSnapshot.capture(lockedThrough: period, from: lockedLines)
        let currentLines = [trialBalanceLine("Checking", debitCents: 150_000, creditCents: nil)]
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: currentLines), context: context(lock: lock, snapshot: snapshot))
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].dollarExposure == Money(minorUnits: 50_000, currency: .usd))
    }

    @Test("A new nonzero account line appearing since lock produces a finding")
    func newAccountLineProducesFinding() {
        let lockedLines = [trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil)]
        let snapshot = PeriodLockSnapshot.capture(lockedThrough: period, from: lockedLines)
        let currentLines = [
            trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil),
            trialBalanceLine("Misc Expense", debitCents: 5_000, creditCents: nil)
        ]
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: currentLines), context: context(lock: lock, snapshot: snapshot))
        guard case .findings = outcome else {
            Issue.record("expected a finding — a new line appeared with a nonzero balance")
            return
        }
    }

    @Test("A sub-materiality-floor change produces .pass")
    func immaterialChangeProducesPass() {
        let lockedLines = [trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil)]
        let snapshot = PeriodLockSnapshot.capture(lockedThrough: period, from: lockedLines)
        let currentLines = [trialBalanceLine("Checking", debitCents: 100_010, creditCents: nil)] // $0.10 diff
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: currentLines), context: context(lock: lock, snapshot: snapshot))
        guard case .pass = outcome else {
            Issue.record("expected .pass — $0.10 is below the materiality floor")
            return
        }
    }

    @Test("Summary rows are excluded from both the snapshot and the comparison")
    func summaryRowsExcluded() {
        let lockedLines = [
            trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil),
            trialBalanceLine("TOTAL", debitCents: 100_000, creditCents: 100_000, isSummary: true)
        ]
        let snapshot = PeriodLockSnapshot.capture(lockedThrough: period, from: lockedLines)
        #expect(snapshot.lines.count == 1)
        let currentLines = [
            trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil),
            trialBalanceLine("TOTAL", debitCents: 999_999, creditCents: 999_999, isSummary: true)
        ]
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: currentLines), context: context(lock: lock, snapshot: snapshot))
        guard case .pass = outcome else {
            Issue.record("expected .pass — only the summary row differs, and it's excluded")
            return
        }
    }

    @Test("No period lock produces .cannotEvaluate")
    func noPeriodLockCannotEvaluate() {
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: []), context: context())
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no lock set")
            return
        }
    }

    @Test("A lock with no snapshot produces .cannotEvaluate")
    func lockWithNoSnapshotCannotEvaluate() {
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: []), context: context(lock: lock))
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — lock predates the snapshot feature")
            return
        }
    }

    @Test("Viewing a different period than the locked one produces .cannotEvaluate")
    func differentPeriodCannotEvaluate() {
        let lockedLines = [trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil)]
        let snapshot = PeriodLockSnapshot.capture(lockedThrough: period, from: lockedLines)
        let otherPeriod = AccountingPeriod(year: 2026, month: 8)
        let outcome = ClosedPeriodDriftRule.evaluate(
            dataSet(trialBalanceLines: lockedLines, period: otherPeriod),
            context: RuleContext(period: otherPeriod, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), periodLock: lock, periodLockSnapshot: snapshot)
        )
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — currently synced period isn't the locked one")
            return
        }
    }

    @Test("No Trial Balance loaded for this sync produces .cannotEvaluate")
    func noTrialBalanceLoadedCannotEvaluate() {
        let lockedLines = [trialBalanceLine("Checking", debitCents: 100_000, creditCents: nil)]
        let snapshot = PeriodLockSnapshot.capture(lockedThrough: period, from: lockedLines)
        let outcome = ClosedPeriodDriftRule.evaluate(dataSet(trialBalanceLines: []), context: context(lock: lock, snapshot: snapshot))
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no Trial Balance fetched this sync")
            return
        }
    }
}
