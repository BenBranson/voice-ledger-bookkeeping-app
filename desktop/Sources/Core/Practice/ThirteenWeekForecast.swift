import Foundation

/// A planned one-off cash item the bookkeeper adds ("buying a trailer in
/// week 4"): positive = money in, negative = money out. Stored per realm.
public struct PlannedCashItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var week: Int          // 1...13
    public var description: String
    public var amount: Money      // signed

    public init(id: String = UUID().uuidString, week: Int, description: String, amount: Money) {
        self.id = id
        self.week = week
        self.description = description
        self.amount = amount
    }
}

public struct ForecastWeek: Identifiable, Sendable, Equatable {
    public var id: Int { number }
    public let number: Int
    public let start: AccountingDate
    public let end: AccountingDate
    public let collections: Money
    public let billPayments: Money
    public let recurringCharges: Money
    public let planned: Money
    public let endingCash: Money

    public var netChange: Money { collections - billPayments - recurringCharges + planned }
}

public struct ThirteenWeekForecast: Sendable, Equatable {
    public let startingCash: Money
    public let weeks: [ForecastWeek]
    public let atRiskReceivables: Money?

    /// The week with the least cash at its end.
    public var lowestWeek: ForecastWeek? { weeks.min { $0.endingCash < $1.endingCash } }
    /// First week the cash goes below zero, if any.
    public var firstNegativeWeek: ForecastWeek? { weeks.first { $0.endingCash.minorUnits < 0 } }
}

/// Owner directive 2026-10-02 (podcast: "the 13-week cash flow forecast is
/// the windshield"). Deterministic, from the same inputs as the 30/60/90-day
/// forecast: aged receivables and payables, detected recurring vendors, and
/// the bookkeeper's planned items.
///
/// Stated assumption (shown on the page): aging buckets carry no exact due
/// dates, so each bucket is spread evenly over the weeks it is expected to
/// clear: current over weeks 1–4, 1–30 days past due over weeks 5–8, 31–90
/// days past due over weeks 9–13. Over 90 days is never counted as coming
/// in. Recurring charges land on their projected dates.
public enum ThirteenWeekForecastEngine {
    public static func compute(currentCash: Money, agedReceivablesLines: [AgingLine], agedPayablesLines: [AgingLine],
                               recurringVendors: [RecurringVendor], planned: [PlannedCashItem], asOf: AccountingDate) -> ThirteenWeekForecast {
        let usd = currentCash.currency
        let ar = AgingSummary.bucketTotals(agedReceivablesLines)
        let ap = AgingSummary.bucketTotals(agedPayablesLines)
        func spread(_ b: AgingSummary.BucketTotals?) -> [Int64] {
            var perWeek = [Int64](repeating: 0, count: 13)
            guard let b else { return perWeek }
            func place(_ m: Money?, _ weeks: ClosedRange<Int>) {
                guard let m, m.currency == usd, m.minorUnits != 0 else { return }
                let n = Int64(weeks.count)
                let each = m.minorUnits / n
                var remainder = m.minorUnits - each * n
                for w in weeks {
                    var share = each
                    if remainder != 0 { share += remainder > 0 ? 1 : -1; remainder += remainder > 0 ? -1 : 1 }
                    perWeek[w - 1] += share
                }
            }
            place(b.current, 1...4)
            place(b.days1to30, 5...8)
            place(b.days31to60, 9...13)
            place(b.days61to90, 9...13)
            return perWeek
        }
        let inflow = spread(ar)
        let outflow = spread(ap)

        var recurring = [Int64](repeating: 0, count: 13)
        for vendor in recurringVendors where vendor.averageIntervalDays > 0 && vendor.averageAmount.currency == usd {
            var occurrence = vendor.expectedNextChargeDate
            var guardCount = 0
            while guardCount < 60 {
                guardCount += 1
                let offset = AccountingDate.daysBetween(asOf, occurrence)
                if offset >= 91 { break }
                if offset >= 0 { recurring[offset / 7] += vendor.averageAmount.minorUnits }
                occurrence = occurrence.adding(days: max(1, Int(vendor.averageIntervalDays.rounded())))
            }
        }
        var plannedPerWeek = [Int64](repeating: 0, count: 13)
        for item in planned where (1...13).contains(item.week) && item.amount.currency == usd { plannedPerWeek[item.week - 1] += item.amount.minorUnits }

        var running = currentCash.minorUnits
        var weeks: [ForecastWeek] = []
        for i in 0..<13 {
            running += inflow[i] - outflow[i] - recurring[i] + plannedPerWeek[i]
            let start = asOf.adding(days: i * 7)
            weeks.append(ForecastWeek(number: i + 1, start: start, end: start.adding(days: 6),
                                      collections: Money(minorUnits: inflow[i], currency: usd), billPayments: Money(minorUnits: outflow[i], currency: usd),
                                      recurringCharges: Money(minorUnits: recurring[i], currency: usd), planned: Money(minorUnits: plannedPerWeek[i], currency: usd),
                                      endingCash: Money(minorUnits: running, currency: usd)))
        }
        return ThirteenWeekForecast(startingCash: currentCash, weeks: weeks, atRiskReceivables: ar?.days91AndOver)
    }
}
