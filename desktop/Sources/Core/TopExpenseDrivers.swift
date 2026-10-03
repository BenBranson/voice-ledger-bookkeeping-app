import Foundation

/// The top N expense line items by dollar amount, for the P&L's expense-
/// driver bar chart. Pure, deterministic. Expense lines are whatever comes
/// after "Total Income" (or "Gross Profit," if present) in QBO's own
/// report ordering — Income sections come first in every P&L, Expenses
/// after — the same "flattened but ordered" shape `ReportLine`'s doc
/// comment already documents for the Balance Sheet.
public enum TopExpenseDrivers {
    public struct Driver: Identifiable, Sendable, Equatable {
        public let id: String
        public let label: String
        public let amount: Money

        public init(label: String, amount: Money) {
            self.id = label
            self.label = label
            self.amount = amount
        }
    }

    /// Every cost line on a P&L: cost of goods sold, expenses and other expenses, never
    /// income. Fixed 2026-10-03 (caught by the Moneypenny eval): this used to start after
    /// "Gross Profit", which skipped cost of goods sold ($160 in September) so the expense
    /// chart disagreed with Income vs. Expenses, and it would have counted Other Income lines
    /// as costs. Starts after "Total Income" and skips the Other Income section.
    public static func costLines(_ lines: [ReportLine]) -> [ReportLine] {
        guard let start = lines.firstIndex(where: { $0.isSummary && $0.label == "Total Income" }) else { return [] }
        var out: [ReportLine] = []
        var inOtherIncome = false
        for line in lines[(start + 1)...] {
            if !line.isSummary && line.amount == nil && line.label == "Other Income" { inOtherIncome = true; continue }
            if line.isSummary && line.label == "Total Other Income" { inOtherIncome = false; continue }
            if inOtherIncome || line.isSummary { continue }
            out.append(line)
        }
        return out
    }

    public static func top(_ count: Int, from profitAndLossLines: [ReportLine]) -> [Driver] {
        return costLines(profitAndLossLines)
            .compactMap { line -> Driver? in
                guard !line.isSummary, let amount = line.amount, amount.minorUnits != 0 else { return nil }
                return Driver(label: line.label, amount: amount)
            }
            .sorted { abs($0.amount.minorUnits) > abs($1.amount.minorUnits) }
            .prefix(count)
            .map { $0 }
    }
}
