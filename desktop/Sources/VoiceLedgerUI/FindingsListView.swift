import SwiftUI
import Core
import DesignSystem

/// docs/phase-0/11_VERTICAL_SLICE.md §11.2's Page 3 shell: the environment
/// badge, the coverage strip, and the findings list. **Not the full
/// Connection Pages** (step 1.3, separately gated) — this is only what the
/// slice needs, per that section.
public struct FindingsListView: View {
    public struct ViewState {
        public let environment: VLEnvironmentTone
        public let coverageStatus: VLStatus
        public let coverageDetail: String
        public let findings: [Finding]
        public let nextBestAction: NextBestAction?
        /// Gauntlet Loop, Gauntlet C round 4 (2026-08-24): a fresh critic
        /// found `AppState.syncAndEvaluate()`'s failure path only ever set
        /// `loadState = .failed(...)`, which no view anywhere read or
        /// rendered — so a sync that threw partway through left the
        /// bookkeeper with no indication anything went wrong, compounding
        /// the false-green risk this same round found (see `coverage`'s
        /// doc comment in `AppState.swift`). Shown as a dismissible-by-
        /// retry banner right below the title; `nil` when the last attempt
        /// succeeded or no sync has failed yet.
        public let syncError: String?
        /// Owner directive (2026-08-29): "the reports should touch upon the
        /// overall health of the client's books... what's been improved or
        /// downgraded since last month." Same free/second-opinion pairing
        /// as `FindingDetailView`'s Ask AI panels — `secondOpinionConfigured`
        /// gates whether the OpenAI report button renders at all, same as
        /// there.
        public let healthReportAnswer: String?
        public let isGeneratingHealthReport: Bool
        public let healthReportError: String?
        public let healthReportSecondOpinionAnswer: String?
        public let isGeneratingHealthReportSecondOpinion: Bool
        public let healthReportSecondOpinionError: String?
        public let secondOpinionConfigured: Bool
        /// Owner directive (2026-08-29): the "value summary" — shown once
        /// every finding is cleared (see `emptyState`).
        public let valueSummaryAnswer: String?
        public let isGeneratingValueSummary: Bool
        public let valueSummaryError: String?
        public let valueSummarySecondOpinionAnswer: String?
        public let isGeneratingValueSummarySecondOpinion: Bool
        public let valueSummarySecondOpinionError: String?
        /// Owner directive (2026-09-07): "generate report with claude
        /// button" — a third report tier, gated separately from
        /// `secondOpinionConfigured` (OpenAI) since the two are configured
        /// independently (different API keys/providers).
        public let claudeConfigured: Bool
        public let healthReportClaudeAnswer: String?
        public let isGeneratingHealthReportClaude: Bool
        public let healthReportClaudeError: String?
        public let valueSummaryClaudeAnswer: String?
        public let isGeneratingValueSummaryClaude: Bool
        public let valueSummaryClaudeError: String?

