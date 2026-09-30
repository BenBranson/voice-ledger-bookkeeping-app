import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 12 (Type A), minimal slice: a flattened
/// view of any single QBO financial-statement report (Balance Sheet,
/// Profit & Loss — both verified live to share the same recursive section
/// shape). See `ReportLine`'s doc comment — real QBO section nesting
/// collapsed to an indent depth, not a fully faithful nested UI.
/// **Report responses need normalization and won't be pixel-identical to
/// QBO's rendered reports** (CLAUDE.md) — this shows real numbers straight
/// from the API, not a branded client-ready document (that's the Close
/// Package, not built).
public struct FinancialReportView: View {
    private let title: String
    private let sourceDescription: String
    private let environment: VLEnvironmentTone
    private let lines: [ReportLine]
    private let isLoading: Bool
    private let errorMessage: String?
    private let onRefresh: () -> Void
    private let onExport: (ReportExportFormat) -> Void
    /// Variance analysis (docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close
    /// Package section) — optional so this view's other 6 call sites (Cash
    /// Flow, and every report before this was added) need no changes.
    /// `nil` prior lines and `false` loading/no error is the same as never
    /// having asked for a comparison at all.
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
        title: String,
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
        alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = []
    ) {
        self.title = title
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
                    Text(title)
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
                    DataStateNotice(.notLoaded(what: "the \(title)", onLoad: onRefresh), isLoading: isLoading)
                } else {
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
                    primaryDisclaimer: "Answers are grounded in the report lines on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this report's line items, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
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
}
