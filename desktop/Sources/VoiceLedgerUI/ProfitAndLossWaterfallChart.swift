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
                        yEnd: .value("End", max(segment.start, segment.end)),
                        width: .ratio(0.55)
                    )
                    .foregroundStyle(color(for: segment))
                    .cornerRadius(4)
                    .annotation(position: segment.end >= segment.start ? .top : .bottom) {
                        Text(Self.formatter.string(from: NSNumber(value: segment.end - (segment.isTotal ? 0 : segment.start))) ?? "")
                            .font(VLTypography.caption())
                            .fontWeight(.medium)
                            .foregroundStyle(VLColor.textPrimary)
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
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(VLColor.border)
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(Self.formatter.string(from: NSNumber(value: amount)) ?? "")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            }
                        }
                    }
                }
                .frame(height: 220)
                .padding(.top, VLSpacing.md)
            }
        }
    }

    /// Distinct hues per segment role, from `VLChartPalette` — real,
    /// reported problem (2026-08-29): the old cyan/blue-only scheme made
    /// the chart look flat and arbitrary rather than purposeful.
    private func color(for segment: ProfitAndLossWaterfall.Segment) -> Color {
        switch segment.label {
        case "Net Income": return segment.end >= 0 ? VLColor.teal : .red
        case "Revenue": return VLColor.cyan
        case "COGS": return VLChartPalette.color(at: 1) // orange
        default: return VLChartPalette.color(at: 4) // indigo — Expenses and any future segment
        }
    }

    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