        public init(
            environment: VLEnvironmentTone,
            coverageStatus: VLStatus,
            coverageDetail: String,
            findings: [Finding],
            nextBestAction: NextBestAction? = nil,
            syncError: String? = nil,
            healthReportAnswer: String? = nil,
            isGeneratingHealthReport: Bool = false,
            healthReportError: String? = nil,
            healthReportSecondOpinionAnswer: String? = nil,
            isGeneratingHealthReportSecondOpinion: Bool = false,
            healthReportSecondOpinionError: String? = nil,
            secondOpinionConfigured: Bool = false,
            valueSummaryAnswer: String? = nil,
            isGeneratingValueSummary: Bool = false,
            valueSummaryError: String? = nil,
            valueSummarySecondOpinionAnswer: String? = nil,
            isGeneratingValueSummarySecondOpinion: Bool = false,
            valueSummarySecondOpinionError: String? = nil,
            claudeConfigured: Bool = false,
            healthReportClaudeAnswer: String? = nil,
            isGeneratingHealthReportClaude: Bool = false,
            healthReportClaudeError: String? = nil,
            valueSummaryClaudeAnswer: String? = nil,
            isGeneratingValueSummaryClaude: Bool = false,
            valueSummaryClaudeError: String? = nil
        ) {
            self.environment = environment
            self.coverageStatus = coverageStatus
            self.coverageDetail = coverageDetail
            self.findings = findings
            self.nextBestAction = nextBestAction
            self.syncError = syncError
            self.healthReportAnswer = healthReportAnswer
            self.isGeneratingHealthReport = isGeneratingHealthReport
            self.healthReportError = healthReportError
            self.healthReportSecondOpinionAnswer = healthReportSecondOpinionAnswer
            self.isGeneratingHealthReportSecondOpinion = isGeneratingHealthReportSecondOpinion
            self.healthReportSecondOpinionError = healthReportSecondOpinionError
            self.secondOpinionConfigured = secondOpinionConfigured
            self.valueSummaryAnswer = valueSummaryAnswer
            self.isGeneratingValueSummary = isGeneratingValueSummary
            self.valueSummaryError = valueSummaryError
            self.valueSummarySecondOpinionAnswer = valueSummarySecondOpinionAnswer
            self.isGeneratingValueSummarySecondOpinion = isGeneratingValueSummarySecondOpinion
            self.valueSummarySecondOpinionError = valueSummarySecondOpinionError
            self.claudeConfigured = claudeConfigured
            self.healthReportClaudeAnswer = healthReportClaudeAnswer
            self.isGeneratingHealthReportClaude = isGeneratingHealthReportClaude
            self.healthReportClaudeError = healthReportClaudeError
            self.valueSummaryClaudeAnswer = valueSummaryClaudeAnswer
            self.isGeneratingValueSummaryClaude = isGeneratingValueSummaryClaude
            self.valueSummaryClaudeError = valueSummaryClaudeError
        }

        // Gauntlet Loop, Gauntlet C round 2 (2026-08-24): a fresh critic
        // found this used to be `state.findings.isEmpty ? .verified :
        // .reviewNeeded`, computed independent of `coverageStatus` — a
        // stale disk-loaded findings list (from `loadFromDiskOnly()`,
        // before any sync in the current process) that happened to be
        // empty rendered EXCEPTIONS FOUND green right next to DATA
        // AVAILABLE showing gray "not synced yet" in the same strip.
        // `VLStatus.verified`'s own doc comment requires the result to be
        // current, not stale — "zero findings" only proves "verified none"
        // when the data behind it is actually current. A NON-empty stale
        // list isn't the same dishonesty (`.reviewNeeded` never claims the
        // result is current), so only the green claim on an empty list is
        // gated on `coverageStatus` also being `.verified`. Extracted to a
        // pure function so `VoiceLedgerUITests` can exercise it directly —
        // this exact bug previously required a temporary test target to
        // even prove.
        public var exceptionsStatus: VLStatus {
            guard findings.isEmpty else { return .reviewNeeded }
            return coverageStatus == .verified ? .verified : .notChecked
        }

        public var exceptionsDetail: String {
            guard findings.isEmpty else { return "\(findings.count) open" }
            return coverageStatus == .verified ? "None" : "Not synced yet"
        }
    }

    private let state: ViewState
    private let onSelect: (Finding) -> Void
    private let onNavigateNextBestAction: (NextBestAction) -> Void
    /// Owner directive (2026-08-29): "a refresh button in the findings
    /// section to rescan the app for discrepancies in case I create one
    /// during the session." A sidebar sync icon already existed, but it's
    /// easy to miss when this screen is the one being watched "with an
    /// eagle eye" — this puts the same re-scan action directly on the page.
    private let onRefresh: () -> Void
    private let isRefreshing: Bool
    private let onGenerateHealthReport: () -> Void
    private let onGenerateHealthReportSecondOpinion: () -> Void
    private let onGenerateValueSummary: () -> Void
    private let onGenerateValueSummarySecondOpinion: () -> Void
    /// Owner directive (2026-08-29): a client-facing PDF for each of the
    /// four report/tier combinations — shown as a small button under a
    /// panel only once it actually has an answer to export.
    private let onExportHealthReportPDF: () -> Void
    private let onExportHealthReportSecondOpinionPDF: () -> Void
    private let onExportValueSummaryPDF: () -> Void
    private let onExportValueSummarySecondOpinionPDF: () -> Void
    /// Owner directive (2026-08-29): real bug fix — the "Ask a question"
    /// box under each report used to silently discard whatever was typed
    /// and just re-trigger report generation again. These actually carry
    /// the typed question through to a grounded, targeted answer.
    private let onAskHealthReportFollowUp: (String) -> Void
    private let onAskHealthReportFollowUpSecondOpinion: (String) -> Void
    private let onAskValueSummaryFollowUp: (String) -> Void
    private let onAskValueSummaryFollowUpSecondOpinion: (String) -> Void
    /// Owner directive (2026-09-07): a third report tier (Claude Haiku 4.5),
    /// alongside Gemma (free) and OpenAI (second opinion) above.
    private let onGenerateHealthReportClaude: () -> Void
    private let onGenerateValueSummaryClaude: () -> Void
    private let onAskHealthReportFollowUpClaude: (String) -> Void
    private let onAskValueSummaryFollowUpClaude: (String) -> Void
    /// Owner directive (2026-09-06): checked findings, in the order they
    /// appear on screen (not `Set` iteration order, which is unspecified) —
    /// opens the (now unlimited) `FindingComparisonView` with exactly the
    /// checked findings.
    private let onCompareSelected: ([String]) -> Void

