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
                        Button("Cash Flow") { state.screen = .cashFlowReport }
                        Button("Trial Balance") { state.screen = .trialBalanceReport }
                        Button("Aged Receivables") { state.screen = .agedReceivablesReport }
                        Button("Aged Payables") { state.screen = .agedPayablesReport }
                        Button("General Ledger") { state.screen = .generalLedgerReport }
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
        .alert("Export Failed", isPresented: Binding(get: { state.exportError != nil }, set: { if !$0 { state.clearExportError() } })) {
            Button("OK") { state.clearExportError() }
        } message: {
            Text(state.exportError ?? "")
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
            ActivityLogView(
                entries: state.activityLog,
                onExport: { format in state.exportTable(Self.exportTable(activityLog: state.activityLog), format: format, suggestedFilename: "Activity Log") }
            )
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
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) },
                onExport: { format in state.exportTable(Self.exportTable(findingSummaries: cleanupAssessmentSummaries), format: format, suggestedFilename: "Cleanup Assessment") }
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
                onRefresh: { Task { await state.loadBalanceSheet() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Balance Sheet", lines: state.balanceSheetLines), format: format, suggestedFilename: "Balance Sheet") }
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
                onRefresh: { Task { await state.loadProfitAndLoss() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Profit & Loss", lines: state.profitAndLossLines), format: format, suggestedFilename: "Profit and Loss") }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .cashFlowReport:
            FinancialReportView(
                title: "Cash Flow",
                sourceDescription: "Read directly from QuickBooks' own Statement of Cash Flows report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.cashFlowLines,
                isLoading: state.isLoadingCashFlow,
                errorMessage: state.cashFlowError,
                onRefresh: { Task { await state.loadCashFlow() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Cash Flow", lines: state.cashFlowLines), format: format, suggestedFilename: "Cash Flow") }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .trialBalanceReport:
            TrialBalanceReportView(
                sourceDescription: "Read directly from QuickBooks' own Trial Balance report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.trialBalanceLines,
                isLoading: state.isLoadingTrialBalance,
                errorMessage: state.trialBalanceError,
                onRefresh: { Task { await state.loadTrialBalance() } },
                onExport: { format in state.exportTable(Self.exportTable(trialBalanceLines: state.trialBalanceLines), format: format, suggestedFilename: "Trial Balance") }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .agedReceivablesReport:
            AgingReportView(
                title: "Aged Receivables",
                rowLabel: "Customer",
                sourceDescription: "Read directly from QuickBooks' own Aged Receivables report, as of today (not period-scoped). Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.agedReceivablesLines,
                isLoading: state.isLoadingAgedReceivables,
                errorMessage: state.agedReceivablesError,
                onRefresh: { Task { await state.loadAgedReceivables() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Aged Receivables", agingLines: state.agedReceivablesLines), format: format, suggestedFilename: "Aged Receivables") }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .agedPayablesReport:
            AgingReportView(
                title: "Aged Payables",
                rowLabel: "Vendor",
                sourceDescription: "Read directly from QuickBooks' own Aged Payables report, as of today (not period-scoped). Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.agedPayablesLines,
                isLoading: state.isLoadingAgedPayables,
                errorMessage: state.agedPayablesError,
                onRefresh: { Task { await state.loadAgedPayables() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Aged Payables", agingLines: state.agedPayablesLines), format: format, suggestedFilename: "Aged Payables") }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .generalLedgerReport:
            GeneralLedgerReportView(
                sourceDescription: "Read directly from QuickBooks' own General Ledger report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.generalLedgerLines,
                isLoading: state.isLoadingGeneralLedger,
                errorMessage: state.generalLedgerError,
                onRefresh: { Task { await state.loadGeneralLedger() } },
                onExport: { format in state.exportTable(Self.exportTable(generalLedgerLines: state.generalLedgerLines), format: format, suggestedFilename: "General Ledger") }
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
                recentActivity: state.activityLog.sorted { $0.recordedAt > $1.recordedAt },
                onExport: { format in
                    let status = MonthEndChecklist.completionStatus(completions: state.checklistCompletions, period: state.currentPeriod)
                    state.exportTable(
                        Self.exportTable(
                            period: state.currentPeriod,
                            checklistCompleted: status.completed,
                            checklistTotal: status.total,
                            openCleanupCount: state.findings.filter { $0.status == .open && AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) }.count,
                            resolvedCleanupCount: state.findings.filter { $0.status == .resolved && AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) }.count,
                            balanceSheetLines: state.balanceSheetLines,
                            profitAndLossLines: state.profitAndLossLines
                        ),
                        format: format,
                        suggestedFilename: "Close Package"
                    )
                }
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

    // MARK: - Export table builders
    //
    // Each report-style page already renders from real, already-computed
    // state (ReportLine, Finding, ActivityLogEntry) — these just reshape
    // that same data into the one generic `ExportTable` shape every format
    // writer consumes, rather than each page inventing its own export path.

    private static func exportTable(title: String, lines: [ReportLine]) -> ExportTable {
        ExportTable(
            title: title,
            columns: ["Label", "Amount"],
            rows: lines.map { line in
                let indent = String(repeating: "    ", count: line.depth)
                let label = indent + line.label + (line.isSummary ? " (Total)" : "")
                return [ExportCell(text: label), ExportCell.money(line.amount)]
            }
        )
    }

    private static func exportTable(trialBalanceLines lines: [TrialBalanceLine]) -> ExportTable {
        ExportTable(
            title: "Trial Balance",
            columns: ["Account", "Debit", "Credit"],
            rows: lines.map { line in
                let label = line.label + (line.isSummary ? " (Total)" : "")
                return [ExportCell(text: label), ExportCell.money(line.debit), ExportCell.money(line.credit)]
            }
        )
    }

    private static func exportTable(title: String, agingLines lines: [AgingLine]) -> ExportTable {
        ExportTable(
            title: title,
            columns: ["Name", "Current", "1-30", "31-60", "61-90", "91+", "Total"],
            rows: lines.map { line in
                let indent = String(repeating: "    ", count: line.depth)
                let label = indent + line.label + (line.isSummary ? " (Total)" : "")
                return [
                    ExportCell(text: label),
                    ExportCell.money(line.current),
                    ExportCell.money(line.days1to30),
                    ExportCell.money(line.days31to60),
                    ExportCell.money(line.days61to90),
                    ExportCell.money(line.days91AndOver),
                    ExportCell.money(line.total)
                ]
            }
        )
    }

    private static func exportTable(generalLedgerLines lines: [GeneralLedgerLine]) -> ExportTable {
        ExportTable(
            title: "General Ledger",
            columns: ["Date/Label", "Type", "Num", "Name", "Memo", "Split", "Amount", "Balance"],
            rows: lines.map { line in
                [
                    ExportCell(text: line.label),
                    ExportCell(text: line.transactionType ?? ""),
                    ExportCell(text: line.docNumber ?? ""),
                    ExportCell(text: line.name ?? ""),
                    ExportCell(text: line.memo ?? ""),
                    ExportCell(text: line.split ?? ""),
                    ExportCell.money(line.amount),
                    ExportCell.money(line.balance)
                ]
            }
        )
    }

    // Gauntlet Loop, Gauntlet B round 4 critic pass (2026-08-23): a fresh
    // critic checked whether a THIRD (and fourth) consumer of `Finding`
    // had also been missed by the finding-detail-screen fixes, beyond
    // `FindingDetailView` and `ClientQuestionDrafter` — and found this one.
    // This export is a TERMINAL artifact (a PDF/XLSX handed to a client or
    // kept as a sales document, per `CLEANUP_MODE.md`'s "doubles as a sales
    // document"), not a clickable in-app row — there is no path back into
    // `FindingDetailView` from the exported file. Two genuinely distinct
    // findings from the same rule, same vendor, same dollar amount but
    // different dates (a real, buildable scenario for VL-DUP-EXP-001) used
    // to render as byte-for-byte identical rows once exported — real,
    // verified by constructing exactly that pair and diffing the two rows.
    // Adding `finding.narrative` (empty string for the 16 rules that don't
    // have one yet, same graceful-degradation pattern used everywhere else
    // this pass) keeps exported rows distinguishable and self-explanatory
    // once they leave the app.
    private static func exportTable(findingSummaries summaries: [CleanupAssessmentView.RuleSummary]) -> ExportTable {
        var rows: [[ExportCell]] = []
        for summary in summaries {
            for finding in summary.findings {
                rows.append([
                    ExportCell(text: summary.title),
                    ExportCell(text: finding.title),
                    ExportCell(text: finding.severity.rawValue.capitalized),
                    ExportCell(text: finding.confidence.rawValue.capitalized),
                    ExportCell.money(finding.dollarExposure),
                    ExportCell(text: finding.narrative ?? "")
                ])
            }
        }
        return ExportTable(title: "Cleanup Assessment", columns: ["Rule", "Finding", "Severity", "Confidence", "Dollar Exposure", "Details"], rows: rows)
    }

    private static func exportTable(activityLog entries: [ActivityLogEntry]) -> ExportTable {
        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()
        let rows = entries.sorted { $0.recordedAt > $1.recordedAt }.map { entry -> [ExportCell] in
            let actor: String
            switch entry.actor {
            case .user(let name): actor = name
            case .system: actor = "Voice Ledger"
            }
            return [
                ExportCell(text: dateFormatter.string(from: entry.recordedAt)),
                ExportCell(text: entry.kind.humanLabel),
                ExportCell(text: actor),
                ExportCell(text: entry.findingSummary ?? ""),
                ExportCell(text: entry.note ?? "")
            ]
        }
        return ExportTable(title: "Activity Log", columns: ["Date", "Kind", "Actor", "Finding", "Note"], rows: rows)
    }

    private static func exportTable(
        period: AccountingPeriod,
        checklistCompleted: Int,
        checklistTotal: Int,
        openCleanupCount: Int,
        resolvedCleanupCount: Int,
        balanceSheetLines: [ReportLine],
        profitAndLossLines: [ReportLine]
    ) -> ExportTable {
        var rows: [[ExportCell]] = [
            [ExportCell(text: "Period"), ExportCell(text: "\(period.year)-\(String(format: "%02d", period.month))"), ExportCell(text: "")],
            [ExportCell(text: "Month-End Checklist"), ExportCell(text: "\(checklistCompleted) of \(checklistTotal) complete"), ExportCell(text: "")],
            [ExportCell(text: "Cleanup Assessment"), ExportCell(text: "\(openCleanupCount) open"), ExportCell(text: "\(resolvedCleanupCount) resolved")]
        ]
        for line in balanceSheetLines where line.isSummary {
            rows.append([ExportCell(text: "Balance Sheet"), ExportCell(text: line.label), ExportCell.money(line.amount)])
        }
        for line in profitAndLossLines where line.isSummary {
            rows.append([ExportCell(text: "Profit & Loss"), ExportCell(text: line.label), ExportCell.money(line.amount)])
        }
        return ExportTable(title: "Close Package", columns: ["Section", "Item", "Value"], rows: rows)
    }
}
