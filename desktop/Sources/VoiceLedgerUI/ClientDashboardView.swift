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
    public struct ViewState {
        public let companyName: String
        public let environment: VLEnvironmentTone
        public let coverageStatus: VLStatus
        public let coverageDetail: String
        public let balanceSheetLines: [ReportLine]
        public let profitAndLossLines: [ReportLine]
        public let isLoadingReports: Bool
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

    public init(state: ViewState, onOpenFinding: @escaping (Finding) -> Void, onViewAllFindings: @escaping () -> Void) {
        self.state = state
        self.onOpenFinding = onOpenFinding
        self.onViewAllFindings = onViewAllFindings
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

                topFindingsSection
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
                                Text("\(finding.priorityScore)%")
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
            kpiCard(label: "Working Capital", money: FinancialKPIs.workingCapital(from: state.balanceSheetLines)),
            kpiCard(label: "Current Ratio", ratio: FinancialKPIs.currentRatio(from: state.balanceSheetLines)),
            kpiCard(label: "Quick Ratio", ratio: FinancialKPIs.quickRatio(from: state.balanceSheetLines))
        ]
    }

    private var profitAndLossKPICards: [KPICardRow.CardData] {
        [
            kpiCard(label: "Gross Margin", percent: FinancialKPIs.grossMarginPercent(from: state.profitAndLossLines)),
            kpiCard(label: "Net Margin", percent: FinancialKPIs.netMarginPercent(from: state.profitAndLossLines)),
            KPICardRow.CardData(
                label: "Net Income",
                value: TaxEstimate.netIncome(from: state.profitAndLossLines)?.description ?? "Not available",
                isAvailable: TaxEstimate.netIncome(from: state.profitAndLossLines) != nil
            )
        ]
    }

    private func kpiCard(label: String, money: Money?) -> KPICardRow.CardData {
        guard let money else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: money.description)
    }

    private func kpiCard(label: String, ratio: Double?) -> KPICardRow.CardData {
        guard let ratio else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: String(format: "%.2fx", ratio))
    }

    private func kpiCard(label: String, percent: Double?) -> KPICardRow.CardData {
        guard let percent else { return KPICardRow.CardData(label: label, value: "Not available", isAvailable: false) }
        return KPICardRow.CardData(label: label, value: String(format: "%.1f%%", percent))
    }
}
