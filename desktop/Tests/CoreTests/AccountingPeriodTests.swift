import Testing
@testable import Core

@Suite("AccountingPeriod.previousMonth")
struct AccountingPeriodTests {
    @Test("An ordinary month steps back within the same year")
    func ordinaryMonthStepsBack() {
        #expect(AccountingPeriod(year: 2026, month: 7).previousMonth == AccountingPeriod(year: 2026, month: 6))
    }

    @Test("January wraps to December of the prior year")
    func januaryWrapsToPriorDecember() {
        #expect(AccountingPeriod(year: 2026, month: 1).previousMonth == AccountingPeriod(year: 2025, month: 12))
    }
}
