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

    public static func top(_ count: Int, from profitAndLossLines: [ReportLine]) -> [Driver] {
        let splitLabel = profitAndLossLines.contains(where: { $0.isSummary && $0.label == "Gross Profit" }) ? "Gross Profit" : "Total Income"
        guard let splitIndex = profitAndLossLines.firstIndex(where: { $0.isSummary && $0.label == splitLabel }) else { return [] }
        let expenseLines = profitAndLossLines[(splitIndex + 1)...]
        return expenseLines
            .compactMap { line -> Driver? in
                guard !line.isSummary, let amount = line.amount, amount.minorUnits != 0 else { return nil }
                return Driver(label: line.label, amount: amount)
            }
            .sorted { abs($0.amount.minorUnits) > abs($1.amount.minorUnits) }
            .prefix(count)
            .map { $0 }
    }
}
