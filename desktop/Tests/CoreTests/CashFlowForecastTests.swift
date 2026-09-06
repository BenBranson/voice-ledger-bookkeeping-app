import Foundation
import Testing
@testable import Core

@Suite("CashFlowForecastEngine")
struct CashFlowForecastTests {
    func agingLine(label: String, current: Int64? = nil, d1to30: Int64? = nil, d31to60: Int64? = nil, d61to90: Int64? = nil, d91: Int64? = nil) -> AgingLine {
        func money(_ v: Int64?) -> Money? { v.map { Money(minorUnits: $0, currency: .usd) } }
        let total = [current, d1to30, d31to60, d61to90, d91].compactMap { $0 }.reduce(0, +)
        return AgingLine(
            label: label,
            current: money(current),
            days1to30: money(d1to30),
            days31to60: money(d31to60),
            days61to90: money(d61to90),
            days91AndOver: money(d91),
            total: money(total),
            depth: 1,
            isSummary: false
        )
    }

    @Test("30-day horizon counts only the Current aging bucket as expected inflow")
    func thirtyDayHorizonUsesCurrentBucketOnly() {
        let receivables = [agingLine(label: "Customer A", current: 10_000, d1to30: 5_000)]
        let forecast = CashFlowForecastEngine.compute(
            currentCash: Money(minorUnits: 100_000, currency: .usd),
            agedReceivablesLines: receivables,
            agedPayablesLines: [],
            recurringVendors: [],
            asOf: AccountingDate(year: 2026, month: 7, day: 1)
        )
        let thirtyDay = forecast.horizons.first { $0.days == 30 }
        #expect(thirtyDay?.expectedInflow == Money(minorUnits: 10_000, currency: .usd))
    }

    @Test("90-day horizon includes every bucket except 91+, which is reported separately as at-risk")
    func ninetyDayHorizonExcludes91Plus() {
        let receivables = [agingLine(label: "Customer A", current: 1_000, d1to30: 2_000, d31to60: 3_000, d61to90: 4_000, d91: 5_000)]
        let forecast = CashFlowForecastEngine.compute(
            currentCash: Money(minorUnits: 0, currency: .usd),
            agedReceivablesLines: receivables,
            agedPayablesLines: [],
            recurringVendors: [],
            asOf: AccountingDate(year: 2026, month: 7, day: 1)
        )
        let ninetyDay = forecast.horizons.first { $0.days == 90 }
        #expect(ninetyDay?.expectedInflow == Money(minorUnits: 10_000, currency: .usd))
        #expect(forecast.atRiskReceivables == Money(minorUnits: 5_000, currency: .usd))
    }

    @Test("Projected ending cash is starting cash plus inflow minus outflow")
    func projectsEndingCash() {
        let receivables = [agingLine(label: "Customer A", current: 10_000)]
        let payables = [agingLine(label: "Vendor A", current: 4_000)]
        let forecast = CashFlowForecastEngine.compute(
            currentCash: Money(minorUnits: 50_000, currency: .usd),
            agedReceivablesLines: receivables,
            agedPayablesLines: payables,
            recurringVendors: [],
            asOf: AccountingDate(year: 2026, month: 7, day: 1)
        )
        let thirtyDay = forecast.horizons.first { $0.days == 30 }
        #expect(thirtyDay?.projectedEndingCash == Money(minorUnits: 56_000, currency: .usd))
    }

    @Test("A recurring vendor's projected charge within the horizon adds to expected outflow")
    func includesRecurringVendorProjection() {
        let vendor = RecurringVendor(
            vendorName: "Adobe",
            occurrenceCount: 4,
            averageAmount: Money(minorUnits: 5_000, currency: .usd),
            averageIntervalDays: 30,
            lastChargeDate: AccountingDate(year: 2026, month: 6, day: 15),
            lastAmount: Money(minorUnits: 5_000, currency: .usd),
            expectedNextChargeDate: AccountingDate(year: 2026, month: 7, day: 15),
            lastAmountChanged: false
        )
        let forecast = CashFlowForecastEngine.compute(
            currentCash: Money(minorUnits: 0, currency: .usd),
            agedReceivablesLines: [],
            agedPayablesLines: [],
            recurringVendors: [vendor],
            asOf: AccountingDate(year: 2026, month: 7, day: 1)
        )
        let thirtyDay = forecast.horizons.first { $0.days == 30 }
        #expect(thirtyDay?.expectedOutflow == Money(minorUnits: 5_000, currency: .usd))
    }

    @Test("nil starting cash and no aging data yields nil throughout, never a fabricated zero")
    func handlesMissingData() {
        let forecast = CashFlowForecastEngine.compute(
            currentCash: nil,
            agedReceivablesLines: [],
            agedPayablesLines: [],
            recurringVendors: [],
            asOf: AccountingDate(year: 2026, month: 7, day: 1)
        )
        for horizon in forecast.horizons {
            #expect(horizon.expectedInflow == nil)
            #expect(horizon.expectedOutflow == nil)
            #expect(horizon.projectedEndingCash == nil)
        }
        #expect(forecast.atRiskReceivables == nil)
    }
}
