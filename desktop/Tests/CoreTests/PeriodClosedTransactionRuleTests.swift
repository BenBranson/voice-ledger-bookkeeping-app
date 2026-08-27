import Testing
@testable import Core
import Foundation

@Suite("VL-PERIOD-CLOSED-001 — PeriodClosedTransactionRule")
struct PeriodClosedTransactionRuleTests {
    let realm = RealmID(rawValue: "9341456442848752")
    let period = AccountingPeriod(year: 2026, month: 6)

    func context(periodLock: PeriodLock?) -> RuleContext {
        RuleContext(period: period, materiality: .defaultPolicy, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false), periodLock: periodLock)
    }

    func transaction(id: String, entityKind: QBOEntityKind = .purchase, date: AccountingDate = AccountingDate(year: 2026, month: 6, day: 15), amountMinorUnits: Int64 = 48_620, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: id, entityKind: entityKind, vendorName: "Permian Supply",
            txnDate: date, totalAmount: Money(minorUnits: amountMinorUnits, currency: .usd),
            paymentAccountID: "checking-1", docNumber: nil, isVoided: isVoided, memo: nil,
            provenance: .qboAPI(readAt: Date())
        )
    }

    func dataSet(_ transactions: [LedgerTransaction], coverage: Coverage = .complete) -> NormalizedDataSet {
        NormalizedDataSet(
            realmID: realm, period: period, transactions: transactions,
            coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false)
        )
    }

    @Test("No period lock set at all — .cannotEvaluate, never a silent .pass")
    func noPeriodLockCannotEvaluate() {
        let txn = transaction(id: "t1")
        let outcome = PeriodClosedTransactionRule.evaluate(dataSet([txn]), context: context(periodLock: nil))
        guard case .cannotEvaluate = outcome else {
            Issue.record("expected .cannotEvaluate — no lock set")
            return
        }
    }

    @Test("A transaction dated in the locked month produces a .high-confidence finding")
    func transactionInLockedMonthProducesFinding() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        let txn = transaction(id: "t1", date: AccountingDate(year: 2026, month: 6, day: 20))
        let outcome = PeriodClosedTransactionRule.evaluate(dataSet([txn]), context: context(periodLock: lock))
        guard case .findings(let findings) = outcome, findings.count == 1 else {
            Issue.record("expected one finding")
            return
        }
        #expect(findings[0].confidence == .high)
    }

    @Test("A transaction dated AFTER the locked month produces no finding")
    func transactionAfterLockedMonthProducesNoFinding() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 5), lockedBy: "Ben")
        let txn = transaction(id: "t1", date: AccountingDate(year: 2026, month: 6, day: 1))
        let outcome = PeriodClosedTransactionRule.evaluate(dataSet([txn]), context: context(periodLock: lock))
        guard case .pass = outcome else {
            Issue.record("expected .pass — transaction is after the lock")
            return
        }
    }

    @Test("A voided transaction in the locked period is excluded")
    func voidedTransactionExcluded() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        let txn = transaction(id: "t1", isVoided: true)
        let outcome = PeriodClosedTransactionRule.evaluate(dataSet([txn]), context: context(periodLock: lock))
        guard case .pass = outcome else {
            Issue.record("expected .pass — the only transaction is voided")
            return
        }
    }

    @Test("An imported bank statement line is excluded — it isn't a posted QBO transaction")
    func importedStatementLineExcluded() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        let line = transaction(id: "s1", entityKind: .importedBankStatementLine)
        let outcome = PeriodClosedTransactionRule.evaluate(dataSet([line]), context: context(periodLock: lock))
        guard case .pass = outcome else {
            Issue.record("expected .pass — statement lines are excluded")
            return
        }
    }

    @Test("Below materiality floor produces no finding")
    func belowMaterialityFloorExcluded() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        let txn = transaction(id: "t1", amountMinorUnits: 500)
        let outcome = PeriodClosedTransactionRule.evaluate(dataSet([txn]), context: context(periodLock: lock))
        guard case .pass = outcome else {
            Issue.record("expected .pass")
            return
        }
    }
}
