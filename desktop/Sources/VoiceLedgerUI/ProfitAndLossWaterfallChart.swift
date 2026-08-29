import SwiftUI
import Charts
import Core
import DesignSystem

/// Revenue -> COGS -> Expenses -> Net Income, from
/// `ProfitAndLossWaterfall`'s already-computed running-total segments.
/// Swift Charts has no native waterfall mark — each segment is a `BarMark`
/// positioned by its own precomputed `start`/`end`, not a new chart type.
public struct ProfitAndLossWaterfallChart: View {
    private let segments: [ProfitAndLossWaterfall.Segment]

    public init(segments: [ProfitAndLossWaterfall.Segment]) {
        self.segments = segments
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("REVENUE TO NET INCOME")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                Chart(segments) { segment in
                    BarMark(
                        x: .value("Segment", segment.label),
                        yStart: .value("Start", min(segment.start, segment.end)),
                        yEnd: .value("End", max(segment.start, segment.end))
                    )
                    .foregroundStyle(color(for: segment))
                    .cornerRadius(3)
                    .annotation(position: .top) {
                        Text(Self.formatter.string(from: NSNumber(value: segment.end - (segment.isTotal ? 0 : segment.start))) ?? "")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisValueLabel()
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(VLColor.border)
                    }
                }
                .frame(height: 200)
            }
        }
    }

    private func color(for segment: ProfitAndLossWaterfall.Segment) -> Color {
        if segment.label == "Net Income" {
            return segment.end >= 0 ? VLColor.teal : .red
        }
        if segment.label == "Revenue" { return VLColor.cyan }
        return VLColor.blue
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
