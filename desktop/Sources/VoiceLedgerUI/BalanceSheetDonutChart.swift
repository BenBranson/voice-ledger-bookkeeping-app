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

    /// A donut can't draw a negative wedge honestly, so negative balances
    /// (an overdrawn checking account) are pulled out and shown as an
    /// alert instead of being coerced to absolute values.
    private var chartSlices: [BalanceSheetBreakdown.Slice] { slices.filter { $0.amount.minorUnits > 0 } }
    private var negativeSlices: [BalanceSheetBreakdown.Slice] { slices.filter { $0.amount.minorUnits < 0 } }

    @State private var selectedAmount: Double?

    private var selectedSlice: BalanceSheetBreakdown.Slice? {
        guard let selectedAmount else { return nil }
        return chartSlices.min { lhs, rhs in
            abs(lhs.amount.majorUnitsDouble - selectedAmount) < abs(rhs.amount.majorUnitsDouble - selectedAmount)
        }
    }

    /// The center-of-donut total — same same-currency guard every other
    /// sum in this app uses (e.g. `ChartPopupView.paretoEntries`) rather
    /// than silently adding across currencies.
    private var totalAmount: Money {
        guard let first = slices.first, slices.allSatisfy({ $0.amount.currency == first.amount.currency }) else {
            return slices.first?.amount ?? Money(minorUnits: 0, currency: .usd)
        }
        let total = slices.reduce(Int64(0)) { $0 + $1.amount.minorUnits }
        return Money(minorUnits: total, currency: first.amount.currency)
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
                    if !negativeSlices.isEmpty {
                        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                            Label("Overdraft / credit balance — not shown in the chart", systemImage: "exclamationmark.triangle.fill")
                                .font(VLTypography.caption())
                                .foregroundStyle(.red)
                            ForEach(negativeSlices) { slice in
                                HStack {
                                    Text(slice.label).foregroundStyle(VLColor.textPrimary)
                                    Spacer()
                                    Text(slice.amount.accountingDescription).foregroundStyle(.red).monospacedDigit()
                                }
                                .font(VLTypography.caption())
                            }
                        }
                        .padding(VLSpacing.xs)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    HStack(spacing: VLSpacing.md) {
                        // Owner directive (2026-09-06): "the graphs in this
                        // app look primitive... like in Excel, Power BI,
                        // and Tableau" — a radial gradient per wedge (glossy
                        // depth instead of a flat fill), a larger chart, and
                        // a center total (the number the whole donut adds
                        // up to, which Power BI/Tableau donuts always show)
                        // instead of a plain colored ring.
                        Chart(Array(chartSlices.enumerated()), id: \.element.id) { index, slice in
                            SectorMark(angle: .value("Amount", slice.amount.majorUnitsDouble), innerRadius: .ratio(0.62), angularInset: 2)
                                .foregroundStyle(VLChartPalette.radialGradient(at: index))
                                .cornerRadius(4)
                                // Dims every slice except the selected one,
                                // so a click visibly highlights which wedge
                                // the callout is describing.
                                .opacity(selectedSlice == nil || selectedSlice?.id == slice.id ? 1 : 0.35)
                        }
                        .chartAngleSelection(value: $selectedAmount)
                        .chartBackground { proxy in
                            GeometryReader { geometry in
                                if let plotFrame = proxy.plotFrame {
                                    let frame = geometry[plotFrame]
                                    VStack(spacing: 2) {
                                        Text(negativeSlices.isEmpty ? "TOTAL" : "NET")
                                            .font(VLTypography.eyebrow())
                                            .tracking(VLTypography.eyebrowTracking)
                                            .foregroundStyle(VLColor.textMuted)
                                        Text(totalAmount.accountingDescription)
                                            .font(VLTypography.tabularNumeric())
                                            .fontWeight(.semibold)
                                            .foregroundStyle(VLColor.textPrimary)
                                            .minimumScaleFactor(0.6)
                                            .lineLimit(1)
                                    }
                                    .frame(width: frame.width * 0.62)
                                    .position(x: frame.midX, y: frame.midY)
                                }
                            }
                        }
                        .frame(width: 180, height: 180)

                        if let selectedSlice {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                Text(selectedSlice.label)
                                    .font(VLTypography.cardTitle())
                                    .foregroundStyle(VLColor.textPrimary)
                                    .lineLimit(2)
                                Text(selectedSlice.amount.accountingDescription)
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
                        ForEach(Array(chartSlices.enumerated()), id: \.element.id) { index, slice in
                            HStack(spacing: VLSpacing.xs) {
                                Circle()
                                    .fill(VLChartPalette.color(at: index))
                                    .frame(width: 8, height: 8)
                                Text(slice.label)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                Text(slice.amount.accountingDescription)
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
