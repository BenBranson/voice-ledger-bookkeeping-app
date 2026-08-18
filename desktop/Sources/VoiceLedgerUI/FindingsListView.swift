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

        public init(environment: VLEnvironmentTone, coverageStatus: VLStatus, coverageDetail: String, findings: [Finding], nextBestAction: NextBestAction? = nil) {
            self.environment = environment
            self.coverageStatus = coverageStatus
            self.coverageDetail = coverageDetail
            self.findings = findings
            self.nextBestAction = nextBestAction
        }
    }

    private let state: ViewState
    private let onSelect: (Finding) -> Void
    private let onNavigateNextBestAction: (NextBestAction) -> Void

    public init(state: ViewState, onSelect: @escaping (Finding) -> Void, onNavigateNextBestAction: @escaping (NextBestAction) -> Void = { _ in }) {
        self.state = state
        self.onSelect = onSelect
        self.onNavigateNextBestAction = onNavigateNextBestAction
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VLSpacing.md) {
                HStack {
                    Text("Transactions")
                        .font(VLTypography.pageTitle())
                        .foregroundStyle(VLColor.textPrimary)
                    Spacer()
                    VLEnvironmentBadge(state.environment)
                }

                if let nextBestAction = state.nextBestAction {
                    NextBestActionView(action: nextBestAction, onNavigate: { onNavigateNextBestAction(nextBestAction) })
                }

                VLCoverageStrip(
                    dataAvailable: state.coverageStatus,
                    dataDetail: state.coverageDetail,
                    checksCompleted: state.coverageStatus,
                    checksDetail: "\(state.findings.count) finding\(state.findings.count == 1 ? "" : "s")",
                    exceptions: state.findings.isEmpty ? .verified : .reviewNeeded,
                    exceptionsDetail: state.findings.isEmpty ? "None" : "\(state.findings.count) open"
                )

                if state.findings.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: VLSpacing.sm) {
                        ForEach(state.findings) { finding in
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
            .padding(VLSpacing.pageGutter)
        }
        .background(VLColor.background)
    }

    private var emptyState: some View {
        VLCard {
            HStack(spacing: VLSpacing.sm) {
                VLStatusPill(state.coverageStatus, label: state.coverageStatus == .verified ? "No duplicates found" : state.coverageDetail)
                Spacer()
            }
        }
    }
}

private struct FindingRow: View {
    let finding: Finding

    var body: some View {
        VLCard(accentRail: StatusMapping.severityStatus(finding.severity).color) {
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
