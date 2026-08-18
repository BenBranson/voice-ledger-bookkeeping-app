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

    public init(
        environment: VLEnvironmentTone,
        coverageStatus: VLStatus,
        coverageDetail: String,
        summaries: [RuleSummary],
        onSelectFinding: @escaping (Finding) -> Void,
        onExport: @escaping (ReportExportFormat) -> Void = { _ in }
    ) {
        self.environment = environment
        self.coverageStatus = coverageStatus
        self.coverageDetail = coverageDetail
        self.summaries = summaries
        self.onSelectFinding = onSelectFinding
        self.onExport = onExport
    }

    private var totalFindingCount: Int { summaries.reduce(0) { $0 + $1.findings.count } }
    private var totalExposure: Money? {
        let all = summaries.flatMap(\.findings)
        guard let first = all.first else { return nil }
        return all.dropFirst().reduce(first.dollarExposure) { $0 + $1.dollarExposure }
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Cleanup Assessment")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
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

                if summaries.isEmpty {
                    VLCard {
                        Text("No Cleanup Assessment rules registered.")
                            .foregroundStyle(VLColor.textMuted)
                    }
                } else {
                    ForEach(summaries) { summary in
                        ruleSection(summary)
                    }
                }
            }
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
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
