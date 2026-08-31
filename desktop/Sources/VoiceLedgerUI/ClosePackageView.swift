import SwiftUI
import Core
import DesignSystem

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit section names the Close Package
/// as: "reports, variance, warnings, completed checklist, corrections made,
/// carry-forward items, client Q&A, Ask Claude history, and who closed it
/// when." **This is a real slice of that, not the whole thing** — same
/// honesty convention as the Baseline Evidence Pack (`CLAUDE.md`
/// terminology: evidence of a starting state, not a restorable backup).
/// Built here: checklist completion status, Cleanup Assessment finding
/// counts, Balance Sheet + Profit & Loss + Cash Flow + Trial Balance summary
/// lines, Aged Receivables/Payables totals, and recent activity log entries
/// — everything the app already has computed from real synced data.
/// Corrected 2026-08-24: this doc comment previously said cash flow/trial
/// balance/aging reports weren't built anywhere in the app — they are now
/// (each has its own dedicated report page, reachable from the toolbar);
/// they just weren't summarized HERE yet, which this pass closes. General
/// Ledger is deliberately still excluded — it's transaction-level detail,
/// not summary lines, and doesn't fit this page's "one line per section"
/// shape. Variance analysis now lives on the Balance Sheet/P&L report pages
/// themselves (`FinancialReportView`'s "Compare to prior period"), not
/// duplicated here. Carry-forward items are now built (`CarryForwardMark`,
/// marked from `FindingDetailView`) — this section only renders when at
/// least one exists. Corrections made is now built too — a filtered view
/// of the Activity Log (`ActivityKind.isCorrection`), not a separately
/// tracked ledger with its own storage; the Activity Log is already the
/// append-only record of everything, so this is a view distinction, not a
/// new data model. **Still not built**: client Q&A and Ask Claude history
/// (no Claude integration exists yet at all — this app uses OpenAI, see
/// `AskAIContext`'s doc comment). Exportable two ways: the Export menu's
/// plain CSV/XLSX/PDF (a flat table of this same data), and "Export
/// Branded PDF" (`ClosePackagePDFExporter`, added 2026-08-28) — a real
/// designed document with a cover page and titled sections, the "branded
/// client PDF" `PDFReportExporter`'s own doc comment originally deferred.
public struct ClosePackageView: View {
    public struct ChecklistStatus {
        public let completed: Int
        public let total: Int
        public init(completed: Int, total: Int) {
            self.completed = completed
            self.total = total
        }
    }

    private let environment: VLEnvironmentTone
    private let period: AccountingPeriod
    private let checklistStatus: ChecklistStatus
    private let openCleanupFindingsCount: Int
    private let resolvedCleanupFindingsCount: Int
    private let balanceSheetLines: [ReportLine]
    private let profitAndLossLines: [ReportLine]
    private let cashFlowLines: [ReportLine]
    private let trialBalanceLines: [TrialBalanceLine]
    private let agedReceivablesLines: [AgingLine]
    private let agedPayablesLines: [AgingLine]
    private let recentActivity: [ActivityLogEntry]
    /// `(mark, finding title, finding dollarExposure)` — the view has no
    /// way to look up a `Finding` by id itself, so the app layer resolves
    /// each mark's finding before passing it down, same as every other
    /// summary on this page being pre-computed by the caller.
    private let carryForwardItems: [(mark: CarryForwardMark, findingTitle: String, dollarExposure: Money)]
    private let onExport: (ReportExportFormat) -> Void
    /// The designed, multi-section cover-page-plus-sections PDF
    /// (`ClosePackagePDFExporter`) — distinct from `onExport`'s generic
    /// flat-table CSV/XLSX/PDF, which every other report page also shares.
    /// A separate button rather than a fourth `ReportExportFormat` case:
    /// that enum is shared by every export menu in the app, and no other
    /// page has a "branded" mode to offer.
    /// Owner directive (2026-08-31): now takes whatever executive-summary
    /// draft text the bookkeeper has generated/edited on this page (`nil`
    /// if they never generated one) — the exporter itself never calls AI,
    /// this is the one place that draft becomes part of the exported file.
    private let onExportBrandedPDF: (String?) -> Void
    /// Owner directive (2026-08-30): "a lot of the sections say unsynced
    /// yet there is no refresh button for them to sync" — see `SyncButton`.
    private let isSyncing: Bool
    private let onSync: () -> Void
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
    /// Owner directive (2026-08-31): "a narrated summary in the Close
    /// Package PDF" — separate answer/error/in-flight state from the Q&A
    /// panel above, same reasoning as every other dedicated-purpose Ask AI
    /// call in this app: a different `contextKey`, must never collide with
    /// the general Q&A panel's own answer.
    private let executiveSummaryAnswer: String?
    private let isGeneratingExecutiveSummary: Bool
    private let executiveSummaryError: String?
    private let onGenerateExecutiveSummary: () -> Void
    private let executiveSummarySecondOpinionAnswer: String?
    private let isGeneratingExecutiveSummarySecondOpinion: Bool
    private let executiveSummarySecondOpinionError: String?
    private let onGenerateExecutiveSummarySecondOpinion: () -> Void

