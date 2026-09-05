import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md Page 12. See `GeneralLedgerLine`'s doc
/// comment — a real transaction-level ledger grouped by account, not a
/// label+amount tree, so this renders a wide scrollable table rather than
/// reusing `FinancialReportView`'s section-indent layout.
public struct GeneralLedgerReportView: View {
    private let sourceDescription: String
    private let environment: VLEnvironmentTone
    private let lines: [GeneralLedgerLine]
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
    private let alternateModelTier: TwoTierAskAIPanel.AlternateModelTier?

    /// Owner directive (2026-08-31): "a quick-click filter component
    /// inside the General Ledger... views" — purely local to this view
    /// (every line is already in `lines`, nothing to fetch), see
    /// `AmountSearch` (Core) for the exact-cents matching itself.
    @State private var amountFilter = ""

    public init(
        sourceDescription: String,
        environment: VLEnvironmentTone,
        lines: [GeneralLedgerLine],
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
        alternateModelTier: TwoTierAskAIPanel.AlternateModelTier? = nil
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
        self.alternateModelTier = alternateModelTier
    }

    private var parsedAmountFilter: Money? {
        AmountSearch.parseAmount(amountFilter)
    }

    /// Drops account-header rows while a filter is active — a flat list
    /// of just the matching leaf rows is more useful for "pinpoint a
    /// duplicate" than headers for accounts that have no match at all.
    private var filteredLines: [GeneralLedgerLine] {
        guard let parsedAmountFilter else { return lines }
        return lines.filter { line in
            !line.isAccountHeader && [line.amount, line.balance].contains { $0 != nil && abs($0!.minorUnits) == abs(parsedAmountFilter.minorUnits) && $0!.currency == parsedAmountFilter.currency }
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("General Ledger")
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
                    HStack {
                        TextField("Filter by amount (e.g. 142.50)", text: $amountFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 240)
                        if !amountFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                            if parsedAmountFilter == nil {
                                Text("Not a recognizable amount").font(VLTypography.caption()).foregroundStyle(.red)
                            } else {
                                Text("\(filteredLines.count) matching line\(filteredLines.count == 1 ? "" : "s")").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                            }
                            Button("Clear") { amountFilter = "" }.buttonStyle(.plain).font(VLTypography.caption()).foregroundStyle(VLColor.cyan)
                        }
                    }

                    VLCard {
                        ScrollView(.horizontal) {
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                HStack {
                                    ForEach(["Date", "Type", "Num", "Name", "Memo", "Split", "Amount", "Balance"], id: \.self) { header in
                                        Text(header).font(VLTypography.caption()).foregroundStyle(VLColor.textMuted).frame(width: 110, alignment: .leading)
                                    }
                                }
                                ForEach(filteredLines) { line in
                                    if line.isAccountHeader {
                                        Text(line.label)
                                            .font(VLTypography.cardTitle())
                                            .foregroundStyle(VLColor.textPrimary)
                                            .padding(.top, VLSpacing.xs)
                                    } else {
                                        HStack {
                                            Text(line.label).font(VLTypography.tabularNumeric()).foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.transactionType ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.docNumber ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.name ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.memo ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.split ?? "").font(VLTypography.body()).foregroundStyle(VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.amount?.description ?? "").font(VLTypography.tabularNumeric()).foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary).frame(width: 110, alignment: .leading)
                                            Text(line.balance?.description ?? "").font(VLTypography.tabularNumeric()).foregroundStyle(line.isSummary ? VLColor.textPrimary : VLColor.textSecondary).frame(width: 110, alignment: .leading)
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
                    primaryDisclaimer: "Answers are grounded in the General Ledger lines on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this General Ledger's line items, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
                    secondOpinionAnswer: secondOpinionAnswer,
                    isAskingSecondOpinion: isAskingSecondOpinion,
                    secondOpinionError: secondOpinionError,
                    onAskSecondOpinion: onAskSecondOpinion,
                    alternateModelTier: alternateModelTier
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }
}