    /// Owner directive (2026-08-31): "a quick-click filter component
    /// inside... the Findings views" — purely local, filtering
    /// `state.findings` (already loaded) by exact dollar exposure.
    @State private var amountFilter = ""
    /// Owner directive (2026-09-06): "there should be a clickable box on
    /// each one and i should be able to press compare and analyze these
    /// findings that are checked in the box." Purely local selection state
    /// (same pattern as `amountFilter` above) — only surfaced to the
    /// caller once "Compare & Analyze" is actually pressed, via
    /// `onCompareSelected`.
    @State private var checkedFindingIDs: Set<String> = []

    public init(
        state: ViewState,
        onSelect: @escaping (Finding) -> Void,
        onNavigateNextBestAction: @escaping (NextBestAction) -> Void = { _ in },
        onRefresh: @escaping () -> Void = {},
        isRefreshing: Bool = false,
        onGenerateHealthReport: @escaping () -> Void = {},
        onGenerateHealthReportSecondOpinion: @escaping () -> Void = {},
        onGenerateValueSummary: @escaping () -> Void = {},
        onGenerateValueSummarySecondOpinion: @escaping () -> Void = {},
        onExportHealthReportPDF: @escaping () -> Void = {},
        onExportHealthReportSecondOpinionPDF: @escaping () -> Void = {},
        onExportValueSummaryPDF: @escaping () -> Void = {},
        onExportValueSummarySecondOpinionPDF: @escaping () -> Void = {},
        onAskHealthReportFollowUp: @escaping (String) -> Void = { _ in },
        onAskHealthReportFollowUpSecondOpinion: @escaping (String) -> Void = { _ in },
        onAskValueSummaryFollowUp: @escaping (String) -> Void = { _ in },
        onAskValueSummaryFollowUpSecondOpinion: @escaping (String) -> Void = { _ in },
        onGenerateHealthReportClaude: @escaping () -> Void = {},
        onGenerateValueSummaryClaude: @escaping () -> Void = {},
        onAskHealthReportFollowUpClaude: @escaping (String) -> Void = { _ in },
        onAskValueSummaryFollowUpClaude: @escaping (String) -> Void = { _ in },
        onCompareSelected: @escaping ([String]) -> Void = { _ in }
    ) {
        self.state = state
        self.onSelect = onSelect
        self.onNavigateNextBestAction = onNavigateNextBestAction
        self.onRefresh = onRefresh
        self.isRefreshing = isRefreshing
        self.onGenerateHealthReport = onGenerateHealthReport
        self.onGenerateHealthReportSecondOpinion = onGenerateHealthReportSecondOpinion
        self.onGenerateValueSummary = onGenerateValueSummary
        self.onGenerateValueSummarySecondOpinion = onGenerateValueSummarySecondOpinion
        self.onExportHealthReportPDF = onExportHealthReportPDF
        self.onExportHealthReportSecondOpinionPDF = onExportHealthReportSecondOpinionPDF
        self.onExportValueSummaryPDF = onExportValueSummaryPDF
        self.onExportValueSummarySecondOpinionPDF = onExportValueSummarySecondOpinionPDF
        self.onAskHealthReportFollowUp = onAskHealthReportFollowUp
        self.onAskHealthReportFollowUpSecondOpinion = onAskHealthReportFollowUpSecondOpinion
        self.onAskValueSummaryFollowUp = onAskValueSummaryFollowUp
        self.onAskValueSummaryFollowUpSecondOpinion = onAskValueSummaryFollowUpSecondOpinion
        self.onGenerateHealthReportClaude = onGenerateHealthReportClaude
        self.onGenerateValueSummaryClaude = onGenerateValueSummaryClaude
        self.onAskHealthReportFollowUpClaude = onAskHealthReportFollowUpClaude
        self.onAskValueSummaryFollowUpClaude = onAskValueSummaryFollowUpClaude
        self.onCompareSelected = onCompareSelected
    }

