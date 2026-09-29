import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 12 (Type A). Deliberately a separate view
/// from `FinancialReportView` — see `TrialBalanceLine`'s doc comment for
/// why Trial Balance's debit/credit-column shape isn't the same as Balance
/// Sheet/P&L/Cash Flow's single-amount section tree. This report is flat
/// (verified live: no section nesting in a real trial balance), so there's
/// no depth-based indentation here.
public struct TrialBalanceReportView: View {
    private let sourceDescription: String
    private let environment: VLEnvironmentTone
    private let lines: [TrialBalanceLine]
    private let isLoading: Bool
    private let errorMessage: String?
    private let onRefresh: () -> Void
    private let onExport: (ReportExportFormat) -> Void
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
        lines: [TrialBalanceLine],
        isLoading: Bool,
        errorMessage: String?,
        onRefresh: @escaping () -> Void,
        onExport: @escaping (ReportExportFormat) -> Void = { _ in },
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
        self.sourceDescription = sourceDescription
        self.environment = environment
        self.lines = lines
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.onRefresh = onRefresh
        self.onExport = onExport
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
                    Text("Trial Balance")
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
                    VLCard {
                        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                            HStack {
                                Text("Account").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                                Spacer()
                                Text("Debit").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).frame(width: 120, alignment: .trailing)
                                Text("Credit").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).frame(width: 120, alignment: .trailing)
                            }
                            ForEach(lines) { line in
                                HStack {
                                    Text(line.label)
                                        .font(line.isSummary ? VLTypography.cardTitle() : VLTypography.body())
                                        .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                                    Spacer()
                                    Text(line.debit?.accountingDescription ?? "")
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                                        .frame(width: 120, alignment: .trailing)
                                    Text(line.credit?.accountingDescription ?? "")
                                        .font(VLTypography.tabularNumeric())
                                        .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                                        .frame(width: 120, alignment: .trailing)
                                }
                            }
                        }
                    }
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this report",
                    primaryDisclaimer: "Answers are grounded in the Trial Balance lines on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this Trial Balance's line items, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
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
