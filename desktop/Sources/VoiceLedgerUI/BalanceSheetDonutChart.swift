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
            DonutCard(title: "Assets", slices: assetSlices)
            DonutCard(title: "Liabilities & Equity", slices: liabilitiesAndEquitySlices)
        }
    }
}

/// One donut, with click-to-inspect: tapping a slice shows its title and
/// amount in a callout beside the chart — real, requested feature
/// (2026-08-29) — while the always-visible legend list stays underneath,
/// unchanged (the owner's own instruction: "keep the reference underneath
/// the graphs").
private struct DonutCard: View {
    let title: String
    let slices: [BalanceSheetBreakdown.Slice]

    @State private var selectedAmount: Double?

    private var selectedSlice: BalanceSheetBreakdown.Slice? {
        guard let selectedAmount else { return nil }
        return slices.min { lhs, rhs in
            abs(lhs.amount.majorUnitsDouble - selectedAmount) < abs(rhs.amount.majorUnitsDouble - selectedAmount)
        }
    }

    var body: some View {
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
                    HStack(spacing: VLSpacing.sm) {
                        Chart(Array(slices.enumerated()), id: \.element.id) { index, slice in
                            SectorMark(angle: .value("Amount", slice.amount.majorUnitsDouble), innerRadius: .ratio(0.6), angularInset: 1.5)
                                .foregroundStyle(VLChartPalette.color(at: index))
                                .cornerRadius(3)
                                // Dims every slice except the selected one,
                                // so a click visibly highlights which wedge
                                // the callout is describing.
                                .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.35)
                        }
                        .chartAngleSelection(value: $selectedAmount)
                        .frame(width: 140, height: 140)

                        if let selectedSlice {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                Text(selectedSlice.label)
                                    .font(VLTypography.cardTitle())
                                    .foregroundStyle(VLColor.textPrimary)
                                    .lineLimit(2)
                                Text(selectedSlice.amount.description)
                                    .font(VLTypography.tabularNumeric())
                                    .foregroundStyle(VLColor.cyan)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .animation(.default, value: selectedAmount)

                    // Owner directive (2026-08-29): a real, confirmed bug —
                    // the chart above renders every slice, but this legend
                    // used to cap at `.prefix(5)`, silently dropping any
                    // account past the 5th (7 wedges, 5 labels — exactly
                    // what was reported live, including the unlabeled
                    // "purple" slice). Every wedge must have a legend row;
                    // nothing about a real account balance gets hidden.
                    Text("Click a slice to see its exact label and amount")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)

                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        ForEach(Array(slices.enumerated()), id: \.element.id) { index, slice in
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
