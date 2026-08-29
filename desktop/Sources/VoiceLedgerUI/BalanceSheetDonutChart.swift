import SwiftUI
import Charts
import Core
import DesignSystem

/// Two donuts — Assets, and Liabilities & Equity — from
/// `BalanceSheetBreakdown`'s already-computed slices. Apple's native
/// Charts framework (macOS 13+, this app targets macOS 15 — no third-party
/// dependency), matching this project's existing "hand-roll against the
/// platform SDK" posture.
public struct BalanceSheetDonutChart: View {
    private let assetSlices: [BalanceSheetBreakdown.Slice]
    private let liabilitiesAndEquitySlices: [BalanceSheetBreakdown.Slice]

    public init(assetSlices: [BalanceSheetBreakdown.Slice], liabilitiesAndEquitySlices: [BalanceSheetBreakdown.Slice]) {
        self.assetSlices = assetSlices
        self.liabilitiesAndEquitySlices = liabilitiesAndEquitySlices
    }

    public var body: some View {
        HStack(spacing: VLSpacing.md) {
            donut(title: "Assets", slices: assetSlices)
            donut(title: "Liabilities & Equity", slices: liabilitiesAndEquitySlices)
        }
    }

    @ViewBuilder
    private func donut(title: String, slices: [BalanceSheetBreakdown.Slice]) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text(title.uppercased())
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)

                if slices.isEmpty {
                    Text("Not available")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                        SectorMark(angle: .value("Amount", slice.amount.majorUnitsDouble), innerRadius: .ratio(0.6), angularInset: 1.5)
                            .foregroundStyle(VLChartPalette.color(at: index))
                            .cornerRadius(3)
                    }
                    .frame(height: 140)

                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        ForEach(Array(slices.prefix(5).enumerated()), id: \.element.id) { index, slice in
                            HStack(spacing: VLSpacing.xs) {
                                Circle()
                                    .fill(VLChartPalette.color(at: index))
                                    .frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(slice.amount.description)
                                    .font(VLTypography.tabularNumeric())
                                    .foregroundStyle(VLColor.textPrimary)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
