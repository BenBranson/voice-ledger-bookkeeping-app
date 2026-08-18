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
                    // docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "Wrong-Client
                    // Protection — active company and period pinned to every
                    // screen." Every other screen showed only the environment
                    // badge (sandbox/production) — never the company name or
                    // period at all, a real gap once more than one client
                    // connection exists. Placed on the shared toolbar (not
                    // each screen individually) so it's automatically on
                    // every one of them, present tense, no exceptions.
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: VLSpacing.xs) {
                            Text(state.companyInfo?.companyName ?? "No company connected")
                                .font(.headline)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text("\(state.currentPeriod.year)-\(String(format: "%02d", state.currentPeriod.month))")
                                .foregroundStyle(.secondary)
                            VLEnvironmentBadge(state.environment == .production ? .production : .sandbox)
                        }
                    }
                    ToolbarItemGroup(placement: .automatic) {
                        Button("Connection") { state.screen = .connection }
                        Button("Sync") { Task { await state.syncAndEvaluate() } }
                            .disabled(state.loadState == .loading)
                        Button("Cleanup Assessment") { state.screen = .cleanupAssessment }
                        Button("Balance Sheet Integrity") { state.screen = .balanceSheetIntegrity }
                        Button("Bank Feed Cleanup") { state.screen = .bankFeedCleanup }
                        Button("Month-End Close") { state.screen = .monthEndClose }
                        Button("Balance Sheet") { state.screen = .balanceSheetReport }
                        Button("Profit & Loss") { state.screen = .profitAndLossReport }
                        Button("Activity Log") { state.screen = .activityLog }
                        Button("Close Package") { state.screen = .closePackage }
                        Button("Client Memory") { state.screen = .clientMemory }
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
                    isChecking: state.isCheckingHealth,
                    writeEnabled: state.writeAccessEnabled,
                    isTogglingWriteAccess: state.isTogglingWriteAccess
                ),
                onCheckHealth: { Task { await state.checkHealth() } },
                onToggleWriteAccess: { enabled in Task { await state.setWriteAccess(enabled) } }
            )

        case .list:
            FindingsListView(
                state: FindingsListView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    coverageStatus: StatusMapping.status(for: coverageOutcome),
                    coverageDetail: coverageDetail,
                    findings: state.findings.filter { $0.status == .open && !AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) },
                    nextBestAction: NextBestAction.compute(
                        findings: state.findings,
                        checklistCompletions: state.checklistCompletions,
                        period: state.currentPeriod,
                        hasImportedStatement: state.importedStatementLineCount > 0
                    )
                ),
                onSelect: { finding in state.screen = .detail(findingID: finding.id) },
                onNavigateNextBestAction: { action in
                    switch action {
                    case .reviewHighSeverityFindings: break // already on the list screen
                    case .importBankStatement: state.screen = .bankFeedCleanup
                    case .completeChecklistItem: state.screen = .monthEndClose
                    case .allClear: break
                    }
                }
            )

        case .detail(let findingID):
            if let finding = state.finding(id: findingID) {
                FindingDetailView(
                    finding: finding,
                    writeAccessEnabled: state.writeAccessEnabled == true,
                    isApplyingFix: state.isApplyingFix,
                    applyFixError: state.applyFixError,
                    hasClientMemoryRule: finding.vendorName.map { vendorName in
                        state.clientMemoryRules.contains { $0.matches(ruleID: finding.ruleID, findingVendorName: vendorName) }
                    } ?? false,
                    onStartProcedure: { action in state.screen = .procedure(findingID: findingID, actionID: action.id) },
                    onApplyFix: { Task { await state.applyStagedFix(findingID: findingID, actorName: actorName) } },
                    onSendClientQuestion: { text in Task { await state.recordClientQuestionSent(findingID: findingID, actorName: actorName, questionText: text) } },
                    onRememberVendor: {
                        guard let vendorName = finding.vendorName else { return }
                        Task { await state.createClientMemoryRule(ruleID: finding.ruleID, vendorName: vendorName, actorName: actorName, note: nil) }
                    },
                    onDismiss: { Task { await state.dismissFinding(findingID: findingID, actorName: actorName, reason: nil) } }
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
                reconciliationSummary: state.importedStatementLineCount > 0
                    ? ReconciliationSummary.compute(totalStatementLines: state.importedStatementLineCount, unmatchedFindings: missingPostingFindings)
                    : nil,
                importError: state.importError,
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) },
                onImportTapped: { isImportingStatement = true }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }
            .fileImporter(isPresented: $isImportingStatement, allowedContentTypes: [.commaSeparatedText, .plainText, .data]) { result in
                // A `.failure` here is the user cancelling the panel or an
                // OS-level picker error — nothing to show; `selectFileForImport`
                // itself reports a real read/parse failure via `importError`.
                // `.data` is included so `.ofx`/`.qfx` (no dedicated UTType)
                // still pass the picker's filter; format is then decided by
                // extension inside `selectFileForImport`, not by this filter.
                if case .success(let url) = result {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    state.selectFileForImport(url: url)
                }
            }
            .sheet(isPresented: Binding(get: { state.pendingImport != nil }, set: { if !$0 { state.cancelPendingImport() } })) {
                switch state.pendingImport {
                case .csv(let pending):
                    ImportBankStatementView(
                        filename: pending.filename,
                        columns: Self.columnPreviews(for: pending),
                        suggestedFields: pending.suggestedFields,
                        appliedHint: pending.appliedHint,
                        accounts: state.accounts,
                        onConfirm: { mappings, accountID in Task { await state.confirmCSVImport(mappings: mappings, statementAccountID: accountID) } },
                        onCancel: { state.cancelPendingImport() }
                    )
                case .ofx(let pending):
                    ImportOFXStatementView(
                        filename: pending.filename,
                        transactionCount: pending.transactionCount,
                        statedEndingBalance: pending.statedEndingBalance,
                        statedAsOfDate: pending.statedAsOfDate,
                        accounts: state.accounts,
                        onConfirm: { accountID in Task { await state.confirmOFXImport(statementAccountID: accountID) } },
                        onCancel: { state.cancelPendingImport() }
                    )
                case nil:
                    EmptyView()
                }
            }

        case .monthEndClose:
            MonthEndCloseView(
                environment: state.environment == .production ? .production : .sandbox,
                items: monthEndChecklistItemStates,
                onComplete: { itemID, note in Task { await state.completeChecklistItem(itemID, actorName: actorName, note: note) } },
                onUncomplete: { itemID in Task { await state.uncompleteChecklistItem(itemID) } }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .balanceSheetReport:
            FinancialReportView(
                title: "Balance Sheet",
                sourceDescription: "Read directly from QuickBooks' own Balance Sheet report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.balanceSheetLines,
                isLoading: state.isLoadingBalanceSheet,
                errorMessage: state.balanceSheetError,
                onRefresh: { Task { await state.loadBalanceSheet() } }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .profitAndLossReport:
            FinancialReportView(
                title: "Profit & Loss",
                sourceDescription: "Read directly from QuickBooks' own Profit & Loss report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.profitAndLossLines,
                isLoading: state.isLoadingProfitAndLoss,
                errorMessage: state.profitAndLossError,
                onRefresh: { Task { await state.loadProfitAndLoss() } }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .closePackage:
            ClosePackageView(
                environment: state.environment == .production ? .production : .sandbox,
                period: state.currentPeriod,
                checklistStatus: {
                    let status = MonthEndChecklist.completionStatus(completions: state.checklistCompletions, period: state.currentPeriod)
                    return ClosePackageView.ChecklistStatus(completed: status.completed, total: status.total)
                }(),
                openCleanupFindingsCount: state.findings.filter { $0.status == .open && AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) }.count,
                resolvedCleanupFindingsCount: state.findings.filter { $0.status == .resolved && AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) }.count,
                balanceSheetLines: state.balanceSheetLines,
                profitAndLossLines: state.profitAndLossLines,
                recentActivity: state.activityLog.sorted { $0.recordedAt > $1.recordedAt }
            )
            .task {
                if state.balanceSheetLines.isEmpty { await state.loadBalanceSheet() }
                if state.profitAndLossLines.isEmpty { await state.loadProfitAndLoss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .clientMemory:
            ClientMemoryView(
                environment: state.environment == .production ? .production : .sandbox,
                rules: state.clientMemoryRules,
                onForget: { rule in Task { await state.removeClientMemoryRule(id: rule.id, actorName: actorName) } }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }
        }
    }

    /// Reads each rule's title directly from `RuleIdentity` rather than
    /// duplicating it in a literal table — the table this replaced grew to
    /// 8 hand-maintained entries before becoming the generic lookup its own
    /// comment said to revisit to once the rule count grew past "a couple."
    private var cleanupAssessmentSummaries: [CleanupAssessmentView.RuleSummary] {
        let openFindings = state.findings.filter { $0.status == .open }
        return RuleRegistry.all
            .filter { AppState.cleanupAssessmentRuleIDs.contains($0.identity.id.rawValue) }
            .sorted { $0.identity.id.rawValue < $1.identity.id.rawValue }
            .map { ruleType in
                CleanupAssessmentView.RuleSummary(
                    ruleID: ruleType.identity.id.rawValue,
                    title: ruleType.identity.title,
                    findings: openFindings.filter { $0.ruleID == ruleType.identity.id }
                )
            }
    }

    /// `readyDetail` per item is real, computed from open-`Finding` counts
    /// for the rule sets each checklist step corresponds to — never a
    /// manual guess (`CLAUDE.md` rule 1). Items with no automatic signal
    /// (QBO-side reconciliation, setting the closing date) get `nil`.
    private var monthEndChecklistItemStates: [MonthEndCloseView.ItemState] {
        let completionsForPeriod = state.checklistCompletions.filter { $0.period == state.currentPeriod }
        let completedIDs = Set(completionsForPeriod.map(\.itemID))
        let openFindings = state.findings.filter { $0.status == .open }

        func detail(for ruleIDs: Set<String>) -> String {
            let count = openFindings.filter { ruleIDs.contains($0.ruleID.rawValue) }.count
            return count == 0 ? "No open findings." : "\(count) open finding\(count == 1 ? "" : "s")."
        }

        return MonthEndChecklist.defaultItems.map { item in
            let readyDetail: String?
            switch item.id.rawValue {
            case "resolve-cleanup-assessment":
                readyDetail = detail(for: AppState.cleanupAssessmentRuleIDs)
            case "review-balance-sheet-integrity":
                readyDetail = detail(for: AppState.balanceSheetIntegrityRuleIDs)
            case "review-bank-feed":
                readyDetail = detail(for: ["VL-RECON-MISSING-001", "VL-VENDOR-MISMATCH-001"])
            default:
                readyDetail = nil
            }
            return MonthEndCloseView.ItemState(
                item: item,
                isUnlocked: MonthEndChecklist.isUnlocked(item, completedItemIDs: completedIDs),
                completion: completionsForPeriod.first { $0.itemID == item.id },
                readyDetail: readyDetail
            )
        }
    }

    private var balanceSheetIntegritySummaries: [BalanceSheetIntegrityView.RuleSummary] {
        let openFindings = state.findings.filter { $0.status == .open }
        return RuleRegistry.all
            .filter { AppState.balanceSheetIntegrityRuleIDs.contains($0.identity.id.rawValue) }
            .sorted { $0.identity.id.rawValue < $1.identity.id.rawValue }
            .map { ruleType in
                BalanceSheetIntegrityView.RuleSummary(
                    ruleID: ruleType.identity.id.rawValue,
                    title: ruleType.identity.title,
                    findings: openFindings.filter { $0.ruleID == ruleType.identity.id }
                )
            }
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
    private static func columnPreviews(for pending: AppState.PendingCSVImport) -> [ImportBankStatementView.ColumnPreview] {
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
