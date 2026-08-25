import Testing
@testable import Core

@Suite("PeriodLock")
struct PeriodLockTests {
    @Test("A date in the locked month is locked")
    func sameMonthIsLocked() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        #expect(lock.isLocked(AccountingDate(year: 2026, month: 6, day: 15)))
    }

    @Test("A date before the locked month is locked")
    func earlierMonthIsLocked() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        #expect(lock.isLocked(AccountingDate(year: 2026, month: 3, day: 1)))
        #expect(lock.isLocked(AccountingDate(year: 2025, month: 12, day: 31)))
    }

    @Test("A date after the locked month is NOT locked")
    func laterMonthIsNotLocked() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        #expect(!lock.isLocked(AccountingDate(year: 2026, month: 7, day: 1)))
        #expect(!lock.isLocked(AccountingDate(year: 2027, month: 1, day: 1)))
    }
}

@Suite("PeriodLockCheck.transactionsInLockedPeriod")
struct PeriodLockCheckTests {
    private func makeTransaction(date: AccountingDate, isVoided: Bool = false) -> LedgerTransaction {
        LedgerTransaction(
            id: "txn-\(date.year)-\(date.month)-\(date.day)-\(isVoided)",
            entityKind: .purchase,
            vendorName: "Acme",
            txnDate: date,
            totalAmount: Money(minorUnits: 1000, currency: .usd),
            paymentAccountID: "acct-1",
            docNumber: nil,
            isVoided: isVoided,
            memo: nil,
            provenance: .qboAPI(readAt: .init())
        )
    }

    @Test("A transaction dated in the locked period is included")
    func includesLockedTransaction() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        let txn = makeTransaction(date: AccountingDate(year: 2026, month: 5, day: 10))
        #expect(PeriodLockCheck.transactionsInLockedPeriod([txn], lock: lock) == [txn])
    }

    @Test("A transaction dated after the locked period is excluded")
    func excludesLaterTransaction() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        let txn = makeTransaction(date: AccountingDate(year: 2026, month: 7, day: 1))
        #expect(PeriodLockCheck.transactionsInLockedPeriod([txn], lock: lock).isEmpty)
    }

    @Test("A voided transaction in the locked period is excluded")
    func excludesVoidedTransaction() {
        let lock = PeriodLock(lockedThrough: AccountingPeriod(year: 2026, month: 6), lockedBy: "Ben")
        let txn = makeTransaction(date: AccountingDate(year: 2026, month: 5, day: 10), isVoided: true)
        #expect(PeriodLockCheck.transactionsInLockedPeriod([txn], lock: lock).isEmpty)
    }
}
