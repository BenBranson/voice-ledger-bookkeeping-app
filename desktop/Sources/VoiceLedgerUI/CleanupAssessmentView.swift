import SwiftUI
import Core
import DesignSystem

/// docs/backlog/CLEANUP_MODE.md §1: "connect the client's QBO (read-only),
/// run every deterministic rule across the full available history, and
/// produce a one-page assessment." This is the minimal read-only version —
/// counts and dollar exposure by rule, from real findings. **Deliberately
/// does NOT show an hours estimate or price band.** CLEANUP_MODE.md's own
/// text says those should be driven by "account-months unreconciled and
/// uncategorized transaction count" — neither exists yet (no reconciliation
/// gap map, no VL-CAT-UNCAT-001). Inventing a formula from the two rules
/// that do exist would be exactly the kind of unearned precision `CLAUDE.md`
/// rule 6 exists to prevent — an honest "not yet available" beats a number
/// nobody should trust.
public struct CleanupAssessmentView: View {
    public struct RuleSummary: Identifiable {
        public let ruleID: String
        public let title: String
        public let findings: [Finding]
        public var id: String { ruleID }

        public init(ruleID: String, title: String, findings: [Finding]) {
            self.ruleID = ruleID
            self.title = title
            self.findings = findings
        }
    }

    private let environment: VLEnvironmentTone
    private let coverageStatus: VLStatus
    private let coverageDetail: String
    private let summaries: [RuleSummary]
    private let onSelectFinding: (Finding) -> Void
    private let onExport: (ReportExportFormat) -> Void
    /// Owner directive (2026-08-30): "a lot of the sections say unsynced
    /// yet there is no refresh button for them to sync" — see `SyncButton`.
    private let isSyncing: Bool
    private let onSync: () -> Void
    /// docs/VOICE_LEDGER_SPEC.md's Ask [AI] panel, page-level form — asks
    /// about the whole assessment (every open finding across every rule
    /// here), not one finding. See `AskAIPanelView`/`AskAIContext.compose(pageTitle:findings:)`.
    private let aiStatus: AIStatus?
    private let askAIAnswer: String?
    private let isAskingAI: Bool
    private let askAIError: String?
    private let onAskAI: (String) -> Void
    /// Owner directive (2026-08-30): every page's Ask AI panel should offer
    /// both the free/local tier and an opt-in OpenAI second opinion, not
    /// just the free one — see `TwoTierAskAIPanel`.
    private let secondOpinionConfigured: Bool
    private let secondOpinionAnswer: String?
    private let isAskingSecondOpinion: Bool
    private let secondOpinionError: String?
    private let onAskSecondOpinion: (String) -> Void
    private let alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier]

    /// Owner directive (2026-08-31): "a quick-click filter component
    /// inside... Cleanup Assessment" — purely local, filtering the
    /// findings already in `summaries` by exact dollar exposure.
    @State private var amountFilter = ""

    public init(
        environment: VLEnvironmentTone,
        coverageStatus: VLStatus,
        coverageDetail: String,
        summaries: [RuleSummary],
        onSelectFinding: @escaping (Finding) -> Void,
        onExport: @escaping (ReportExportFormat) -> Void = { _ in },
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
        alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = []
    ) {
        self.environment = environment
        self.coverageStatus = coverageStatus
        self.coverageDetail = coverageDetail
        self.summaries = summaries
        self.onSelectFinding = onSelectFinding
        self.onExport = onExport
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
        self.alternateModelTiers = alternateModelTiers
    }

    private var totalFindingCount: Int { summaries.reduce(0) { $0 + $1.findings.count } }
    private var totalExposure: Money? {
        let all = summaries.flatMap(\.findings)
        guard let first = all.first else { return nil }
        return all.dropFirst().reduce(first.dollarExposure) { $0 + $1.dollarExposure }
    }

    private var parsedAmountFilter: Money? {
        AmountSearch.parseAmount(amountFilter)
    }

    /// Each `RuleSummary`'s `findings` narrowed to exact-dollar-exposure
    /// matches when a filter is active; a summary with zero matches is
    /// dropped entirely rather than shown as a misleading empty section.
    private var filteredSummaries: [RuleSummary] {
        guard let parsedAmountFilter else { return summaries }
        return summaries.compactMap { summary in
            let matches = summary.findings.filter {
                $0.dollarExposure.currency == parsedAmountFilter.currency && abs($0.dollarExposure.minorUnits) == abs(parsedAmountFilter.minorUnits)
            }
            guard !matches.isEmpty else { return nil }
            return RuleSummary(ruleID: summary.ruleID, title: summary.title, findings: matches)
        }
    }

    /// Owner directive (2026-08-30), via Gemma's own suggestion on this
    /// page: "rank findings by ease of fix vs. dollar impact... quick wins
    /// first." Capped at 8 so this reads as "start here," not a second copy
    /// of the full list below.
    private var quickWins: [Finding] {
        Array(QuickWinTriage.sorted(filteredSummaries.flatMap(\.findings)).prefix(8))
    }

    /// Owner directive (2026-08-30): "group the findings into logical
    /// categories... to make the scope manageable" — `CleanupCategory`'s
    /// static rule→category table, applied to the rule summaries the
    /// caller already built, in a fixed display order rather than however
    /// `summaries` happened to be sorted.
    private var summariesByCategory: [(category: CleanupCategory, summaries: [RuleSummary])] {
        var buckets: [CleanupCategory: [RuleSummary]] = [:]
        for summary in filteredSummaries {
            buckets[CleanupCategory.category(forRuleID: summary.ruleID), default: []].append(summary)
        }
        return buckets.keys.sorted { $0.sortOrder < $1.sortOrder }.map { ($0, buckets[$0] ?? []) }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Cleanup Assessment")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    ExportMenuButton(onExport: onExport)
                    VLEnvironmentBadge(environment)
                }

                Text("Read-only. Runs every Cleanup Assessment rule across the synced period. Doubles as a scoping and pricing input, not a finished quote.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                VLCoverageStrip(
                    dataAvailable: coverageStatus,
                    dataDetail: coverageDetail,
                    checksCompleted: coverageStatus,
                    checksDetail: "\(summaries.count) rule\(summaries.count == 1 ? "" : "s")",
                    exceptions: totalFindingCount == 0 ? .verified : .reviewNeeded,
                    exceptionsDetail: totalFindingCount == 0 ? "None" : "\(totalFindingCount) open"
                )

                VLCard {
                    VStack(alignment: .leading, spacing: VLSpacing.xs) {
                        Text("TOTAL DOLLAR EXPOSURE")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Text(totalExposure?.description ?? "$0.00")
                            .font(VLTypography.metricLarge())
                            .foregroundStyle(VLColor.textPrimary)
                        Text("Estimated hours and price band: not yet available — needs the reconciliation gap map and uncategorized-transaction count, neither built yet. Not shown rather than guessed.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }

                if !summaries.isEmpty {
                    HStack {
                        TextField("Filter by dollar amount (e.g. 142.50)", text: $amountFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        if !amountFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                            if parsedAmountFilter == nil {
                                Text("Not a recognizable amount").font(VLTypography.caption()).foregroundStyle(.red)
                            } else {
                                Text(verbatim: "\(filteredSummaries.flatMap(\.findings).count) matching finding\(filteredSummaries.flatMap(\.findings).count == 1 ? "" : "s")").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                            }
                            Button("Clear") { amountFilter = "" }.buttonStyle(.plain).font(VLTypography.caption()).foregroundStyle(VLColor.cyan)
                        }
                    }
                }

                if summaries.isEmpty {
                    VLCard {
                        Text("No Cleanup Assessment rules registered.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    if !quickWins.isEmpty {
                        quickWinsSection
                    }

                    ForEach(summariesByCategory, id: \.category) { entry in
                        VStack(alignment: .leading, spacing: VLSpacing.sm) {
                            Text(entry.category.label.uppercased())
                                .font(VLTypography.eyebrow())
                                .tracking(VLTypography.eyebrowTracking)
                                .foregroundStyle(VLColor.textMuted)
                            ForEach(entry.summaries) { summary in
                                ruleSection(summary)
                            }
                        }
                    }
                }

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this assessment",
                    primaryDisclaimer: "Answers are grounded in the findings on this page, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this page's findings, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
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

    private var quickWinsSection: some View {
        VLCard(accentRail: VLColor.cyan) {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                Text("QUICK WINS — START HERE")
                    .font(VLTypography.eyebrow())
                    .tracking(VLTypography.eyebrowTracking)
                    .foregroundStyle(VLColor.textMuted)
                Text("Ranked by ease of fix, then dollar impact — a one-click Apply Fix candidate, largest dollar exposure first, is worth clearing before the findings below it that need manual work in QBO.")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
                ForEach(quickWins) { finding in
                    Button {
                        onSelectFinding(finding)
                    } label: {
                        HStack {
                            Text(finding.title)
                                .font(VLTypography.body())
                                .foregroundStyle(VLColor.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let action = finding.proposedActions.first {
                                VLStatusPill(StatusMapping.resolutionStatus(action.resolution), label: action.resolution == .manualQBO ? "Manual QBO" : "Staged")
                            }
                            Text(finding.dollarExposure.description)
                                .font(VLTypography.tabularNumeric())
                                .foregroundStyle(VLColor.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                    if finding.id != quickWins.last?.id {
                        Divider().overlay(VLColor.border)
                    }
                }
            }
        }
    }

    private func ruleSection(_ summary: RuleSummary) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text(summary.title)
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLStatusPill(summary.findings.isEmpty ? .verified : .reviewNeeded, label: "\(summary.findings.count)")
                }
                if summary.findings.isEmpty {
                    Text("None found.")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(summary.findings) { finding in
                        Button {
                            onSelectFinding(finding)
                        } label: {
                            HStack {
                                Text(finding.title)
                                    .font(VLTypography.body())
                                    .foregroundStyle(VLColor.textSecondary)
                                Spacer()
                                // Same "Staged"/"Manual QBO" pill FindingsListView's
                                // row already shows — this page was the one gap
                                // where a finding with an Apply Fix available
                                // looked identical to one that needs the full
                                // guided procedure.
                                if let action = finding.proposedActions.first {
                                    VLStatusPill(StatusMapping.resolutionStatus(action.resolution), label: action.resolution == .manualQBO ? "Manual QBO" : "Staged")
                                }
                                Text(finding.dollarExposure.description)
                                    .font(VLTypography.tabularNumeric())
                                    .foregroundStyle(VLColor.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
