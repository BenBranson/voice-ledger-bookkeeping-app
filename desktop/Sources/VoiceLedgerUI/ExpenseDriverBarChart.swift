import SwiftUI
import Charts
import Core
import DesignSystem

/// Horizontal ranked bars for the top expense line items, from
/// `TopExpenseDrivers`'s already-computed, already-sorted list.
public struct ExpenseDriverBarChart: View {
    private let drivers: [TopExpenseDrivers.Driver]

    public init(drivers: [TopExpenseDrivers.Driver]) {
        self.drivers = drivers
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("TOP EXPENSE DRIVERS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                if drivers.isEmpty {
                    Text("Not available")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    Chart(Array(drivers.enumerated()), id: \.element.id) { index, driver in
                        BarMark(
                            x: .value("Amount", driver.amount.majorUnitsDouble),
                            y: .value("Expense", driver.label)
                        )
                        .foregroundStyle(VLChartPalette.gradient(at: index))
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text(driver.amount.description)
                                .font(VLTypography.tabularNumeric())
                                .fontWeight(.medium)
                                .foregroundStyle(VLColor.textPrimary)
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
                    .frame(height: CGFloat(drivers.count) * 36 + 20)
                }
            }
        }
    }
}
