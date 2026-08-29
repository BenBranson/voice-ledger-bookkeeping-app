import Foundation

/// Revenue -> (COGS, if this company's P&L has one) -> Expenses -> Net
/// Income, as running-total segments for the P&L waterfall chart. Pure,
/// deterministic. Deliberately does NOT look up a "Total Cost of Goods
/// Sold"/"Total Expenses" label the way `FinancialKPIs` looks up "Gross
/// Profit" — that would be a second unverified label guess on top of the
/// ones already flagged there. Instead, the "Expenses" segment is derived
/// arithmetically (Gross Profit, or Total Income if this company has no
/// COGS section, minus Net Income) so it's always internally consistent
/// by construction, never a wrong number from a label that didn't match.
public enum ProfitAndLossWaterfall {
    public struct Segment: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let start: Double
        public let end: Double
        /// A "from zero" bar (Revenue, Net Income) vs. a delta bar (COGS,
        /// Expenses) — the two render differently in the chart.
        public let isTotal: Bool

        public init(label: String, start: Double, end: Double, isTotal: Bool) {
            self.id = label
            self.label = label
            self.start = start
            self.end = end
            self.isTotal = isTotal
        }
    }

    private static func summaryAmount(_ label: String, in lines: [ReportLine]) -> Money? {
        lines.first(where: { $0.isSummary && $0.label == label })?.amount
    }

    /// `nil` if "Total Income" (this file's one required, unverified label
    /// — see `FinancialKPIs`'s doc comment) or Net Income (verified,
    /// `TaxEstimate.netIncome`) is missing.
    public static func segments(from profitAndLossLines: [ReportLine]) -> [Segment]? {
        guard let totalIncome = summaryAmount("Total Income", in: profitAndLossLines),
              let netIncome = TaxEstimate.netIncome(from: profitAndLossLines),
              totalIncome.currency == netIncome.currency else { return nil }

        var segments: [Segment] = []
        let revenue = totalIncome.majorUnitsDouble
        segments.append(Segment(label: "Revenue", start: 0, end: revenue, isTotal: true))

        var running = revenue
        // Real, reported problem (2026-08-29): when a company has no COGS
        // section, "Gross Profit" equals "Total Income" — the segment
        // computed to a zero-width bar with a floating "$0" label and
        // nothing visibly under it. Only added when it's an actual,
        // visible delta.
        if let grossProfit = summaryAmount("Gross Profit", in: profitAndLossLines), grossProfit.minorUnits != totalIncome.minorUnits {
            let afterCOGS = grossProfit.majorUnitsDouble
            segments.append(Segment(label: "COGS", start: running, end: afterCOGS, isTotal: false))
            running = afterCOGS
        }

        let netIncomeValue = netIncome.majorUnitsDouble
        segments.append(Segment(label: "Expenses", start: running, end: netIncomeValue, isTotal: false))
        segments.append(Segment(label: "Net Income", start: 0, end: netIncomeValue, isTotal: true))
        return segments
    }
}
