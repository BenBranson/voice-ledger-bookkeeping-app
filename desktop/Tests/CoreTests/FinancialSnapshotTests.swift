import Foundation
import Testing
@testable import Core

struct FinancialSnapshotTests {
    let line = ReportLine(label: "Total", amount: Money(minorUnits: 100, currency: .usd), depth: 0, isSummary: true)
    func data(coverage: Coverage = .complete, balanceSheet: Bool = true, profitAndLoss: Bool = true) -> NormalizedDataSet {
        NormalizedDataSet(realmID: RealmID(rawValue: "test"), period: AccountingPeriod(year: 2026, month: 7), transactions: [],
                          profitAndLossLines: profitAndLoss ? [line] : [], balanceSheetLines: balanceSheet ? [line] : [],
                          coverage: coverage, companyFacts: CompanyFacts(customTxnNumbersForPurchases: false))
    }
    @Test func failedOrPartialRefreshCannotCreateAFreshSnapshot() {
        let now = Date()
        #expect(FinancialSnapshot.fromCompleteSync(data(balanceSheet: false), syncedAt: now) == nil)
        #expect(FinancialSnapshot.fromCompleteSync(data(profitAndLoss: false), syncedAt: now) == nil)
        #expect(FinancialSnapshot.fromCompleteSync(data(coverage: .partial(reason: "truncated")), syncedAt: now) == nil)
        let snapshot = FinancialSnapshot.fromCompleteSync(data(), syncedAt: now)
        #expect(snapshot?.syncedAt == now)
        #expect(snapshot?.balanceSheetLines == [line])
    }
}
