import Foundation
import Testing
@testable import Core

@Suite("AgingSummary")
struct AgingSummaryTests {
    func line(label: String, current: Int64?, days1to30: Int64? = nil, total: Int64, isSummary: Bool = false) -> AgingLine {
        AgingLine(
            label: label,
            current: current.map { Money(minorUnits: $0, currency: .usd) },
            days1to30: days1to30.map { Money(minorUnits: $0, currency: .usd) },
            days31to60: nil,
            days61to90: nil,
            days91AndOver: nil,
            total: Money(minorUnits: total, currency: .usd),
            depth: isSummary ? 0 : 1,
            isSummary: isSummary
        )
    }

    @Test("Sums leaf rows only, excluding a parent subtotal row")
    func sumsLeavesOnly() {
        let lines = [
            line(label: "Customer A", current: 10_000, total: 10_000),
            line(label: "Customer B (parent)", current: 0, total: 30_000, isSummary: true),
            line(label: "Customer B - Sub 1", current: 20_000, total: 20_000),
            line(label: "Customer B - Sub 2", current: 10_000, days1to30: 0, total: 10_000)
        ]
        let result = AgingSummary.summarize(lines)
        #expect(result?.totalAmount == Money(minorUnits: 40_000, currency: .usd))
        #expect(result?.currentAmount == Money(minorUnits: 40_000, currency: .usd))
    }

    @Test("Computes overdue amount and percent from the aging buckets")
    func computesOverdue() {
        let lines = [
            line(label: "Customer A", current: 7_000, days1to30: 3_000, total: 10_000)
        ]
        let result = AgingSummary.summarize(lines)
        #expect(result?.overdueAmount == Money(minorUnits: 3_000, currency: .usd))
        #expect(result?.percentOverdue == 30.0)
    }

    @Test("Empty input produces nil, not a crash or a fabricated zero")
    func handlesEmptyInput() {
        #expect(AgingSummary.summarize([]) == nil)
    }

    @Test("daysOutstanding is a plain (balance / period amount) * days formula")
    func daysOutstandingFormula() {
        let balance = Money(minorUnits: 30_000, currency: .usd)
        let periodAmount = Money(minorUnits: 300_000, currency: .usd)
        let days = AgingSummary.daysOutstanding(balance: balance, periodAmount: periodAmount, daysInPeriod: 30)
        #expect(days == 3.0)
    }

    @Test("daysOutstanding is nil when the period amount is zero or currencies differ")
    func daysOutstandingNilCases() {
        let balance = Money(minorUnits: 30_000, currency: .usd)
        #expect(AgingSummary.daysOutstanding(balance: balance, periodAmount: Money(minorUnits: 0, currency: .usd), daysInPeriod: 30) == nil)
        #expect(AgingSummary.daysOutstanding(balance: balance, periodAmount: nil, daysInPeriod: 30) == nil)
    }
}