    private var parsedAmountFilter: Money? {
        AmountSearch.parseAmount(amountFilter)
    }

    private var filteredFindings: [Finding] {
        guard let parsedAmountFilter else { return state.findings }
        return state.findings.filter {
            $0.dollarExposure.currency == parsedAmountFilter.currency && abs($0.dollarExposure.minorUnits) == abs(parsedAmountFilter.minorUnits)
        }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Transactions")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Button(action: onRefresh) {
                        HStack(spacing: VLSpacing.xxs) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                                .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                            Text(isRefreshing ? "Refreshing…" : "Refresh")
                        }
                        .font(VLTypography.label())
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRefreshing)
                    .help("Re-scan QBO for new or changed discrepancies")
                    VLEnvironmentBadge(state.environment)
                }

                if let syncError = state.syncError {
                    Text("The last sync didn't finish: \(syncError). What's shown below may be out of date — try Sync again.")
                        .font(VLTypography.caption())
                        .foregroundStyle(.red)
                }

                if let nextBestAction = state.nextBestAction {
                    NextBestActionView(action: nextBestAction, onNavigate: { onNavigateNextBestAction(nextBestAction) })
                }

                VLCoverageStrip(
                    dataAvailable: state.coverageStatus,
                    dataDetail: state.coverageDetail,
                    checksCompleted: state.coverageStatus,
                    checksDetail: "\(state.findings.count) finding\(state.findings.count == 1 ? "" : "s")",
                    exceptions: state.exceptionsStatus,
                    exceptionsDetail: state.exceptionsDetail
                )

                healthReportSection

                if !state.findings.isEmpty {
                    HStack {
                        TextField("Filter by dollar amount (e.g. 142.50)", text: $amountFilter)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                        if !amountFilter.trimmingCharacters(in: .whitespaces).isEmpty {
                            if parsedAmountFilter == nil {
                                Text("Not a recognizable amount").font(VLTypography.caption()).foregroundStyle(.red)
                            } else {
                                Text("\(filteredFindings.count) matching finding\(filteredFindings.count == 1 ? "" : "s")").font(VLTypography.caption()).foregroundStyle(VLColor.textMuted)
                            }
                            Button("Clear") { amountFilter = "" }.buttonStyle(.plain).font(VLTypography.caption()).foregroundStyle(VLColor.cyan)
                        }
                    }
                }

                if !filteredFindings.isEmpty {
                    compareBar
                }

                if state.findings.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: VLSpacing.sm) {
                        ForEach(filteredFindings) { finding in
                            HStack(spacing: VLSpacing.sm) {
                                // Owner directive (2026-09-06): "there
                                // should be a clickable box on each one" —
                                // a separate tap target from the row itself
                                // so checking a box for comparison never
                                // also opens that finding's detail page.
                                Button {
                                    if checkedFindingIDs.contains(finding.id) {
                                        checkedFindingIDs.remove(finding.id)
                                    } else {
                                        checkedFindingIDs.insert(finding.id)
                                    }
                                } label: {
                                    Image(systemName: checkedFindingIDs.contains(finding.id) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 16))
                                        .foregroundStyle(checkedFindingIDs.contains(finding.id) ? VLColor.cyan : VLColor.textMuted)
                                }
                                .buttonStyle(.plain)
                                .help("Select for comparison")

                                Button {
                                    onSelect(finding)
                                } label: {
                                    FindingRow(finding: finding)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    /// Owner directive (2026-09-06): shown only once at least one finding
    /// is checked — stays out of the way otherwise. "Compare & Analyze"
    /// requires 2+ (comparing one finding to itself isn't a comparison);
    /// a single checked finding can still be cleared from here.
    @ViewBuilder
    private var compareBar: some View {
        if !checkedFindingIDs.isEmpty {
            HStack(spacing: VLSpacing.sm) {
                Text("\(checkedFindingIDs.count) selected")
                    .font(VLTypography.label())
                    .foregroundStyle(VLColor.textSecondary)
                Button("Compare & Analyze") {
                    let orderedIDs = filteredFindings.filter { checkedFindingIDs.contains($0.id) }.map(\.id)
                    onCompareSelected(orderedIDs)
                    checkedFindingIDs = []
                }
                .buttonStyle(.borderedProminent)
                .disabled(checkedFindingIDs.count < 2)
                .help(checkedFindingIDs.count < 2 ? "Check at least 2 findings to compare" : "Open these \(checkedFindingIDs.count) findings side by side")
                Button("Clear Selection") { checkedFindingIDs = [] }
                    .buttonStyle(.plain)
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.cyan)
            }
            .padding(.horizontal, VLSpacing.sm)
            .padding(.vertical, VLSpacing.xs)
            .background(VLColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// Owner directive (2026-08-29): "at the top of findings there should
    /// be 2 buttons, one generate report with gemma... and the other...
    /// open AI which should possibly be even more thorough." Reuses
    /// `AskAIPanelView` exactly as `FindingDetailView` does for its own
    /// two-tier panels — same component, page-level context instead of one
    /// finding's.
    private var healthReportSection: some View {
        VStack(alignment: .leading, spacing: VLSpacing.sm) {
            AskAIPanelView(
                title: "BOOK HEALTH REPORT (GEMMA — FREE)",
                disclaimer: "Covers open issues, what's been fixed, key metrics, and change since the last report — all numbers already computed by this app.",
                aiStatus: nil,
                answer: state.healthReportAnswer,
                isAsking: state.isGeneratingHealthReport,
                error: state.healthReportError,
                onAsk: onAskHealthReportFollowUp,
                quickAskLabel: "Generate Report (Gemma)",
                onQuickAsk: onGenerateHealthReport
            )
            if state.healthReportAnswer != nil {
                exportPDFButton(action: onExportHealthReportPDF)
            }
            if state.secondOpinionConfigured {
                AskAIPanelView(
                    title: "BOOK HEALTH REPORT (OPENAI — MORE THOROUGH)",
                    disclaimer: "Same real numbers, sent to OpenAI for a more thorough read. Costs money per report and only runs when you ask.",
                    aiStatus: nil,
                    answer: state.healthReportSecondOpinionAnswer,
                    isAsking: state.isGeneratingHealthReportSecondOpinion,
                    error: state.healthReportSecondOpinionError,
                    onAsk: onAskHealthReportFollowUpSecondOpinion,
                    quickAskLabel: "Generate Report (OpenAI)",
                    onQuickAsk: onGenerateHealthReportSecondOpinion
                )
                if state.healthReportSecondOpinionAnswer != nil {
                    exportPDFButton(action: onExportHealthReportSecondOpinionPDF)
                }
            }
            if state.claudeConfigured {
                AskAIPanelView(
                    title: "BOOK HEALTH REPORT (CLAUDE HAIKU 4.5)",
                    disclaimer: "Same real numbers, sent to Claude Haiku 4.5 for a fast cloud read. Costs a fraction of a cent per report and only runs when you ask.",
                    aiStatus: nil,
                    answer: state.healthReportClaudeAnswer,
                    isAsking: state.isGeneratingHealthReportClaude,
                    error: state.healthReportClaudeError,
                    onAsk: onAskHealthReportFollowUpClaude,
                    quickAskLabel: "Generate Report (Claude)",
                    onQuickAsk: onGenerateHealthReportClaude
                )
            }
        }
    }

    /// Owner directive (2026-08-29): a client-facing PDF for a generated
    /// report — shown only once there's an actual answer to export.
    private func exportPDFButton(action: @escaping () -> Void) -> some View {
        Button("Export as PDF", action: action)
            .buttonStyle(.bordered)
            .font(VLTypography.caption())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: VLSpacing.sm) {
            VLCard {
                HStack(spacing: VLSpacing.sm) {
                    VLStatusPill(state.coverageStatus, label: state.coverageStatus == .verified ? "No duplicates found" : state.coverageDetail)
                    Spacer()
                }
            }

            // Owner directive (2026-08-29): "after all findings are
            // completed I should be able to press a button that explains
            // all changes... whether I helped the client save money, time,
            // etc." Only offered once genuinely verified-clear (CLAUDE.md
            // rule 5 — never invite a value claim built on a stale or
            // never-synced "empty" list).
            if state.coverageStatus == .verified {
                VStack(alignment: .leading, spacing: VLSpacing.sm) {
                    AskAIPanelView(
                        title: "CLIENT VALUE SUMMARY (GEMMA — FREE)",
                        disclaimer: "Summarizes what was found and corrected since the last report, and the real dollar exposure addressed — never a claim of literal cash saved.",
                        aiStatus: nil,
                        answer: state.valueSummaryAnswer,
                        isAsking: state.isGeneratingValueSummary,
                        error: state.valueSummaryError,
                        onAsk: onAskValueSummaryFollowUp,
                        quickAskLabel: "Generate Client Value Report (Gemma)",
                        onQuickAsk: onGenerateValueSummary
                    )
                    if state.valueSummaryAnswer != nil {
                        exportPDFButton(action: onExportValueSummaryPDF)
                    }
                    if state.secondOpinionConfigured {
                        AskAIPanelView(
                            title: "CLIENT VALUE SUMMARY (OPENAI — MORE THOROUGH)",
                            disclaimer: "Same real numbers, sent to OpenAI for a more thorough read. Costs money per report and only runs when you ask.",
                            aiStatus: nil,
                            answer: state.valueSummarySecondOpinionAnswer,
                            isAsking: state.isGeneratingValueSummarySecondOpinion,
                            error: state.valueSummarySecondOpinionError,
                            onAsk: onAskValueSummaryFollowUpSecondOpinion,
                            quickAskLabel: "Generate Client Value Report (OpenAI)",
                            onQuickAsk: onGenerateValueSummarySecondOpinion
                        )
                        if state.valueSummarySecondOpinionAnswer != nil {
                            exportPDFButton(action: onExportValueSummarySecondOpinionPDF)
                        }
                    }
                    if state.claudeConfigured {
                        AskAIPanelView(
                            title: "CLIENT VALUE SUMMARY (CLAUDE HAIKU 4.5)",
                            disclaimer: "Same real numbers, sent to Claude Haiku 4.5 for a fast cloud read. Costs a fraction of a cent per report and only runs when you ask.",
                            aiStatus: nil,
                            answer: state.valueSummaryClaudeAnswer,
                            isAsking: state.isGeneratingValueSummaryClaude,
                            error: state.valueSummaryClaudeError,
                            onAsk: onAskValueSummaryFollowUpClaude,
                            quickAskLabel: "Generate Client Value Report (Claude)",
                            onQuickAsk: onGenerateValueSummaryClaude
                        )
                    }
                }
            }
        }
    }
}

private struct FindingRow: View {
    let finding: Finding

    var body: some View {
        // Owner directive (2026-08-29): triage queue — the accent rail and
        // the leading pill both key off `priorityScore`'s color band, not
        // raw severity, so the strongest visual signal on the row matches
        // the order the list itself is sorted in (`FindingTriage.sorted`,
        // RootView.swift).
        VLCard(accentRail: StatusMapping.priorityStatus(finding.priorityScore).color) {
            VStack(alignment: .leading, spacing: VLSpacing.xs) {
                HStack {
                    Text(finding.title)
                        .font(VLTypography.cardTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    Text(finding.dollarExposure.description)
                        .font(VLTypography.tabularNumericEmphasis())
                        .foregroundStyle(VLColor.textPrimary)
                }
                HStack(spacing: VLSpacing.xs) {
                    VLStatusPill(StatusMapping.priorityStatus(finding.priorityScore), label: "\(finding.priorityScore)% priority")
                    VLStatusPill(StatusMapping.severityStatus(finding.severity), label: finding.severity == .high ? "High" : "Low")
                    Text("Confidence: \(finding.confidence.rawValue.capitalized)")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                    if let action = finding.proposedActions.first {
                        VLStatusPill(StatusMapping.resolutionStatus(action.resolution), label: action.resolution == .manualQBO ? "Manual QBO" : "Staged")
                    }
                }
            }
        }
    }
}
