import SwiftUI
import Core
import IntegrationsQuickBooks
import DesignSystem
import VoiceLedgerUI

struct RootView: View {
    @Bindable var state: AppState
    @State private var actorName = NSFullUserName()
    @State private var isImportingStatement = false

    var body: some View {
        NavigationStack {
            content
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button("Connection") { state.screen = .connection }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Sync") { Task { await state.syncAndEvaluate() } }
                            .disabled(state.loadState == .loading)
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Cleanup Assessment") { state.screen = .cleanupAssessment }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Balance Sheet Integrity") { state.screen = .balanceSheetIntegrity }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Bank Feed Cleanup") { state.screen = .bankFeedCleanup }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button("Activity Log") { state.screen = .activityLog }
                    }
                }
        }
        .task {
            await state.loadFromDiskOnly()
            await state.checkHealth()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.screen {
        case .connection:
            ConnectionView(
                state: ConnectionView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    companyName: state.companyInfo?.companyName,
                    realmID: state.companyInfo?.realmID.rawValue ?? "(not yet checked)",
                    healthStatus: state.healthResult.map { Self.vlStatus(for: $0.status) },
                    healthDetail: state.healthCheckError ?? state.healthResult.map { "\($0.status.rawValue) — \($0.latencyMs)ms" },
                    lastCheckedAt: state.healthResult?.checkedAt,
                    isChecking: state.isCheckingHealth
                ),
                onCheckHealth: { Task { await state.checkHealth() } }
            )

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

        case .balanceSheetIntegrity:
            BalanceSheetIntegrityView(
                environment: state.environment == .production ? .production : .sandbox,
                coverageStatus: StatusMapping.status(for: coverageOutcome),
                coverageDetail: coverageDetail,
                summaries: balanceSheetIntegritySummaries,
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .bankFeedCleanup:
            let missingPostingFindings = state.findings.filter { $0.status == .open && $0.ruleID.rawValue == "VL-RECON-MISSING-001" }
            BankFeedCleanupView(
                environment: state.environment == .production ? .production : .sandbox,
                coverageStatus: missingPostingFindings.isEmpty ? .notChecked : .reviewNeeded,
                missingPostingOutcomeDetail: "No statement imported for this period. Import a bank/card statement to run this check (docs/VOICE_LEDGER_SPEC.md Page 4).",
                findings: missingPostingFindings,
                importError: state.importError,
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) },
                onImportTapped: { isImportingStatement = true }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }
            .fileImporter(isPresented: $isImportingStatement, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                // A `.failure` here is the user cancelling the panel or an
                // OS-level picker error — nothing to show; `selectFileForImport`
                // itself reports a real read/parse failure via `importError`.
                if case .success(let url) = result {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    state.selectFileForImport(url: url)
                }
            }
            .sheet(isPresented: Binding(get: { state.pendingImport != nil }, set: { if !$0 { state.cancelPendingImport() } })) {
                if let pending = state.pendingImport {
                    ImportBankStatementView(
                        filename: pending.filename,
                        columns: Self.columnPreviews(for: pending),
                        onConfirm: { mappings in Task { await state.confirmImport(mappings: mappings) } },
                        onCancel: { state.cancelPendingImport() }
                    )
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
            ),
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-OBE-BALANCE-001",
                title: "Nonzero Opening Balance Equity",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-OBE-BALANCE-001" }
            ),
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-BS-NEGBAL-001",
                title: "Negative asset or liability balances",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-BS-NEGBAL-001" }
            ),
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-DUP-VEND-001",
                title: "Possible duplicate vendor records",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-DUP-VEND-001" }
            ),
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-DUP-BILL-001",
                title: "Possible duplicate bills",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-DUP-BILL-001" }
            ),
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-DUP-INV-001",
                title: "Possible duplicate invoices",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-DUP-INV-001" }
            ),
            CleanupAssessmentView.RuleSummary(
                ruleID: "VL-DUP-PAY-001",
                title: "Possible duplicate payments",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-DUP-PAY-001" }
            )
        ]
    }

    private var balanceSheetIntegritySummaries: [BalanceSheetIntegrityView.RuleSummary] {
        let openFindings = state.findings.filter { $0.status == .open }
        return [
            BalanceSheetIntegrityView.RuleSummary(
                ruleID: "VL-BS-NEGBAL-001",
                title: "Negative asset or liability balances",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-BS-NEGBAL-001" }
            ),
            BalanceSheetIntegrityView.RuleSummary(
                ruleID: "VL-OBE-BALANCE-001",
                title: "Nonzero Opening Balance Equity",
                findings: openFindings.filter { $0.ruleID.rawValue == "VL-OBE-BALANCE-001" }
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

    /// `HealthStatus` (IntegrationsQuickBooks) -> `VLStatus` (DesignSystem).
    /// Lives here, not in `VoiceLedgerUI`'s `StatusMapping`, because
    /// `VoiceLedgerUI` deliberately has no dependency on
    /// `IntegrationsQuickBooks` (Package.swift's boundary) — only the app
    /// layer, which already depends on both, is allowed to bridge them.
    private static func vlStatus(for health: HealthStatus) -> VLStatus {
        switch health {
        case .green: return .verified
        case .yellow: return .reviewNeeded
        case .red: return .urgent
        case .gray: return .notChecked
        }
    }

    /// Builds one `ColumnPreview` per CSV column — header (from row 0, if
    /// present) and up to 3 sample values from the data rows — for
    /// `ImportBankStatementView`'s confirm-and-correct screen.
    private static func columnPreviews(for pending: AppState.PendingImport) -> [ImportBankStatementView.ColumnPreview] {
        let headerRow = pending.hasHeaderRow ? pending.allRows.first : nil
        let dataRows = pending.hasHeaderRow ? Array(pending.allRows.dropFirst()) : pending.allRows
        let columnCount = pending.allRows.map(\.count).max() ?? 0

        return (0..<columnCount).map { index in
            let header = headerRow.flatMap { $0.indices.contains(index) ? $0[index] : nil } ?? "Column \(index + 1)"
            let samples = dataRows.prefix(3).compactMap { $0.indices.contains(index) ? $0[index] : nil }
            return ImportBankStatementView.ColumnPreview(index: index, header: header, sampleValues: samples)
        }
    }
}
