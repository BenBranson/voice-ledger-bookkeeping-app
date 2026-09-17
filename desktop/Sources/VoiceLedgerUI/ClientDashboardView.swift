import SwiftUI
import Core
import DesignSystem

/// Owner directive (2026-08-29): the app's real landing screen — "the app
/// should start with the client's dashboard with KPI graphs and charts
/// that are most important." Previously the app opened on Connection (or
/// wherever the bookkeeper last left it) with no actual overview screen at
/// all — the sidebar's "Dashboard" item was a naming leftover that opened
/// Findings.
///
/// Deliberately composes components that already exist rather than
/// reimplementing them: `KPICardRow`/`BalanceSheetDonutChart`/
/// `ProfitAndLossWaterfallChart`/`ExpenseDriverBarChart` are the exact
/// views `BalanceSheetReportView`/`ProfitAndLossReportView` already use —
/// same computed data (`FinancialKPIs`, `BalanceSheetBreakdown`,
/// `ProfitAndLossWaterfall`, `TopExpenseDrivers`), just on one screen
/// instead of split across two report pages. The charts show the shape of
/// the books; the top-findings list below them is what gives this screen a
/// reason to exist beyond decoration — what actually needs attention right
/// now, using the same `FindingTriage.sorted` priority queue the Findings
/// screen itself is sorted by.
public struct ClientDashboardView: View {
    /// Owner directive (2026-09-06): "the cards on the dashboard should be
    /// clickable to take the user to where it was calculated, for
    /// instance net margin takes the user to balance sheet or P and L if
    /// thats more correct and beneficial" — Net Margin is a P&L figure
    /// (Net Income / Total Income, both P&L lines), so it goes to Profit &
    /// Loss; Working Capital/Current Ratio/Quick Ratio/Cash Balance are
    /// Balance Sheet figures. Kept as this view's own small enum (not a
    /// dependency on `AppState.Screen`) so `VoiceLedgerUI` stays decoupled
    /// from the app target, matching this module's existing boundary.
    public enum ReportDestination {
        case balanceSheet
        case profitAndLoss
        case agedReceivables
        case agedPayables
        case cashFlowForecast
        case recurringVendors
    }

    public struct ViewState {
        public let companyName: String
        public let environment: VLEnvironmentTone
        public let coverageStatus: VLStatus
        public let coverageDetail: String
        public let balanceSheetLines: [ReportLine]
        public let profitAndLossLines: [ReportLine]
        public let isLoadingReports: Bool
        /// Owner directive (2026-09-06): "does the dashboard have all the
        /// KPIs I need... add all please" — the prior-period comparison
        /// (trend arrows), AR/AP aging, vendor concentration, and
        /// month-end close progress this dashboard was missing. Every one
        /// of these reuses data/computations that already existed
        /// elsewhere in the app (variance analysis, aging reports, vendor
        /// spend, the month-end checklist) — nothing here is a new kind of
        /// claim, just surfaced where a bookkeeper's eye lands first.
        public let priorBalanceSheetLines: [ReportLine]
        public let priorProfitAndLossLines: [ReportLine]
        public let agedReceivablesLines: [AgingLine]
        public let agedPayablesLines: [AgingLine]
        public let topVendors: [VendorSpendSummary.VendorTotal]
        public let monthEndChecklistProgress: (completed: Int, total: Int)?
        public let period: AccountingPeriod
        /// Owner directive (2026-09-06): "build cash flow forecasting and
        /// recurring-vendor detection" — surfaced on the dashboard the
        /// same way Month-End Close's progress is: a compact summary here,
        /// full detail on its own page.
        public let cashFlowForecast: CashFlowForecast?
        public let missingRecurringVendorsCount: Int
        /// Already sorted and capped by the caller (`FindingTriage.sorted`,
        /// then `.prefix(5)`) — this view has no opinion about ordering,
        /// same "dumb rendering of what it's given" posture as
        /// `FindingsListView`'s row components.
        public let topFindings: [Finding]
        public let openFindingsCount: Int

