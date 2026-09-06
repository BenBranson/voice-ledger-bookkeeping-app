import SwiftUI
import Charts
import Core
import DesignSystem

/// A generic horizontal ranked-bar chart for any already-sorted
/// `(label, amount)` list — added 2026-09-06 for the voice assistant's
/// `generate_chart` tool's vendor-spend and Pareto-cost-driver charts,
/// which have no dedicated Core type of their own the way
/// `TopExpenseDrivers`/`ExpenseDriverBarChart` do. Same visual language as
/// `ExpenseDriverBarChart` (this app's one existing ranked-bar chart) —
/// deliberately not a copy-paste of it, since the only real difference is
/// which input type feeds it and the title shown.
public struct RankedMoneyBarChart: View {
    public struct Entry: Identifiable {
        public let id: String
        public let label: String
        public let amount: Money
        /// Pareto-only — running total as a percentage of the whole
        /// (0...100). `nil` for a plain ranked chart (vendor spend).
        public let cumulativePercent: Double?

        public init(id: String, label: String, amount: Money, cumulativePercent: Double? = nil) {
            self.id = id
            self.label = label
            self.amount = amount
            self.cumulativePercent = cumulativePercent
        }
    }

    private let title: String
    private let entries: [Entry]

    public init(title: String, entries: [Entry]) {
        self.title = title
        self.entries = entries
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text(title.uppercased())
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                if entries.isEmpty {
                    Text("Not available")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    Chart(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        BarMark(
                            x: .value("Amount", entry.amount.majorUnitsDouble),
                            y: .value("Label", entry.label)
                        )
                        .foregroundStyle(VLChartPalette.color(at: index))
                        .cornerRadius(3)
                        .annotation(position: .trailing) {
                            Text(entry.cumulativePercent.map { "\(entry.amount.description) — \(String(format: "%.0f%%", $0)) cumulative" } ?? entry.amount.description)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textSecondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine().foregroundStyle(VLColor.border)
                        }
                    }
                    .chartYAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textSecondary)
                        }
                    }
                    .frame(height: CGFloat(entries.count) * 36 + 20)
                }
            }
        }
    }
}
