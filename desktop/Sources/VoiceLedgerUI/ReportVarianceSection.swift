import SwiftUI
import Core
import DesignSystem

/// The prior-period comparison card shared by every financial report
/// screen — extracted from `FinancialReportView` (see that type's own doc
/// comment on why this feature is opt-in per call site) so
/// `BalanceSheetReportView`/`ProfitAndLossReportView` reuse the identical
/// behavior rather than reimplementing it.
public struct ReportVarianceSection: View {
    private let currentLines: [ReportLine]
    private let priorPeriodLines: [ReportLine]?
    private let priorPeriodLabel: String?
    private let isLoadingVariance: Bool
    private let varianceError: String?
    private let onLoadVariance: () -> Void

    public init(
        currentLines: [ReportLine],
        priorPeriodLines: [ReportLine]?,
        priorPeriodLabel: String?,
        isLoadingVariance: Bool,
        varianceError: String?,
        onLoadVariance: @escaping () -> Void
    ) {
        self.currentLines = currentLines
        self.priorPeriodLines = priorPeriodLines
        self.priorPeriodLabel = priorPeriodLabel
        self.isLoadingVariance = isLoadingVariance
        self.varianceError = varianceError
        self.onLoadVariance = onLoadVariance
    }

    public var body: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack {
                    Text("VS. \(priorPeriodLabel ?? "PRIOR PERIOD")")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    if let priorPeriodLines, !priorPeriodLines.isEmpty {
                        EmptyView()
                    } else {
                        Button(isLoadingVariance ? "Loading…" : "Compare to prior period") { onLoadVariance() }
                            .disabled(isLoadingVariance)
                            .font(VLTypography.caption())
                    }
                }

                if let varianceError {
                    Text(varianceError)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textSecondary)
                }

                if let priorPeriodLines, !priorPeriodLines.isEmpty {
                    let varianceLines = VarianceAnalysis.compute(current: currentLines, prior: priorPeriodLines)
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        ForEach(varianceLines) { vline in
                            HStack {
                                Text(vline.label)
                                    .font(vline.isSummary ? VLTypography.cardTitle() : VLTypography.body())
                                    .foregroundStyle(vline.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                                    .padding(.leading, CGFloat(vline.depth) * 16)
                                Spacer()
                                Text(vline.priorAmount?.description ?? "—")
                                    .font(VLTypography.tabularNumeric())
                                    .foregroundStyle(VLColor.textMuted)
                                    .frame(minWidth: 90, alignment: .trailing)
                                if let change = vline.change {
                                    Text("\(change.minorUnits >= 0 ? "+" : "")\(change.description)")
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(change.minorUnits >= 0 ? VLColor.textPrimary : .red)
                                        .frame(minWidth: 90, alignment: .trailing)
                                } else {
                                    Text("—").font(VLTypography.tabularNumeric()).foregroundStyle(VLColor.textMuted).frame(minWidth: 90, alignment: .trailing)
                                }
                                if let percent = vline.percentChange {
                                    Text("\(percent >= 0 ? "+" : "")\(String(format: "%.1f", percent * 100))%")
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(percent >= 0 ? VLColor.textPrimary : .red)
                                        .frame(minWidth: 60, alignment: .trailing)
                                } else {
                                    Text("—").font(VLTypography.tabularNumeric()).foregroundStyle(VLColor.textMuted).frame(minWidth: 60, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
