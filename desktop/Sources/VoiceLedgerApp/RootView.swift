import SwiftUI
import Core
import DesignSystem
import VoiceLedgerUI

struct RootView: View {
    @Bindable var state: AppState
    @State private var actorName = NSFullUserName()

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Sync") { Task { await state.syncAndEvaluate() } }
                            .disabled(state.loadState == .loading)
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Cleanup Assessment") { state.screen = .cleanupAssessment }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Activity Log") { state.screen = .activityLog }
                    }
                }
        }
        .task { await state.loadFromDiskOnly() }
    }

    @ViewBuilder
    private var content: some View {
        switch state.screen {
        case .list:
            FindingsListView(
                state: FindingsListView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    coverageStatus: StatusMapping.status(for: coverageOutcome),
                    coverageDetail: coverageDetail,
                    findings: state.findings.filter { $0.status == .open && !AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) }
                ),
                onSelect: { finding in state.screen = .detail(findingID: finding.id) }
            )

        case .detail(let findingID):
            if let finding = state.finding(id: findingID) {
                FindingDetailView(
                    finding: finding,
                    onStartProcedure: { action in state.screen = .procedure(findingID: findingID, actionID: action.id) },
                    onDismiss: { state.screen = .list }
                )
            } else {
                Text("Finding not found — it may already be resolved.")
                    .onAppear { state.screen = .list }
            }

        case .procedure(let findingID, let actionID):
            if let finding = state.finding(id: findingID),
               let action = finding.proposedActions.first(where: { $0.id == actionID }),
               let procedure = action.guidedProcedure {
                GuidedProcedureView(
                    procedure: procedure,
                    onAttest: { note in
                        Task { await state.attestCompletion(findingID: findingID, actorName: actorName, note: note) }
                    },
                    onCancel: { state.screen = .detail(findingID: findingID) }
                )
            } else {
                Text("Procedure not found.")
                    .onAppear { state.screen = .list }
            }

        case .activityLog:
            ActivityLogView(entries: state.activityLog)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { state.screen = .list }
                    }
                }

        case .cleanupAssessment:
            CleanupAssessmentView(
                environment: state.environment == .production ? .production : .sandbox,
                coverageStatus: StatusMapping.status(for: coverageOutcome),
                coverageDetail: coverageDetail,
                summaries: cleanupAssessmentSummaries,
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }
        }
    }

    /// Only two rules exist today, so the title mapping is a small literal
    /// table rather than a generic lookup — revisit once more Cleanup
    /// Assessment rules exist (`RuleIdentity.title` could be read directly
    /// at that point instead of duplicating it here).
    private var cleanupAssessmentSummaries: [CleanupAssessmentView.RuleSummary] {
        let openFindings = state.findings.filter { $0.status == .open }
        return [
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-CC-PAYMENT-001",
                title: "Credit card payments coded to an expense account",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-CC-PAYMENT-001" }
            ),
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-PAYROLL-LUMP-001",
                title: "Payroll payments on a single lump-sum line",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-PAYROLL-LUMP-001" }
            )
        ]
    }

    /// This app hasn't synced yet on first launch, so there's no
    /// `RuleOutcome` to map directly — `coverage` alone is enough for the
    /// list page's coverage strip. A real per-rule outcome (with the
    /// engine's `.cannotEvaluate` reason) is available immediately after a
    /// sync, via `state.coverage`.
    private var coverageOutcome: RuleOutcome {
        switch state.coverage {
        case .complete: return .pass(coverage: .complete, checkedCount: state.findings.count)
        case .partial(let reason): return .cannotEvaluate(.partialCoverage(reason: reason))
        }
    }

    private var coverageDetail: String {
        switch state.coverage {
        case .complete: return "Synced"
        case .partial(let reason): return reason
        }
    }
}
