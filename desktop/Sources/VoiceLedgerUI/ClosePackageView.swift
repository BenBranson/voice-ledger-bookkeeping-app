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
/// counts, Balance Sheet + Profit & Loss summary lines, and recent activity
/// log entries — everything the app already has computed from real synced
/// data. **Not built**: variance analysis, cash flow / general ledger /
/// trial balance / aging reports, a tracked "corrections made" ledger
/// distinct from the Activity Log, carry-forward items, client Q&A, and Ask
/// Claude history (no Claude integration exists yet at all). Also not a
/// branded, exportable PDF — this is an in-app read-only consolidated view,
/// same as `FinancialReportView` and `BalanceSheetIntegrityView`.
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
    private let recentActivity: [ActivityLogEntry]

    public init(
        environment: VLEnvironmentTone,
        period: AccountingPeriod,
        checklistStatus: ChecklistStatus,
        openCleanupFindingsCount: Int,
        resolvedCleanupFindingsCount: Int,
        balanceSheetLines: [ReportLine],
        profitAndLossLines: [ReportLine],
        recentActivity: [ActivityLogEntry]
    ) {
        self.environment = environment
        self.period = period
        self.checklistStatus = checklistStatus
        self.openCleanupFindingsCount = openCleanupFindingsCount
        self.resolvedCleanupFindingsCount = resolvedCleanupFindingsCount
        self.balanceSheetLines = balanceSheetLines
        self.profitAndLossLines = profitAndLossLines
        self.recentActivity = recentActivity
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Close Package")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(environment)
                }

                Text("\(period.year)-\(String(format: "%02d", period.month)) · A consolidated summary of this period's close, assembled from what's already been synced and recorded — not a branded exportable document, and not the full spec'd Close Package (no variance analysis, no cash flow/GL/trial balance/aging reports, no carry-forward items or client Q&A).")
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textMuted)

                checklistSection
                cleanupSection

                if !balanceSheetLines.isEmpty {
                    reportSummarySection(title: "Balance Sheet (summary lines)", lines: balanceSheetLines)
                }
                if !profitAndLossLines.isEmpty {
                    reportSummarySection(title: "Profit & Loss (summary lines)", lines: profitAndLossLines)
                }

                activitySection
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
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
                        HStack {
                            Text(entry.kind.rawValue)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textPrimary)
                            Spacer()
                            Text(entry.recordedAt, style: .date)
                                .font(VLTypography.caption())
                                .foregroundStyle(VLColor.textMuted)
                        }
                    }
                }
            }
        }
    }
}