    @State private var executiveSummaryDraft: String = ""

    public init(
        environment: VLEnvironmentTone,
        period: AccountingPeriod,
        checklistStatus: ChecklistStatus,
        openCleanupFindingsCount: Int,
        resolvedCleanupFindingsCount: Int,
        balanceSheetLines: [ReportLine],
        profitAndLossLines: [ReportLine],
        cashFlowLines: [ReportLine] = [],
        trialBalanceLines: [TrialBalanceLine] = [],
        agedReceivablesLines: [AgingLine] = [],
        agedPayablesLines: [AgingLine] = [],
        recentActivity: [ActivityLogEntry],
        carryForwardItems: [(mark: CarryForwardMark, findingTitle: String, dollarExposure: Money)] = [],
        onExport: @escaping (ReportExportFormat) -> Void = { _ in },
        onExportBrandedPDF: @escaping (String?) -> Void = { _ in },
        isSyncing: Bool = false,
        onSync: @escaping () -> Void = {},
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
        executiveSummaryAnswer: String? = nil,
        isGeneratingExecutiveSummary: Bool = false,
        executiveSummaryError: String? = nil,
        onGenerateExecutiveSummary: @escaping () -> Void = {},
        executiveSummarySecondOpinionAnswer: String? = nil,
        isGeneratingExecutiveSummarySecondOpinion: Bool = false,
        executiveSummarySecondOpinionError: String? = nil,
        onGenerateExecutiveSummarySecondOpinion: @escaping () -> Void = {}
    ) {
        self.environment = environment
        self.period = period
        self.checklistStatus = checklistStatus
        self.openCleanupFindingsCount = openCleanupFindingsCount
        self.resolvedCleanupFindingsCount = resolvedCleanupFindingsCount
        self.balanceSheetLines = balanceSheetLines
        self.profitAndLossLines = profitAndLossLines
        self.cashFlowLines = cashFlowLines
        self.trialBalanceLines = trialBalanceLines
        self.agedReceivablesLines = agedReceivablesLines
        self.agedPayablesLines = agedPayablesLines
        self.recentActivity = recentActivity
        self.carryForwardItems = carryForwardItems
        self.onExport = onExport
        self.onExportBrandedPDF = onExportBrandedPDF
        self.isSyncing = isSyncing
        self.onSync = onSync
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
        self.executiveSummaryAnswer = executiveSummaryAnswer
        self.isGeneratingExecutiveSummary = isGeneratingExecutiveSummary
        self.executiveSummaryError = executiveSummaryError
        self.onGenerateExecutiveSummary = onGenerateExecutiveSummary
        self.executiveSummarySecondOpinionAnswer = executiveSummarySecondOpinionAnswer
        self.isGeneratingExecutiveSummarySecondOpinion = isGeneratingExecutiveSummarySecondOpinion
        self.executiveSummarySecondOpinionError = executiveSummarySecondOpinionError
        self.onGenerateExecutiveSummarySecondOpinion = onGenerateExecutiveSummarySecondOpinion
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Close Package")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    Button("Export Branded PDF") {
                        let trimmed = executiveSummaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        onExportBrandedPDF(trimmed.isEmpty ? nil : executiveSummaryDraft)
                    }
                    .buttonStyle(.bordered)
                    ExportMenuButton(onExport: onExport)
                    VLEnvironmentBadge(environment)
                }

                Text("\(period.year)-\(String(format: "%02d", period.month)) · A consolidated summary of this period's close, assembled from what's already been synced and recorded. \"Export Branded PDF\" produces a designed cover-page-plus-sections document; the Export menu's plain CSV/XLSX/PDF is the same raw data as a flat table. Not the full spec'd Close Package (no client Q&A or Ask Claude history yet).")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                executiveSummarySection
                checklistSection
                cleanupSection

                if !balanceSheetLines.isEmpty {
                    reportSummarySection(title: "Balance Sheet (summary lines)", lines: balanceSheetLines)
                }
                if !profitAndLossLines.isEmpty {
                    reportSummarySection(title: "Profit & Loss (summary lines)", lines: profitAndLossLines)
                }
                if !cashFlowLines.isEmpty {
                    reportSummarySection(title: "Cash Flow (summary lines)", lines: cashFlowLines)
                }
                if !trialBalanceLines.isEmpty {
                    trialBalanceSummarySection
                }
                if !agedReceivablesLines.isEmpty {
                    agingSummarySection(title: "Aged Receivables (total)", lines: agedReceivablesLines)
                }
                if !agedPayablesLines.isEmpty {
                    agingSummarySection(title: "Aged Payables (total)", lines: agedPayablesLines)
                }

                correctionsSection
                if !carryForwardItems.isEmpty {
                    carryForwardSection
                }

                activitySection

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this close package",
                    primaryDisclaimer: "Answers are grounded strictly in the reports and activity listed on this page — it cannot state a dollar figure, severity, or judgment beyond what's already shown, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's report summaries and activity to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already on this screen, and never gives tax or legal advice.",
                    secondOpinionAnswer: secondOpinionAnswer,
                    isAskingSecondOpinion: isAskingSecondOpinion,
                    secondOpinionError: secondOpinionError,
                    onAskSecondOpinion: onAskSecondOpinion
                )
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
        // Seeds the editable draft whenever a NEW generation actually
        // completes — `onChange` only fires on a real value change, so
        // this never clobbers text the bookkeeper is mid-edit on.
        .onChange(of: executiveSummaryAnswer) { _, newValue in
            if let newValue { executiveSummaryDraft = newValue }
        }
        .onChange(of: executiveSummarySecondOpinionAnswer) { _, newValue in
            if let newValue { executiveSummaryDraft = newValue }
        }
    }

    /// Owner directive (2026-08-31): "a narrated summary in the Close
    /// Package PDF." The exporter itself (`ClosePackagePDFExporter`) never
    /// calls AI or computes anything about this text — it only lays out
    /// whatever string is in `executiveSummaryDraft` at export time. Always
    /// editable before export (same "review before it's real" posture as
    /// `clientQuestionSection` on `FindingDetailView`), never baked in
    /// straight from the raw AI answer.
    private var executiveSummarySection: some View {
        VLCard(accentRail: VLColor.violet) {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("EXECUTIVE SUMMARY — FOR EXPORTED PDF")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text("Optional. AI-drafted from the report summaries and activity below, grounded strictly in what's already on this page — edit freely below. Left blank, \"Export Branded PDF\" omits this section entirely rather than including an empty one.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)

                HStack(spacing: VLSpacing.sm) {
                    Button(isGeneratingExecutiveSummary ? "Generating…" : "Generate (Gemma)") { onGenerateExecutiveSummary() }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingExecutiveSummary)
                    if secondOpinionConfigured {
                        Button(isGeneratingExecutiveSummarySecondOpinion ? "Generating…" : "Generate (OpenAI)") { onGenerateExecutiveSummarySecondOpinion() }
                            .buttonStyle(.bordered)
                            .disabled(isGeneratingExecutiveSummarySecondOpinion)
                    }
                }

                if let executiveSummaryError {
                    Text(executiveSummaryError).font(VLTypography.caption()).foregroundStyle(.red)
                }
                if let executiveSummarySecondOpinionError {
                    Text(executiveSummarySecondOpinionError).font(VLTypography.caption()).foregroundStyle(.red)
                }

                if !executiveSummaryDraft.isEmpty {
                    TextEditor(text: $executiveSummaryDraft)
                        .font(VLTypography.body())
                        .frame(minHeight: 120)
                        .padding(VLSpacing.xs)
                        .background(VLColor.background)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(VLColor.border))
                }
            }
        }
    }

    private var checklistSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("MONTH-END CHECKLIST")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                HStack {
                    Text("\(checklistStatus.completed) of \(checklistStatus.total) items complete")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLStatusPill(
                        checklistStatus.completed == checklistStatus.total ? .verified : .informational,
                        label: checklistStatus.completed == checklistStatus.total ? "Ready to close" : "Not ready"
                    )
                }
            }
        }
    }

    private var cleanupSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("CLEANUP ASSESSMENT FINDINGS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                HStack {
                    Text("\(openCleanupFindingsCount) open")
                        .font(VLTypography.body())
                        .foregroundStyle(openCleanupFindingsCount == 0 ? VLColor.textPrimary : VLColor.textPrimary)
                    Text("·")
                        .foregroundStyle(VLColor.textMuted)
                    Text("\(resolvedCleanupFindingsCount) resolved")
                        .font(VLTypography.body())
                        .foregroundStyle(VLColor.textSecondary)
                    Spacer()
                }
            }
        }
    }

    private func reportSummarySection(title: String, lines: [ReportLine]) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text(title.uppercased())
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                ForEach(lines.filter(\.isSummary)) { line in
                    HStack {
                        Text(line.label)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                        Spacer()
                        Text(line.amount?.description ?? "-")
                            .font(VLTypography.tabularNumericEmphasis())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                }
            }
        }
    }

    private var trialBalanceSummarySection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("TRIAL BALANCE (SUMMARY LINE)")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                if let summaryLine = trialBalanceLines.last(where: \.isSummary) {
                    HStack {
                        Text(summaryLine.label)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                        Spacer()
                        Text("Debit \(summaryLine.debit?.description ?? "-")  ·  Credit \(summaryLine.credit?.description ?? "-")")
                            .font(VLTypography.tabularNumericEmphasis())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                }
            }
        }
    }

    /// Only the grand-total summary row, not every customer/vendor line —
    /// this page is a one-line-per-section overview, matching
    /// `reportSummarySection`'s shape for `ReportLine`.
    private func agingSummarySection(title: String, lines: [AgingLine]) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text(title.uppercased())
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                if let summaryLine = lines.last(where: { $0.isSummary }) {
                    HStack {
                        Text(summaryLine.label)
                            .font(VLTypography.body())
                            .foregroundStyle(VLColor.textPrimary)
                        Spacer()
                        Text(summaryLine.total?.description ?? "-")
                            .font(VLTypography.tabularNumericEmphasis())
                            .foregroundStyle(VLColor.textPrimary)
                    }
                }
            }
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package section:
    /// "corrections made" — distinct from the full Activity Log (which also
    /// records detections, dismissals, and other non-correction events).
    /// `ActivityKind.isCorrection` is the single source of truth for what
    /// counts; this section just filters and renders it.
    private var correctionsSection: some View {
        let corrections = recentActivity.filter { $0.kind.isCorrection }
        return VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("CORRECTIONS MADE")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                if corrections.isEmpty {
                    Text("No corrections recorded yet this period.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(corrections.prefix(20), id: \.id) { entry in
                        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                            HStack {
                                Text(entry.kind.humanLabel)
                                    .font(VLTypography.body())
                                    .foregroundStyle(VLColor.textPrimary)
                                Spacer()
                                Text(entry.recordedAt, style: .date)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            }
                            if let summary = entry.findingSummary {
                                Text(summary)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textSecondary)
                            }
                            Text(entry.actor.displayLabel)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                    }
                }
            }
        }
    }

    private var carryForwardSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("CARRY-FORWARD ITEMS")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                ForEach(carryForwardItems, id: \.mark.id) { item in
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        HStack {
                            Text(item.findingTitle)
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textPrimary)
                            Spacer()
                            Text(item.dollarExposure.description)
                                .font(VLTypography.tabularNumeric())
                                .foregroundStyle(VLColor.textPrimary)
                        }
                        Text("Marked by \(item.mark.markedBy)\(item.mark.reason.map { " — \($0)" } ?? "")")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                Text("RECENT ACTIVITY")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                if recentActivity.isEmpty {
                    Text("No activity recorded yet.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(recentActivity.prefix(10), id: \.id) { entry in
                        VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                            HStack {
                                Text(entry.kind.humanLabel)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textPrimary)
                                Spacer()
                                Text(entry.recordedAt, style: .date)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                            }
                            if let summary = entry.findingSummary {
                                Text(summary)
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textSecondary)
                            }
                            Text(entry.actor.displayLabel)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                    }
                }
            }
        }
    }
}
