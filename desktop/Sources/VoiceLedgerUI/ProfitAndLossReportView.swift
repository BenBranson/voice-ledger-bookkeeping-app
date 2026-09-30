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
    private let accountTypes: [String: LedgerAccountType]
    private let chartActions: ChartAccountActions
    private let trend: TrendData?
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
    /// Owner directive (2026-08-30): every page ends in a two-tier Ask AI
    /// panel — see `TwoTierAskAIPanel`.
    private let aiStatus: AIStatus?
    private let askAIAnswer: String?
    private let isAskingAI: Bool
    private let askAIError: String?
    private let onAskAI: (String) -> Void
    private let secondOpinionConfigured: Bool
    private let secondOpinionAnswer: String?
    private let isAskingSecondOpinion: Bool
    private let secondOpinionError: String?
    private let onAskSecondOpinion: (String) -> Void
    private let alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier]

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
        onLoadVariance: (() -> Void)? = nil,
        aiStatus: AIStatus? = nil,
        askAIAnswer: String? = nil,
        isAskingAI: Bool = false,
        askAIError: String? = nil,
        onAskAI: @escaping (String) -> Void = { _ in },
        secondOpinionConfigured: Bool = false,
        secondOpinionAnswer: String? = nil,
        isAskingSecondOpinion: Bool = false,
        secondOpinionError: String? = nil,
        onAskSecondOpinion: @escaping (String) -> Void = { _ in },
        alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = [],
        accountTypes: [String: LedgerAccountType] = [:],
        chartActions: ChartAccountActions = .none,
        trend: TrendData? = nil
    ) {
        self.accountTypes = accountTypes
        self.chartActions = chartActions
        self.trend = trend
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
        self.aiStatus = aiStatus
        self.askAIAnswer = askAIAnswer
        self.isAskingAI = isAskingAI
        self.askAIError = askAIError
        self.onAskAI = onAskAI
        self.secondOpinionConfigured = secondOpinionConfigured
        self.secondOpinionAnswer = secondOpinionAnswer
        self.isAskingSecondOpinion = isAskingSecondOpinion
        self.secondOpinionError = secondOpinionError
        self.onAskSecondOpinion = onAskSecondOpinion
        self.alternateModelTiers = alternateModelTiers
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
                    DataStateNotice(.notLoaded(what: "the Profit & Loss", onLoad: onRefresh), isLoading: isLoading)
                } else {
                    KPICardRow(cards: kpiCards)
                    WaterfallCard(data: ChartData.waterfall(from: lines))
                    MoneyFlowCard(data: ChartData.moneyFlow(from: lines, hubLabel: "This period", topExpenses: 8), actions: chartActions)
                    ExpenseCategoriesCard(data: ChartData.expenseCategories(from: lines, top: 8), actions: chartActions)
                    ExpenseTreemapCard(data: ChartData.expenseTree(from: lines), actions: chartActions)
                    if let trend { TrendCard(data: trend) }
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

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this report",
                    primaryDisclaimer: "Answers are grounded in the Profit & Loss lines on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this Profit & Loss's line items, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
                    secondOpinionAnswer: secondOpinionAnswer,
                    isAskingSecondOpinion: isAskingSecondOpinion,
                    secondOpinionError: secondOpinionError,
                    onAskSecondOpinion: onAskSecondOpinion,
                    alternateModelTiers: alternateModelTiers
                )
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
                value: TaxEstimate.netIncome(from: lines)?.accountingDescription ?? "Not available",
                isAvailable: TaxEstimate.netIncome(from: lines) != nil
            )
        ]
    }

    private func kpiCard(label: String, percent: Double?) -> KPICardRow.CardData {
        guard let percent else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: String(format: "%.1f%%", percent))
    }
}
