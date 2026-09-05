import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 12. Shared by Aged Receivables and Aged
/// Payables — verified live to share the exact same 6-money-column shape
/// (Current/1-30/31-60/61-90/91-and-over/Total), keyed by Customer or
/// Vendor respectively. See `AgingLine`'s doc comment for the mixed
/// leaf-row shape this had to be decoded around.
public struct AgingReportView: View {
    private let title: String
    private let rowLabel: String
    private let sourceDescription: String
    private let environment: VLEnvironmentTone
    private let lines: [AgingLine]
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

    public init(
        title: String,
        rowLabel: String,
        sourceDescription: String,
        environment: VLEnvironmentTone,
        lines: [AgingLine],
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
        onAskSecondOpinion: @escaping (String) -> Void = { _ in }
    ) {
        self.title = title
        self.rowLabel = rowLabel
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
    }

    private static let columnWidth: CGFloat = 90

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
                    VLCard {
                        Text("No report loaded yet. Tap Refresh.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    VLCard {
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                HStack {
                                    Text(rowLabel).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).frame(width: 200, alignment: .leading)
                                    ForEach(["Current", "1-30", "31-60", "61-90", "91+", "Total"], id: \.self) { header in
                                        Text(header).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).frame(width: Self.columnWidth, alignment: .trailing)
                                    }
                                }
                                ForEach(lines) { line in
                                    HStack {
                                        Text(line.label)
                                            .font(line.isSummary ? VLTypography.cardTitle() : VLTypography.body())
                                            .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                                            .padding(.leading, CGFloat(line.depth) * 16)
                                            .frame(width: 200, alignment: .leading)
                                        let amounts = [line.current, line.days1to30, line.days31to60, line.days61to90, line.days91AndOver, line.total]
                                        ForEach(amounts.indices, id: \.self) { index in
                                            Text(amounts[index]?.description ?? "")
                                                .font(VLTypography.tabularNumeric())
                                                .foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary)
                                                .frame(width: Self.columnWidth, alignment: .trailing)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this report",
                    primaryDisclaimer: "Answers are grounded in the \(title) lines on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this \(title) report's line items, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
                    secondOpinionAnswer: secondOpinionAnswer,
                    isAskingSecondOpinion: isAskingSecondOpinion,
                    secondOpinionError: secondOpinionError,
                    onAskSecondOpinion: onAskSecondOpinion
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
