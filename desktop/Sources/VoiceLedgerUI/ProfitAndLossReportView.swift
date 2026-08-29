import SwiftUI
import Core
import DesignSystem

/// The Profit & Loss screen — KPI cards, a revenue-to-net-income waterfall,
/// and a top-expense-drivers chart ABOVE the same full detailed line-item
/// table `FinancialReportView` already renders (reused via
/// `ReportLinesTable`, not reimplemented) — see `BalanceSheetReportView`'s
/// doc comment for the "charts are added, never a replacement" decision
/// this mirrors.
public struct ProfitAndLossReportView: View {
    private let sourceDescription: String
    private let environment: VLEnvironmentTone
    private let lines: [ReportLine]
    private let isLoading: Bool
    private let errorMessage: String?
    private let onRefresh: () -> Void
    private let onExport: (ReportExportFormat) -> Void
    private let priorPeriodLines: [ReportLine]?
    private let priorPeriodLabel: String?
    private let isLoadingVariance: Bool
    private let varianceError: String?
    private let onLoadVariance: (() -> Void)?

    public init(
        sourceDescription: String,
        environment: VLEnvironmentTone,
        lines: [ReportLine],
        isLoading: Bool,
        errorMessage: String?,
        onRefresh: @escaping () -> Void,
        onExport: @escaping (ReportExportFormat) -> Void = { _ in },
        priorPeriodLines: [ReportLine]? = nil,
        priorPeriodLabel: String? = nil,
        isLoadingVariance: Bool = false,
        varianceError: String? = nil,
        onLoadVariance: (() -> Void)? = nil
    ) {
        self.sourceDescription = sourceDescription
        self.environment = environment
        self.lines = lines
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
        self.onExport = onExport
        self.priorPeriodLines = priorPeriodLines
        self.priorPeriodLabel = priorPeriodLabel
        self.isLoadingVariance = isLoadingVariance
        self.varianceError = varianceError
        self.onLoadVariance = onLoadVariance
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Profit & Loss")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    if !lines.isEmpty {
                        ExportMenuButton(onExport: onExport)
                    }
                    VLEnvironmentBadge(environment)
                }

                HStack {
                    Text(sourceDescription)
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    Button(isLoading ? "Loading…" : "Refresh") { onRefresh() }
                        .disabled(isLoading)
                }

                if let errorMessage {
                    VLCard(accentRail: VLColor.violet) {
                        Text(errorMessage)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textSecondary)
                    }
                }

                if lines.isEmpty && !isLoading && errorMessage == nil {
                    VLCard {
                        Text("No report loaded yet. Tap Refresh.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    KPICardRow(cards: kpiCards)
                    if let segments = ProfitAndLossWaterfall.segments(from: lines) {
                        ProfitAndLossWaterfallChart(segments: segments)
                    }
                    ExpenseDriverBarChart(drivers: TopExpenseDrivers.top(5, from: lines))
                    ReportLinesTable(lines: lines)
                }

                if let onLoadVariance {
                    ReportVarianceSection(
                        currentLines: lines,
                        priorPeriodLines: priorPeriodLines,
                        priorPeriodLabel: priorPeriodLabel,
                        isLoadingVariance: isLoadingVariance,
                        varianceError: varianceError,
                        onLoadVariance: onLoadVariance
                    )
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var kpiCards: [KPICardRow.CardData] {
        [
            kpiCard(label: "Gross Margin", percent: FinancialKPIs.grossMarginPercent(from: lines)),
            kpiCard(label: "Net Margin", percent: FinancialKPIs.netMarginPercent(from: lines)),
            KPICardRow.CardData(
                label: "Net Income",
                value: TaxEstimate.netIncome(from: lines)?.description ?? "Not available",
                isAvailable: TaxEstimate.netIncome(from: lines) != nil
            )
        ]
    }

    private func kpiCard(label: String, percent: Double?) -> KPICardRow.CardData {
        guard let percent else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: String(format: "%.1f%%", percent))
    }
}