        public init(
            companyName: String,
            environment: VLEnvironmentTone,
            coverageStatus: VLStatus,
            coverageDetail: String,
            balanceSheetLines: [ReportLine],
            profitAndLossLines: [ReportLine],
            isLoadingReports: Bool,
            priorBalanceSheetLines: [ReportLine] = [],
            priorProfitAndLossLines: [ReportLine] = [],
            agedReceivablesLines: [AgingLine] = [],
            agedPayablesLines: [AgingLine] = [],
            topVendors: [VendorSpendSummary.VendorTotal] = [],
            monthEndChecklistProgress: (completed: Int, total: Int)? = nil,
            period: AccountingPeriod,
            cashFlowForecast: CashFlowForecast? = nil,
            missingRecurringVendorsCount: Int = 0,
            topFindings: [Finding],
            openFindingsCount: Int
        ) {
            self.companyName = companyName
            self.environment = environment
            self.coverageStatus = coverageStatus
            self.coverageDetail = coverageDetail
            self.balanceSheetLines = balanceSheetLines
            self.profitAndLossLines = profitAndLossLines
            self.isLoadingReports = isLoadingReports
            self.priorBalanceSheetLines = priorBalanceSheetLines
            self.priorProfitAndLossLines = priorProfitAndLossLines
            self.agedReceivablesLines = agedReceivablesLines
            self.agedPayablesLines = agedPayablesLines
            self.topVendors = topVendors
            self.monthEndChecklistProgress = monthEndChecklistProgress
            self.period = period
            self.cashFlowForecast = cashFlowForecast
            self.missingRecurringVendorsCount = missingRecurringVendorsCount
            self.topFindings = topFindings
            self.openFindingsCount = openFindingsCount
        }

        // Same derivation `FindingsListView.ViewState.exceptionsStatus`
        // already uses (CLAUDE.md rule 5: zero findings only reads as
        // green when the check that would have found something is
        // actually current) — duplicated here rather than shared, since
        // the two `ViewState`s are otherwise unrelated shapes and this is
        // six lines, not a subsystem.
        public var exceptionsStatus: VLStatus {
            guard openFindingsCount == 0 else { return .reviewNeeded }
            return coverageStatus == .verified ? .verified : .notChecked
        }

        public var exceptionsDetail: String {
            guard openFindingsCount == 0 else { return "\(openFindingsCount) open" }
            return coverageStatus == .verified ? "None" : "Not synced yet"
        }
    }

