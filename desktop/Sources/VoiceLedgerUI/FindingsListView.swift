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

        public init(environment: VLEnvironmentTone, coverageStatus: VLStatus, coverageDetail: String, findings: [Finding], nextBestAction: NextBestAction? = nil, syncError: String? = nil) {
            self.environment = environment
            self.coverageStatus = coverageStatus
            self.coverageDetail = coverageDetail
            self.findings = findings
            self.nextBestAction = nextBestAction
            self.syncError = syncError
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