    private let state: ViewState
    private let onOpenFinding: (Finding) -> Void
    private let onViewAllFindings: () -> Void
    private let onViewMonthEndClose: () -> Void
    private let onNavigateToReport: (ReportDestination) -> Void
    /// Owner directive (2026-08-30): "a lot of the sections say unsynced
    /// yet there is no refresh button for them to sync" — see `SyncButton`.
    /// This is the landing screen, so it's the single most likely place a
    /// first-time user hits "not synced yet" with no obvious way forward.
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
    private let alternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier]

    public init(
        state: ViewState,
        onOpenFinding: @escaping (Finding) -> Void,
        onViewAllFindings: @escaping () -> Void,
        onViewMonthEndClose: @escaping () -> Void = {},
        onNavigateToReport: @escaping (ReportDestination) -> Void = { _ in },
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
        self.state = state
        self.onOpenFinding = onOpenFinding
        self.onViewAllFindings = onViewAllFindings
        self.onViewMonthEndClose = onViewMonthEndClose
        self.onNavigateToReport = onNavigateToReport
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

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                        Text("Dashboard")
                            .font(VLTypography.pageTitle())
                            .foregroundStyle(VLColor.textPrimary)
                        Text(state.companyName)
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                    Spacer()
                    SyncButton(isSyncing: isSyncing, onSync: onSync)
                    VLEnvironmentBadge(state.environment)
                }

                VLCoverageStrip(
                    dataAvailable: state.coverageStatus,
                    dataDetail: state.coverageDetail,
                    checksCompleted: state.coverageStatus,
                    checksDetail: "\(state.openFindingsCount) open finding\(state.openFindingsCount == 1 ? "" : "s")",
                    exceptions: state.exceptionsStatus,
                    exceptionsDetail: state.exceptionsDetail
                )

                if state.balanceSheetLines.isEmpty && state.profitAndLossLines.isEmpty {
                    VLCard {
                        Text(state.isLoadingReports ? "Loading this client's numbers…" : "No report data yet — sync to see this client's KPIs.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    if !state.balanceSheetLines.isEmpty {
                        KPICardRow(cards: balanceSheetKPICards)
                        BalanceSheetDonutChart(
                            assetSlices: BalanceSheetBreakdown.assetSlices(from: state.balanceSheetLines),
                            liabilitiesAndEquitySlices: BalanceSheetBreakdown.liabilitiesAndEquitySlices(from: state.balanceSheetLines)
                        )
                    }
                    if !state.profitAndLossLines.isEmpty {
                        KPICardRow(cards: profitAndLossKPICards)
                        if let segments = ProfitAndLossWaterfall.segments(from: state.profitAndLossLines) {
                            ProfitAndLossWaterfallChart(segments: segments)
                        }
                        ExpenseDriverBarChart(drivers: TopExpenseDrivers.top(5, from: state.profitAndLossLines))
                    }
                }

                if let arApCards = arApKPICards {
                    KPICardRow(cards: arApCards)
                }

                if !state.topVendors.isEmpty {
                    RankedMoneyBarChart(
                        title: "Top Vendors by Spend",
                        entries: state.topVendors.map { .init(id: $0.id, label: $0.vendorName, amount: $0.total) }
                    )
                }

                if let forecast = state.cashFlowForecast, forecast.startingCash != nil {
                    cashFlowForecastCard(forecast)
                }

                if state.missingRecurringVendorsCount > 0 {
                    recurringVendorsAlertCard
                }

                if let progress = state.monthEndChecklistProgress {
                    monthEndCloseCard(progress)
                }

                topFindingsSection

                TwoTierAskAIPanel(
                    aiStatus: aiStatus,
                    placeholder: "Ask a question about this client's books",
                    primaryDisclaimer: "Answers are grounded in this dashboard's KPIs and top findings, plus a summary of every other open finding across the app — it cannot state a dollar figure, severity, or judgment beyond what's already computed, and it never gives tax or legal advice.",
                    primaryAnswer: askAIAnswer,
                    isAskingPrimary: isAskingAI,
                    primaryError: askAIError,
                    onAskPrimary: onAskAI,
                    secondOpinionConfigured: secondOpinionConfigured,
                    secondOpinionDisclaimer: "Sends this dashboard's KPIs and top findings, plus a summary of every other open finding across the app, to OpenAI's API for a second opinion. This costs money per question and only runs when you ask. Still cannot state a dollar figure or judgment beyond what's already computed, and never gives tax or legal advice.",
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

    private var topFindingsSection: some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text("NEEDS YOUR ATTENTION")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    if state.openFindingsCount > 0 {
                        Button("View All \(state.openFindingsCount)") { onViewAllFindings() }
                            .buttonStyle(.plain)
                            .font(VLTypography.caption())
                    }
                }

                if state.topFindings.isEmpty {
                    Text(state.openFindingsCount == 0 ? "No open findings — you're all caught up." : "")
                        .font(VLTypography.caption())
                        .foregroundStyle(VLColor.textMuted)
                } else {
                    ForEach(state.topFindings) { finding in
                        Button {
                            onOpenFinding(finding)
                        } label: {
                            HStack {
                                Text(finding.title)
                                    .font(VLTypography.body())
                                    .foregroundStyle(VLColor.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text(verbatim: "\(finding.priorityScore)%")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(StatusMapping.priorityStatus(finding.priorityScore).color)
                                Text(finding.dollarExposure.description)
                                    .font(VLTypography.tabularNumericEmphasis())
                                    .foregroundStyle(VLColor.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if finding.id != state.topFindings.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var balanceSheetKPICards: [KPICardRow.CardData] {
        [
            kpiCard(
                label: "Cash Balance",
                money: FinancialKPIs.cashBalance(from: state.balanceSheetLines),
                trend: moneyTrend(current: FinancialKPIs.cashBalance(from: state.balanceSheetLines), prior: FinancialKPIs.cashBalance(from: state.priorBalanceSheetLines)),
                onTap: { onNavigateToReport(.balanceSheet) }
            ),
            kpiCard(
                label: "Working Capital",
                money: FinancialKPIs.workingCapital(from: state.balanceSheetLines),
                trend: moneyTrend(current: FinancialKPIs.workingCapital(from: state.balanceSheetLines), prior: FinancialKPIs.workingCapital(from: state.priorBalanceSheetLines)),
                onTap: { onNavigateToReport(.balanceSheet) }
            ),
            kpiCard(
                label: "Current Ratio",
                ratio: FinancialKPIs.currentRatio(from: state.balanceSheetLines),
                trend: pointsTrend(current: FinancialKPIs.currentRatio(from: state.balanceSheetLines), prior: FinancialKPIs.currentRatio(from: state.priorBalanceSheetLines), suffix: "x"),
                onTap: { onNavigateToReport(.balanceSheet) }
            ),
            kpiCard(
                label: "Quick Ratio",
                ratio: FinancialKPIs.quickRatio(from: state.balanceSheetLines),
                trend: pointsTrend(current: FinancialKPIs.quickRatio(from: state.balanceSheetLines), prior: FinancialKPIs.quickRatio(from: state.priorBalanceSheetLines), suffix: "x"),
                onTap: { onNavigateToReport(.balanceSheet) }
            )
        ]
    }

    private var profitAndLossKPICards: [KPICardRow.CardData] {
        [
            kpiCard(
                label: "Gross Margin",
                percent: FinancialKPIs.grossMarginPercent(from: state.profitAndLossLines),
                trend: pointsTrend(current: FinancialKPIs.grossMarginPercent(from: state.profitAndLossLines), prior: FinancialKPIs.grossMarginPercent(from: state.priorProfitAndLossLines), suffix: "pts"),
                onTap: { onNavigateToReport(.profitAndLoss) }
            ),
            kpiCard(
                label: "Net Margin",
                percent: FinancialKPIs.netMarginPercent(from: state.profitAndLossLines),
                trend: pointsTrend(current: FinancialKPIs.netMarginPercent(from: state.profitAndLossLines), prior: FinancialKPIs.netMarginPercent(from: state.priorProfitAndLossLines), suffix: "pts"),
                onTap: { onNavigateToReport(.profitAndLoss) }
            ),
            kpiCard(
                label: "Net Income",
                money: TaxEstimate.netIncome(from: state.profitAndLossLines),
                trend: moneyTrend(current: TaxEstimate.netIncome(from: state.profitAndLossLines), prior: TaxEstimate.netIncome(from: state.priorProfitAndLossLines)),
                onTap: { onNavigateToReport(.profitAndLoss) }
            )
        ]
    }

    /// `nil` when there's no aging data for either receivables or payables
    /// at all — the whole row stays hidden rather than showing four
    /// "Not available" cards, same "don't render decoration with nothing
    /// behind it" posture as `topVendors`/`monthEndChecklistProgress` below.
    private var arApKPICards: [KPICardRow.CardData]? {
        let receivables = AgingSummary.summarize(state.agedReceivablesLines)
        let payables = AgingSummary.summarize(state.agedPayablesLines)
        guard receivables != nil || payables != nil else { return nil }

        var cards: [KPICardRow.CardData] = []
        if let receivables {
            cards.append(KPICardRow.CardData(
                label: "Accounts Receivable",
                value: receivables.totalAmount?.description ?? "Not available",
                isAvailable: receivables.totalAmount != nil,
                detail: receivables.percentOverdue.map { String(format: "%.0f%% overdue", $0) },
                onTap: { onNavigateToReport(.agedReceivables) }
            ))
            cards.append(kpiCard(
                label: "Days Sales Outstanding (approx.)",
                value: AgingSummary.daysOutstanding(balance: receivables.totalAmount, periodAmount: FinancialKPIs.totalIncome(from: state.profitAndLossLines), daysInPeriod: state.period.daysInMonth).map { String(format: "%.0f days", $0) },
                onTap: { onNavigateToReport(.agedReceivables) }
            ))
        }
        if let payables {
            cards.append(KPICardRow.CardData(
                label: "Accounts Payable",
                value: payables.totalAmount?.description ?? "Not available",
                isAvailable: payables.totalAmount != nil,
                detail: payables.percentOverdue.map { String(format: "%.0f%% overdue", $0) },
                onTap: { onNavigateToReport(.agedPayables) }
            ))
            cards.append(kpiCard(
                label: "Days Payable Outstanding (approx.)",
                value: AgingSummary.daysOutstanding(balance: payables.totalAmount, periodAmount: FinancialKPIs.totalExpenses(from: state.profitAndLossLines), daysInPeriod: state.period.daysInMonth).map { String(format: "%.0f days", $0) },
                onTap: { onNavigateToReport(.agedPayables) }
            ))
        }
        return cards
    }

    private func cashFlowForecastCard(_ forecast: CashFlowForecast) -> some View {
        Button { onNavigateToReport(.cashFlowForecast) } label: {
            VLCard {
                VStack(alignment: .leading, spacing: VLSpacing.sm) {
                    HStack {
                        Text("CASH FLOW FORECAST")
                            .font(VLTypography.eyebrow())
                            .tracking(VLTypography.eyebrowTracking)
                            .foregroundStyle(VLColor.textMuted)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(VLColor.textMuted)
                    }
                    // Same narrow-window reflow fix as `KPICardRow` — a
                    // plain `HStack` doesn't wrap, so these 3 horizons
                    // could squeeze or overflow on a laptop-width window.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: VLSpacing.sm)], spacing: VLSpacing.sm) {
                        ForEach(forecast.horizons) { horizon in
                            VStack(alignment: .leading, spacing: VLSpacing.xxs) {
                                Text("IN \(horizon.days) DAYS")
                                    .font(VLTypography.caption())
                                    .foregroundStyle(VLColor.textMuted)
                                Text(horizon.projectedEndingCash?.description ?? "Not available")
                                    .font(VLTypography.metricMedium())
                                    .foregroundStyle(horizon.projectedEndingCash != nil ? VLColor.cyan : VLColor.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var recurringVendorsAlertCard: some View {
        Button { onNavigateToReport(.recurringVendors) } label: {
            VLCard(accentRail: VLColor.violet) {
                HStack {
                    VLStatusPill(.reviewNeeded, label: "\(state.missingRecurringVendorsCount) recurring vendor(s) overdue for their expected charge")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(VLColor.textMuted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func monthEndCloseCard(_ progress: (completed: Int, total: Int)) -> some View {
        VLCard {
            VStack(alignment: .leading, spacing: VLSpacing.sm) {
                HStack {
                    Text("MONTH-END CLOSE PROGRESS")
                        .font(VLTypography.eyebrow())
                        .tracking(VLTypography.eyebrowTracking)
                        .foregroundStyle(VLColor.textMuted)
                    Spacer()
                    Button("Open Checklist") { onViewMonthEndClose() }
                        .buttonStyle(.plain)
                        .font(VLTypography.caption())
                }
                HStack(spacing: VLSpacing.sm) {
                    ProgressView(value: progress.total > 0 ? Double(progress.completed) / Double(progress.total) : 0)
                        .tint(VLColor.cyan)
                    Text(verbatim: "\(progress.completed) of \(progress.total)")
                        .font(VLTypography.label())
                        .foregroundStyle(VLColor.textSecondary)
                }
            }
        }
    }

    private func kpiCard(label: String, money: Money?, trend: KPICardRow.Trend? = nil, onTap: (() -> Void)? = nil) -> KPICardRow.CardData {
        guard let money else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: money.description, trend: trend, onTap: onTap)
    }

    private func kpiCard(label: String, ratio: Double?, trend: KPICardRow.Trend? = nil, onTap: (() -> Void)? = nil) -> KPICardRow.CardData {
        guard let ratio else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: String(format: "%.2fx", ratio), trend: trend, onTap: onTap)
    }

    private func kpiCard(label: String, percent: Double?, trend: KPICardRow.Trend? = nil, onTap: (() -> Void)? = nil) -> KPICardRow.CardData {
        guard let percent else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: String(format: "%.1f%%", percent), trend: trend, onTap: onTap)
    }

    private func kpiCard(label: String, value: String?, onTap: (() -> Void)? = nil) -> KPICardRow.CardData {
        guard let value else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: value, onTap: onTap)
    }

    /// "vs last month" period-over-period change for a `Money` KPI —
    /// `nil` (no trend shown) rather than a fabricated 0% when the prior
    /// period isn't loaded yet or the two amounts aren't in the same
    /// currency.
    private func moneyTrend(current: Money?, prior: Money?) -> KPICardRow.Trend? {
        guard let current, let prior, current.currency == prior.currency, prior.minorUnits != 0 else { return nil }
        let percentChange = Double(current.minorUnits - prior.minorUnits) / Double(abs(prior.minorUnits)) * 100
        let direction: KPICardRow.Trend.Direction = percentChange > 0.5 ? .up : (percentChange < -0.5 ? .down : .flat)
        return KPICardRow.Trend(direction: direction, label: String(format: "%.1f%% vs last month", abs(percentChange)))
    }

    /// The ratio/margin counterpart to `moneyTrend` — a plain point
    /// difference (e.g. current ratio 1.25x vs. 1.10x is "+0.15x"), not a
    /// percent-of-a-percent, which reads more naturally for a ratio or
    /// margin than a compounded percentage would.
    private func pointsTrend(current: Double?, prior: Double?, suffix: String) -> KPICardRow.Trend? {
        guard let current, let prior else { return nil }
        let delta = current - prior
        let direction: KPICardRow.Trend.Direction = delta > 0.05 ? .up : (delta < -0.05 ? .down : .flat)
        return KPICardRow.Trend(direction: direction, label: String(format: "%.2f\(suffix) vs last month", abs(delta)))
    }
}
