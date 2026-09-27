import SwiftUI
import AppKit
import Core
import IntegrationsQuickBooks
import DesignSystem
import VoiceLedgerUI
import Exporting

struct RootView: View {
    @Bindable var state: AppState
    @State private var actorName = NSFullUserName()
    @State private var isImportingStatement = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    /// A live handle onto the actual, already-rendered NSView backing the
    /// detail column — see `HostViewCaptureAnchor`'s doc comment for why
    /// `exportCurrentPageAsPDF` snapshots THIS rather than re-rendering a
    /// detached second copy of `content`.
    @State private var hostViewBox = HostViewCaptureBox()
    /// Mirrors `VoiceToolLoopPreference.current` (a plain `UserDefaults`
    /// value SwiftUI has no observation hook into) so the Connection
    /// page's radio selection updates immediately on tap, rather than only
    /// on the next unrelated re-render.
    @State private var selectedVoiceToolLoopModel = VoiceToolLoopPreference.current
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AppSidebar(
                selection: sidebarSelection,
                companyName: state.companyInfo?.companyName ?? "No company connected",
                periodLabel: "\(state.currentPeriod.year)-\(String(format: "%02d", state.currentPeriod.month))",
                environmentTone: state.environment == .production ? .production : .sandbox,
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncDashboard() } },
                isVoiceListening: state.voiceEngine.isListening,
                isVoiceProcessing: state.voiceEngine.isProcessing,
                onToggleVoice: { state.voiceEngine.toggleListening() },
                onGoHome: { state.screen = .clientDashboard }
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 300)
        } detail: {
            NavigationStack {
                ContentHostingView(box: hostViewBox, content: content)
            }
        }
        .overlay(alignment: .bottom) {
            // docs/VOICE_LEDGER_SPEC.md's `/voice` module — one global
            // control, not per-page, since a bookkeeper navigates between
            // pages while talking.
            if state.voiceEngine.isListening || state.voiceEngine.isProcessing || state.voiceEngine.isSpeaking
                || state.voiceEngine.lastMessage != nil || state.voiceEngine.errorMessage != nil {
                VoiceStatusPanel(
                    isListening: state.voiceEngine.isListening,
                    isSpeaking: state.voiceEngine.isSpeaking,
                    micLevel: state.voiceEngine.micLevel,
                    transcript: state.voiceEngine.transcript,
                    lastMessage: state.voiceEngine.lastMessage,
                    errorMessage: state.voiceEngine.errorMessage,
                    onStop: { state.voiceEngine.stopSpeaking() },
                    onDismiss: { state.voiceEngine.dismissStatus() }
                )
                .padding(.bottom, VLSpacing.md)
            }
        }
        .task {
            await state.loadFromDiskOnly()
            await state.checkHealth()
            await state.checkAIStatus()
            await state.voiceEngine.loadPersistedContext()
        }
        .alert("Export Failed", isPresented: Binding(get: { state.exportError != nil }, set: { if !$0 { state.clearExportError() } })) {
            Button("OK") { state.clearExportError() }
        } message: {
            Text(state.exportError ?? "")
        }
        // Owner-facing (2026-09-06): the voice assistant's chart-popup
        // capability (`VoiceUIAction.presentChart`) — global, not
        // per-page, matching the voice status panel above: a chart can be
        // requested from any screen.
        .sheet(isPresented: Binding(get: { state.presentedChart != nil }, set: { if !$0 { state.presentedChart = nil } })) {
            if let request = state.presentedChart {
                ChartPopupView(request: request) { state.presentedChart = nil }
            }
        }
        // Owner-reported bug (2026-09-06): a macOS `.sheet` doesn't offer a
        // resize grip regardless of frame flexibility. Comparing findings —
        // "pull up two transactions... side by side," later "shouldn't be
        // just limited to 2" — now opens a real `Window` scene instead
        // (declared in `VoiceLedgerApp.body`), which gets genuine
        // resizability and native traffic-light controls for free. This
        // view only needs to open/close that window as `comparedFindingIDs`
        // transitions to/from empty; the window's own content reads
        // `state` directly (see `VoiceLedgerApp.swift`).
        .onChange(of: state.comparedFindingIDs.isEmpty) { _, isEmpty in
            if isEmpty {
                dismissWindow(id: VoiceLedgerApp.comparisonWindowID)
            } else {
                openWindow(id: VoiceLedgerApp.comparisonWindowID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportCurrentPageAsPDF)) { _ in
            exportCurrentPageAsPDF()
        }
    }

    /// File > "Export Page as PDF…". Snapshots the ACTUAL, already-
    /// rendered NSView backing `content` (via `hostViewBox`, populated by
    /// `HostViewCaptureAnchor`) into PDF `Data` using AppKit's own
    /// `-dataWithPDF(inside:)`, then hands the bytes to
    /// `AppState.savePDFData` — the same `NSSavePanel` path every other
    /// export in this app already goes through.
    ///
    /// **Why not `ImageRenderer` (tried first, reverted):** `ImageRenderer`
    /// builds and lays out a SECOND, DETACHED copy of `content` outside the
    /// real window. Several of this app's pages nest their own
    /// `ScrollView`/`GeometryReader` (sized relative to their real
    /// surrounding window), and a detached copy of those can collapse to
    /// zero size when laid out standalone — live-reported result: an
    /// exported PDF that was solid black (the page's own dark background,
    /// painted correctly) with nothing else on it (the actual content,
    /// collapsed to nothing). Snapshotting the view that's already
    /// correctly laid out and on screen has no such problem.
    ///
    /// Scope, stated honestly: this captures the page as it's actually
    /// laid out on screen right now, at its current on-screen size — not
    /// an unbounded "print the whole scrollable history" capture. A long
    /// list further down a `ScrollView` than the current window shows
    /// isn't included, the same way a Cmd-P print of a single-page view
    /// wouldn't be. Resize the window before exporting for a page whose
    /// content is currently clipped. And because SwiftUI views on macOS
    /// are layer-backed, `-dataWithPDF(inside:)` rasterizes what it
    /// captures into the PDF rather than preserving selectable vector
    /// text — a real trade-off against the (broken) vector attempt above,
    /// not a hidden regression.
    @MainActor
    private func exportCurrentPageAsPDF() {
        guard let hostView = hostViewBox.view, hostView.bounds.width > 0, hostView.bounds.height > 0 else {
            state.reportPDFExportFailure("Nothing to export yet — try again once the page has finished loading.")
            return
        }
        let data = hostView.dataWithPDF(inside: hostView.bounds)
        guard !data.isEmpty else {
            state.reportPDFExportFailure("Could not render this page to PDF.")
            return
        }
        state.savePDFData(data, suggestedFilename: currentPageTitle)
    }

    /// The current page's human-readable name, for the export's suggested
    /// filename — reuses `SidebarItem.title`, the same label already shown
    /// in the sidebar for this screen, rather than inventing a second name
    /// for the same page.
    private var currentPageTitle: String {
        sidebarSelection.wrappedValue?.title ?? "Voice Ledger Page"
    }

    /// Bridges `AppState.screen` (the real navigation state, including the
    /// two parameterized drill-down cases `.detail`/`.procedure`) to
    /// `SidebarItem?` (the sidebar's flat, top-level selection). Reading it
    /// while a finding is open maps back to `.findings` so "Findings"
    /// stays highlighted, the same way a Finder sidebar row stays selected
    /// while you're looking inside something it contains. Setting it always
    /// replaces `state.screen` outright — the sidebar is the one navigation
    /// surface that always starts a fresh top-level screen, never a
    /// drill-down.
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(
            get: {
                switch state.screen {
                case .clientDashboard: return .dashboard
                case .connection: return .connection
                case .scopeAndPeriodLock: return .scopeAndPeriodLock
                case .list, .detail, .procedure: return .findings
                case .batchFixes: return .batchFixes
                case .firmCockpit: return .firmCockpit
                case .taxes: return .taxes
                case .salesTaxReview: return .salesTaxReview
                case .chartOfAccountsCleanup: return .chartOfAccountsCleanup
                case .cleanupAssessment: return .cleanupAssessment
                case .balanceSheetIntegrity: return .balanceSheetIntegrity
                case .bankFeedCleanup: return .bankFeedCleanup
                case .monthEndClose: return .monthEndClose
                case .activityLog: return .activityLog
                case .closePackage: return .closePackage
                case .clientMemory: return .clientMemory
                case .voiceHistory: return .voiceHistory
                case .balanceSheetReport: return .balanceSheetReport
                case .profitAndLossReport: return .profitAndLossReport
                case .cashFlowReport: return .cashFlowReport
                case .trialBalanceReport: return .trialBalanceReport
                case .agedReceivablesReport: return .agedReceivablesReport
                case .agedPayablesReport: return .agedPayablesReport
                case .generalLedgerReport: return .generalLedgerReport
                case .amountSearch: return .amountSearch
                case .pricingCalculator: return .pricingCalculator
                case .audioSettings: return .audioSettings
                case .cashFlowForecast: return .cashFlowForecast
                case .recurringVendors: return .recurringVendors
                }
            },
            set: { newValue in
                guard let newValue else { return }
                switch newValue {
                case .dashboard: state.screen = .clientDashboard
                case .findings: state.screen = .list
                case .connection: state.screen = .connection
                case .scopeAndPeriodLock: state.screen = .scopeAndPeriodLock
                case .batchFixes: state.screen = .batchFixes
                case .firmCockpit: state.screen = .firmCockpit
                case .taxes: state.screen = .taxes
                case .salesTaxReview: state.screen = .salesTaxReview
                case .chartOfAccountsCleanup: state.screen = .chartOfAccountsCleanup
                case .cleanupAssessment: state.screen = .cleanupAssessment
                case .balanceSheetIntegrity: state.screen = .balanceSheetIntegrity
                case .bankFeedCleanup: state.screen = .bankFeedCleanup
                case .monthEndClose: state.screen = .monthEndClose
                case .activityLog: state.screen = .activityLog
                case .closePackage: state.screen = .closePackage
                case .clientMemory: state.screen = .clientMemory
                case .voiceHistory: state.screen = .voiceHistory
                case .balanceSheetReport: state.screen = .balanceSheetReport
                case .profitAndLossReport: state.screen = .profitAndLossReport
                case .cashFlowReport: state.screen = .cashFlowReport
                case .trialBalanceReport: state.screen = .trialBalanceReport
                case .agedReceivablesReport: state.screen = .agedReceivablesReport
                case .agedPayablesReport: state.screen = .agedPayablesReport
                case .generalLedgerReport: state.screen = .generalLedgerReport
                case .amountSearch: state.screen = .amountSearch
                case .pricingCalculator: state.screen = .pricingCalculator
                case .audioSettings: state.screen = .audioSettings
                case .cashFlowForecast: state.screen = .cashFlowForecast
                case .recurringVendors: state.screen = .recurringVendors
                }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch state.screen {
        case .clientDashboard:
            let dashboardOpenFindings = state.findings.filter { $0.status == .open }
            let dashboardTopFindings = Array(FindingTriage.sorted(dashboardOpenFindings).prefix(5))
            let dashboardAskAIKey = "page:client-dashboard"
            let dashboardContext = {
                var lines = ["Open findings: \(dashboardOpenFindings.count)"]
                if let workingCapital = FinancialKPIs.workingCapital(from: state.balanceSheetLines) {
                    lines.append("Working capital: \(workingCapital.description)")
                }
                if let netIncome = TaxEstimate.netIncome(from: state.profitAndLossLines) {
                    lines.append("Net income: \(netIncome.description)")
                }
                return AskAIContext.compose(pageTitle: "Client Dashboard", findings: dashboardTopFindings) + "\n" + lines.joined(separator: "\n") + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            }
            ClientDashboardView(
                state: ClientDashboardView.ViewState(
                    companyName: state.companyInfo?.companyName ?? "No company connected",
                    environment: state.environment == .production ? .production : .sandbox,
                    coverageStatus: StatusMapping.status(for: coverageOutcome),
                    coverageDetail: coverageDetail,
                    balanceSheetLines: state.balanceSheetLines,
                    profitAndLossLines: state.profitAndLossLines,
                    isLoadingReports: state.isLoadingBalanceSheet || state.isLoadingProfitAndLoss,
                    priorBalanceSheetLines: state.priorPeriodBalanceSheetLines,
                    priorProfitAndLossLines: state.priorPeriodProfitAndLossLines,
                    agedReceivablesLines: state.agedReceivablesLines,
                    agedPayablesLines: state.agedPayablesLines,
                    topVendors: VendorSpendSummary.top(5, from: state.transactions),
                    monthEndChecklistProgress: {
                        let progress = MonthEndChecklist.completionStatus(completions: state.checklistCompletions, period: state.currentPeriod)
                        return progress.total > 0 ? progress : nil
                    }(),
                    period: state.currentPeriod,
                    cashFlowForecast: state.cashFlowForecast,
                    missingRecurringVendorsCount: state.missingRecurringVendors.count,
                    topFindings: dashboardTopFindings,
                    openFindingsCount: dashboardOpenFindings.count
                ),
                onOpenFinding: { finding in state.screen = .detail(findingID: finding.id) },
                onViewAllFindings: { state.screen = .list },
                onViewMonthEndClose: { state.screen = .monthEndClose },
                onNavigateToReport: { destination in
                    switch destination {
                    case .balanceSheet: state.screen = .balanceSheetReport
                    case .profitAndLoss: state.screen = .profitAndLossReport
                    case .agedReceivables: state.screen = .agedReceivablesReport
                    case .agedPayables: state.screen = .agedPayablesReport
                    case .cashFlowForecast: state.screen = .cashFlowForecast
                    case .recurringVendors: state.screen = .recurringVendors
                    }
                },
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncDashboard() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[dashboardAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(dashboardAskAIKey),
                askAIError: state.askAIError?.contextKey == dashboardAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: dashboardAskAIKey, contextText: dashboardContext(), question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[dashboardAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(dashboardAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == dashboardAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: dashboardAskAIKey, contextText: dashboardContext(), question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(dashboardAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(dashboardAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(dashboardAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(dashboardAskAIKey)-qwen", contextText: dashboardContext(), question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(dashboardAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(dashboardAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(dashboardAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(dashboardAskAIKey)-claude", contextText: dashboardContext(), question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.balanceSheetLines.isEmpty { await state.loadBalanceSheet() }
                if state.profitAndLossLines.isEmpty { await state.loadProfitAndLoss() }
                if state.agedReceivablesLines.isEmpty { await state.loadAgedReceivables() }
                if state.agedPayablesLines.isEmpty { await state.loadAgedPayables() }
                if state.priorPeriodBalanceSheetLines.isEmpty || state.priorPeriodProfitAndLossLines.isEmpty { await state.loadVarianceAnalysis() }
                if state.trailingPurchases.isEmpty { await state.loadTrailingPurchases() }
            }

        case .connection:
            ConnectionView(
                state: ConnectionView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    companyName: state.companyInfo?.companyName,
                    realmID: state.companyInfo?.realmID.rawValue ?? "(not yet checked)",
                    healthStatus: state.healthResult.map { Self.vlStatus(for: $0.status) },
                    healthDetail: state.healthCheckError ?? state.healthResult.map { "\($0.status.rawValue) — \($0.latencyMs)ms" },
                    lastCheckedAt: state.healthResult?.checkedAt,
                    refreshTokenExpiresAt: state.healthResult?.refreshTokenExpiresAt,
                    isChecking: state.isCheckingHealth,
                    writeEnabled: state.writeAccessEnabled,
                    isTogglingWriteAccess: state.isTogglingWriteAccess,
                    aiStatus: state.aiStatus,
                    isCheckingAIStatus: state.isCheckingAIStatus,
                    isTogglingAIEnabled: state.isTogglingAIEnabled,
                    aiStatusError: state.aiStatusError,
                    voiceAssistantModelOptions: VoiceToolLoopModel.allCases.map { model in
                        ConnectionView.VoiceModelOption(
                            id: model.rawValue,
                            label: model.displayName,
                            isAvailable: model == .gemma || state.aiStatus?.anthropicConfigured == true
                        )
                    },
                    selectedVoiceAssistantModelID: selectedVoiceToolLoopModel.rawValue
                ),
                onCheckHealth: { Task { await state.checkHealth() } },
                onToggleWriteAccess: { enabled in Task { await state.setWriteAccess(enabled) } },
                onToggleAIEnabled: { enabled in Task { await state.setAIEnabled(enabled) } },
                onSelectVoiceAssistantModel: { modelID in
                    guard let model = VoiceToolLoopModel(rawValue: modelID) else { return }
                    VoiceToolLoopPreference.current = model
                    selectedVoiceToolLoopModel = model
                }
            )

        case .batchFixes:
            let batchFixesAskAIKey = "page:batch-fixes"
            let batchFixItems = BatchFixPlan.preview(findings: state.stagedFixFindings)
            BatchFixesView(
                environment: state.environment == .production ? .production : .sandbox,
                writeAccessEnabled: state.writeAccessEnabled == true,
                items: batchFixItems,
                selectedIDs: state.batchFixSelection,
                applyingFindingIDs: state.applyingFixFindingIDs,
                applyFixError: state.applyFixError,
                isApplyingBatch: state.isApplyingBatchFix,
                onToggleSelection: { findingID in state.toggleBatchFixSelection(findingID) },
                onSelectAll: { state.selectAllBatchFix() },
                onDeselectAll: { state.deselectAllBatchFix() },
                onApplyBatch: {
                    let ids = Array(state.batchFixSelection)
                    Task { await state.applyBatchFix(findingIDs: ids, actorName: actorName) }
                },
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[batchFixesAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(batchFixesAskAIKey),
                askAIError: state.askAIError?.contextKey == batchFixesAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    let context = AskAIContext.compose(pageTitle: "Batch Fixes", summaryLines: batchFixItems.map { "\($0.findingTitle): \($0.currentAccountName) → \($0.suggestedAccountName), \($0.dollarExposure.description)" }) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
                    Task { await state.askAI(contextKey: batchFixesAskAIKey, contextText: context, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[batchFixesAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(batchFixesAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == batchFixesAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    let context = AskAIContext.compose(pageTitle: "Batch Fixes", summaryLines: batchFixItems.map { "\($0.findingTitle): \($0.currentAccountName) → \($0.suggestedAccountName), \($0.dollarExposure.description)" }) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
                    Task { await state.askSecondOpinion(contextKey: batchFixesAskAIKey, contextText: context, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(batchFixesAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(batchFixesAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(batchFixesAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Batch Fixes", summaryLines: batchFixItems.map { "\($0.findingTitle): \($0.currentAccountName) → \($0.suggestedAccountName), \($0.dollarExposure.description)" }) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
                        Task { await state.askAI(contextKey: "\(batchFixesAskAIKey)-qwen", contextText: context, question: question, model: "qwen3:8b") }
                    }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(batchFixesAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(batchFixesAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(batchFixesAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Batch Fixes", summaryLines: batchFixItems.map { "\($0.findingTitle): \($0.currentAccountName) → \($0.suggestedAccountName), \($0.dollarExposure.description)" }) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
                        Task { await state.askAI(contextKey: "\(batchFixesAskAIKey)-claude", contextText: context, question: question, model: "claude-haiku-4-5") }
                    }
                ) : nil
                ].compactMap { $0 }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .firmCockpit:
            let firmCockpitAskAIKey = "page:firm-cockpit"
            let firmCockpitContext = AskAIContext.compose(
                pageTitle: "Firm Cockpit",
                summaryLines: state.firmCockpitSummaries.map { summary in
                    "\(summary.client.companyName ?? "(unnamed)"): \(summary.openFindingsCount) open findings, \(summary.urgentFindingsCount) urgent, checklist \(summary.checklistCompleted)/\(summary.checklistTotal)"
                }
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            FirmCockpitView(
                environment: state.environment == .production ? .production : .sandbox,
                summaries: state.firmCockpitSummaries,
                isLoading: state.isLoadingFirmCockpit,
                errorMessage: state.firmCockpitError,
                currentRealmID: state.currentRealmID.rawValue,
                isSwitchingClient: state.isSwitchingClient,
                switchClientError: state.switchClientError,
                onRefresh: { Task { await state.loadFirmCockpit() } },
                onSwitchToClient: { client in
                    Task { await state.switchActiveClient(to: client.realmID, environment: client.environment) }
                },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[firmCockpitAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(firmCockpitAskAIKey),
                askAIError: state.askAIError?.contextKey == firmCockpitAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: firmCockpitAskAIKey, contextText: firmCockpitContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[firmCockpitAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(firmCockpitAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == firmCockpitAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: firmCockpitAskAIKey, contextText: firmCockpitContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(firmCockpitAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(firmCockpitAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(firmCockpitAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(firmCockpitAskAIKey)-qwen", contextText: firmCockpitContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(firmCockpitAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(firmCockpitAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(firmCockpitAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(firmCockpitAskAIKey)-claude", contextText: firmCockpitContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.firmCockpitSummaries.isEmpty { await state.loadFirmCockpit() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .taxes:
            let taxesAskAIKey = "page:taxes"
            let taxesContext = {
                var lines = ["Current period (\(Self.periodLabel(state.currentPeriod))) net income: \(TaxEstimate.netIncome(from: state.profitAndLossLines)?.description ?? "not loaded")"]
                lines.append("Prior period (\(Self.periodLabel(state.currentPeriod.previousMonth))) net income: \(TaxEstimate.netIncome(from: state.priorPeriodProfitAndLossLines)?.description ?? "not loaded")")
                if let rate = state.taxEstimateSettings.ratePercent {
                    lines.append("Bookkeeper-provided rate: \(rate)%")
                    if let setAside = TaxEstimate.estimatedSetAside(netIncome: TaxEstimate.netIncome(from: state.profitAndLossLines), ratePercent: rate) {
                        lines.append("Illustrative set-aside at that rate: \(setAside.description)")
                    }
                }
                return AskAIContext.compose(pageTitle: "Taxes", summaryLines: lines) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            }
            TaxesView(
                environment: state.environment == .production ? .production : .sandbox,
                currentPeriodLabel: Self.periodLabel(state.currentPeriod),
                priorPeriodLabel: Self.periodLabel(state.currentPeriod.previousMonth),
                currentNetIncome: TaxEstimate.netIncome(from: state.profitAndLossLines),
                priorNetIncome: TaxEstimate.netIncome(from: state.priorPeriodProfitAndLossLines),
                isLoading: state.isLoadingProfitAndLoss || state.isLoadingVarianceAnalysis,
                errorMessage: state.profitAndLossError ?? state.varianceAnalysisError,
                settings: state.taxEstimateSettings,
                onRefresh: {
                    Task {
                        await state.loadProfitAndLoss()
                        await state.loadVarianceAnalysis()
                    }
                },
                onSaveSettings: { settings in Task { await state.updateTaxEstimateSettings(settings) } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[taxesAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(taxesAskAIKey),
                askAIError: state.askAIError?.contextKey == taxesAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: taxesAskAIKey, contextText: taxesContext(), question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[taxesAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(taxesAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == taxesAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: taxesAskAIKey, contextText: taxesContext(), question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(taxesAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(taxesAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(taxesAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(taxesAskAIKey)-qwen", contextText: taxesContext(), question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(taxesAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(taxesAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(taxesAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(taxesAskAIKey)-claude", contextText: taxesContext(), question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.profitAndLossLines.isEmpty { await state.loadProfitAndLoss() }
                if state.priorPeriodProfitAndLossLines.isEmpty { await state.loadVarianceAnalysis() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .salesTaxReview:
            let salesTaxAskAIKey = "page:sales-tax-review"
            let salesTaxContext = {
                var lines = state.taxAgencies.map { "Agency: \($0.displayName)" }
                lines += state.taxRates.map { "Rate: \($0.name), \($0.ratePercent.map { String(format: "%.2f%%", $0) } ?? "—"), active: \($0.isActive)" }
                lines += state.taxCodes.map { "Code: \($0.name), taxable: \($0.taxable.map(String.init) ?? "unknown")" }
                return AskAIContext.compose(pageTitle: "Sales Tax Review", summaryLines: lines) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            }
            SalesTaxReviewView(
                environment: state.environment == .production ? .production : .sandbox,
                taxCodes: state.taxCodes,
                taxRates: state.taxRates,
                taxAgencies: state.taxAgencies,
                isLoading: state.isLoadingSalesTax,
                errorMessage: state.salesTaxError,
                attestation: state.salesTaxAttestation,
                onRefresh: { Task { await state.loadSalesTaxProfile() } },
                onSaveAttestation: { attestation in Task { await state.updateSalesTaxAttestation(attestation) } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[salesTaxAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(salesTaxAskAIKey),
                askAIError: state.askAIError?.contextKey == salesTaxAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: salesTaxAskAIKey, contextText: salesTaxContext(), question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[salesTaxAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(salesTaxAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == salesTaxAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: salesTaxAskAIKey, contextText: salesTaxContext(), question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(salesTaxAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(salesTaxAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(salesTaxAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(salesTaxAskAIKey)-qwen", contextText: salesTaxContext(), question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(salesTaxAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(salesTaxAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(salesTaxAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(salesTaxAskAIKey)-claude", contextText: salesTaxContext(), question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .chartOfAccountsCleanup:
            let chartOfAccountsAskAIKey = "page:chart-of-accounts-cleanup"
            let duplicateGroups = ChartOfAccountsCleanup.findDuplicateCandidates(state.accounts)
            let chartOfAccountsContext = AskAIContext.compose(
                pageTitle: "Chart of Accounts Cleanup",
                summaryLines: duplicateGroups.map { group in
                    "Candidate group: " + group.accounts.map(\.name).joined(separator: ", ")
                }
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            ChartOfAccountsCleanupView(
                state: ChartOfAccountsCleanupView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    totalAccountsCount: state.accounts.count,
                    accountsWithFullyQualifiedNameCount: state.accounts.filter { $0.fullyQualifiedName != nil }.count,
                    groups: duplicateGroups
                ),
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[chartOfAccountsAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(chartOfAccountsAskAIKey),
                askAIError: state.askAIError?.contextKey == chartOfAccountsAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: chartOfAccountsAskAIKey, contextText: chartOfAccountsContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[chartOfAccountsAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(chartOfAccountsAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == chartOfAccountsAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: chartOfAccountsAskAIKey, contextText: chartOfAccountsContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(chartOfAccountsAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(chartOfAccountsAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(chartOfAccountsAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(chartOfAccountsAskAIKey)-qwen", contextText: chartOfAccountsContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(chartOfAccountsAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(chartOfAccountsAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(chartOfAccountsAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(chartOfAccountsAskAIKey)-claude", contextText: chartOfAccountsContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )

        case .scopeAndPeriodLock:
            ScopeAndPeriodLockView(
                state: ScopeAndPeriodLockView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    servicesIncluded: state.engagementScope.servicesIncluded,
                    qboaAccountantAccessAttested: state.engagementScope.qboaAccountantAccessAttested,
                    attestedBy: state.engagementScope.attestedBy,
                    attestedAt: state.engagementScope.attestedAt,
                    currentPeriod: state.currentPeriod,
                    periodLock: state.periodLock,
                    transactionsInLockedPeriod: state.periodLock.map { lock in
                        PeriodLockCheck.transactionsInLockedPeriod(state.transactions, lock: lock)
                    } ?? []
                ),
                onToggleService: { service in
                    var scope = state.engagementScope
                    if scope.servicesIncluded.contains(service) {
                        scope.servicesIncluded.remove(service)
                    } else {
                        scope.servicesIncluded.insert(service)
                    }
                    Task { await state.updateEngagementScope(scope) }
                },
                onAttest: { actorName in
                    var scope = state.engagementScope
                    scope.qboaAccountantAccessAttested = true
                    scope.attestedBy = actorName
                    scope.attestedAt = Date()
                    Task { await state.updateEngagementScope(scope) }
                },
                onSetLock: { through, note in
                    Task { await state.setPeriodLock(through: through, actorName: actorName, note: note) }
                },
                onClearLock: { Task { await state.clearPeriodLock() } }
            )

        case .list:
            VStack(spacing: 0) {
                // The dashboard's own voice entry point — the owner's own
                // ask ("voice button on the dashboard"), placed where a
                // bookkeeper's eye lands first, above the findings the
                // moment the app opens. `AppSidebar`'s footer offers the
                // same action from every other screen; this one is just
                // more prominent, matching where the reference screenshot
                // put its own "Start a conversation" affordance.
                DashboardVoiceBanner(
                    isListening: state.voiceEngine.isListening,
                    isProcessing: state.voiceEngine.isProcessing,
                    onToggle: { state.voiceEngine.toggleListening() }
                )
                .padding(.horizontal, VLSpacing.pageGutter)
                .padding(.top, VLSpacing.md)

                // Owner-facing (2026-09-06): "in case the mic system is
                // down at some point, there should be a harness on the
                // dashboard for me to ask questions and make commands
                // just as powerful as by voice." Calls the exact same
                // `VoiceEngine.handleTypedCommand` pipeline a spoken turn
                // goes through (router match, tool-calling fallback,
                // navigate/open/chart, spoken reply) — the only thing
                // skipped is speech-to-text.
                TypedCommandHarness(
                    isProcessing: state.voiceEngine.isProcessing,
                    lastMessage: state.voiceEngine.lastMessage,
                    onSubmit: { text in Task { await state.voiceEngine.handleTypedCommand(text) } }
                )
                .padding(.horizontal, VLSpacing.pageGutter)
                .padding(.top, VLSpacing.sm)

                FindingsListView(
                    state: FindingsListView.ViewState(
                        environment: state.environment == .production ? .production : .sandbox,
                        coverageStatus: StatusMapping.status(for: coverageOutcome),
                        coverageDetail: coverageDetail,
                        // Owner directive (2026-08-29): Findings is the one
                        // screen used with "an eagle eye" for every red flag
                        // — it must never silently exclude a category of
                        // open finding just because that category ALSO has
                        // its own focused workflow page (Cleanup Assessment,
                        // Balance Sheet Integrity). Previously excluded
                        // every `cleanupAssessmentRuleIDs` finding (21 of the
                        // ~29 registered rules) from this list entirely —
                        // real discrepancies were only visible if the owner
                        // separately remembered to open those other pages.
                        // Cleanup Assessment/Balance Sheet Integrity keep
                        // their own filtered views below (harmless overlap,
                        // not a source of truth conflict — both read the
                        // same `state.findings`).
                        findings: FindingTriage.sorted(state.findings.filter { $0.status == .open }),
                        nextBestAction: NextBestAction.compute(
                            findings: state.findings,
                            checklistCompletions: state.checklistCompletions,
                            period: state.currentPeriod,
                            hasImportedStatement: state.importedStatementLineCount > 0
                        ),
                        syncError: {
                            if case .failed(let message) = state.loadState { return message }
                            return nil
                        }(),
                        healthReportAnswer: state.askAIAnswers[AppState.healthReportContextKey],
                        isGeneratingHealthReport: state.askingAIContextKeys.contains(AppState.healthReportContextKey),
                        healthReportError: state.askAIError?.contextKey == AppState.healthReportContextKey ? state.askAIError?.message : nil,
                        healthReportSecondOpinionAnswer: state.secondOpinionAnswers[AppState.healthReportContextKey],
                        isGeneratingHealthReportSecondOpinion: state.askingSecondOpinionContextKeys.contains(AppState.healthReportContextKey),
                        healthReportSecondOpinionError: state.secondOpinionError?.contextKey == AppState.healthReportContextKey ? state.secondOpinionError?.message : nil,
                        secondOpinionConfigured: state.aiStatus?.secondaryConfigured ?? false,
                        valueSummaryAnswer: state.askAIAnswers[AppState.valueSummaryContextKey],
                        isGeneratingValueSummary: state.askingAIContextKeys.contains(AppState.valueSummaryContextKey),
                        valueSummaryError: state.askAIError?.contextKey == AppState.valueSummaryContextKey ? state.askAIError?.message : nil,
                        valueSummarySecondOpinionAnswer: state.secondOpinionAnswers[AppState.valueSummaryContextKey],
                        isGeneratingValueSummarySecondOpinion: state.askingSecondOpinionContextKeys.contains(AppState.valueSummaryContextKey),
                        valueSummarySecondOpinionError: state.secondOpinionError?.contextKey == AppState.valueSummaryContextKey ? state.secondOpinionError?.message : nil,
                        claudeConfigured: state.aiStatus?.anthropicConfigured ?? false,
                        healthReportClaudeAnswer: state.askAIAnswers["\(AppState.healthReportContextKey)-claude"],
                        isGeneratingHealthReportClaude: state.askingAIContextKeys.contains("\(AppState.healthReportContextKey)-claude"),
                        healthReportClaudeError: state.askAIError?.contextKey == "\(AppState.healthReportContextKey)-claude" ? state.askAIError?.message : nil,
                        valueSummaryClaudeAnswer: state.askAIAnswers["\(AppState.valueSummaryContextKey)-claude"],
                        isGeneratingValueSummaryClaude: state.askingAIContextKeys.contains("\(AppState.valueSummaryContextKey)-claude"),
                        valueSummaryClaudeError: state.askAIError?.contextKey == "\(AppState.valueSummaryContextKey)-claude" ? state.askAIError?.message : nil
                    ),
                    onSelect: { finding in state.screen = .detail(findingID: finding.id) },
                    onNavigateNextBestAction: { action in
                        switch action {
                        case .reviewHighSeverityFindings: break // already on the list screen
                        case .importBankStatement: state.screen = .bankFeedCleanup
                        case .completeChecklistItem: state.screen = .monthEndClose
                        case .allClear: break
                        }
                    },
                    onRefresh: { Task { await state.syncAndEvaluate() } },
                    isRefreshing: state.loadState == .loading,
                    onGenerateHealthReport: { Task { await state.generateHealthReport() } },
                    onGenerateHealthReportSecondOpinion: { Task { await state.generateHealthReportSecondOpinion() } },
                    onGenerateValueSummary: { Task { await state.generateValueSummary() } },
                    onGenerateValueSummarySecondOpinion: { Task { await state.generateValueSummarySecondOpinion() } },
                    onExportHealthReportPDF: {
                        guard let answer = state.askAIAnswers[AppState.healthReportContextKey] else { return }
                        state.exportAIReportPDF(reportTitle: "Book Health Report", providerLabel: "Gemma (local, free)", bodyText: answer, suggestedFilename: "Book Health Report")
                    },
                    onExportHealthReportSecondOpinionPDF: {
                        guard let answer = state.secondOpinionAnswers[AppState.healthReportContextKey] else { return }
                        state.exportAIReportPDF(reportTitle: "Book Health Report", providerLabel: "OpenAI", bodyText: answer, suggestedFilename: "Book Health Report (OpenAI)")
                    },
                    onExportValueSummaryPDF: {
                        guard let answer = state.askAIAnswers[AppState.valueSummaryContextKey] else { return }
                        state.exportAIReportPDF(reportTitle: "Client Value Summary", providerLabel: "Gemma (local, free)", bodyText: answer, suggestedFilename: "Client Value Summary")
                    },
                    onExportValueSummarySecondOpinionPDF: {
                        guard let answer = state.secondOpinionAnswers[AppState.valueSummaryContextKey] else { return }
                        state.exportAIReportPDF(reportTitle: "Client Value Summary", providerLabel: "OpenAI", bodyText: answer, suggestedFilename: "Client Value Summary (OpenAI)")
                    },
                    onExportHealthReportClaudePDF: {
                        guard let answer = state.askAIAnswers["\(AppState.healthReportContextKey)-claude"] else { return }
                        state.exportAIReportPDF(reportTitle: "Book Health Report", providerLabel: "Claude Haiku 4.5", bodyText: answer, suggestedFilename: "Book Health Report (Claude)")
                    },
                    onExportValueSummaryClaudePDF: {
                        guard let answer = state.askAIAnswers["\(AppState.valueSummaryContextKey)-claude"] else { return }
                        state.exportAIReportPDF(reportTitle: "Client Value Summary", providerLabel: "Claude Haiku 4.5", bodyText: answer, suggestedFilename: "Client Value Summary (Claude)")
                    },
                    onAskHealthReportFollowUp: { question in Task { await state.askHealthReportFollowUp(question) } },
                    onAskHealthReportFollowUpSecondOpinion: { question in Task { await state.askHealthReportFollowUpSecondOpinion(question) } },
                    onAskValueSummaryFollowUp: { question in Task { await state.askValueSummaryFollowUp(question) } },
                    onAskValueSummaryFollowUpSecondOpinion: { question in Task { await state.askValueSummaryFollowUpSecondOpinion(question) } },
                    onGenerateHealthReportClaude: { Task { await state.generateHealthReportClaude() } },
                    onGenerateValueSummaryClaude: { Task { await state.generateValueSummaryClaude() } },
                    onAskHealthReportFollowUpClaude: { question in Task { await state.askHealthReportFollowUpClaude(question) } },
                    onAskValueSummaryFollowUpClaude: { question in Task { await state.askValueSummaryFollowUpClaude(question) } },
                    onCompareSelected: { ids in state.comparedFindingIDs = ids }
                )
            }

        case .detail(let findingID):
            if let finding = state.finding(id: findingID) {
                // Extracted to local `let`s (2026-08-29) — the compiler
                // started timing out type-checking the giant
                // `FindingDetailView(...)` call below once `onMarkDone`
                // gained a parameter; these two closures were the most
                // deeply-nested expressions in that call and splitting
                // them out is enough to bring it back under the type
                // checker's time limit, with no behavior change.
                let pendingWriteJournalEntry: WriteJournalEntry? = finding.proposedActions.first?.apiWriteDetails.flatMap { details -> WriteJournalEntry? in
                    let journalID = "\(details.purchaseID):\(details.lineID)"
                    for entry in state.writeJournal {
                        let isPending = entry.state == .submitted || entry.state == .unknown
                        if entry.id == journalID && isPending {
                            return entry
                        }
                    }
                    return nil
                }
                let isResolvingPendingWrite: Bool = finding.proposedActions.first?.apiWriteDetails.map { details in
                    state.isResolvingWriteJournalEntryIDs.contains("\(details.purchaseID):\(details.lineID)")
                } ?? false
                // Same type-checker-timeout reasoning as the two lets
                // above — added 2026-08-31 once `clientMessageAnswer`/etc
                // pushed this call over the limit again.
                let clientMessageContextKey = "client-message:\(findingID)"
                let clientMessageAnswer = state.askAIAnswers[clientMessageContextKey]
                let isDraftingClientMessage = state.askingAIContextKeys.contains(clientMessageContextKey)
                let clientMessageError = state.askAIError?.contextKey == clientMessageContextKey ? state.askAIError?.message : nil
                FindingDetailView(
                    finding: finding,
                    writeAccessEnabled: state.writeAccessEnabled == true,
                    isApplyingFix: state.applyingFixFindingIDs.contains(findingID),
                    applyFixError: state.applyFixError?.findingID == findingID ? state.applyFixError?.message : nil,
                    findingActionError: state.findingActionError?.findingID == findingID ? state.findingActionError?.message : nil,
                    isFindingActionInFlight: state.findingActionInFlightIDs.contains(findingID),
                    hasClientMemoryRule: finding.vendorName.map { vendorName in
                        state.clientMemoryRules.contains { $0.matches(ruleID: finding.ruleID, findingVendorName: vendorName) }
                    } ?? false,
                    carryForwardMark: state.carryForwardMarks.first { $0.findingID == findingID },
                    justAttestedStillOpen: state.attestationOutcome?.findingID == findingID && state.attestationOutcome?.stillOpen == true,
                    onStartProcedure: { action in state.screen = .procedure(findingID: findingID, actionID: action.id) },
                    onApplyFix: { Task { await state.applyStagedFix(findingID: findingID, actorName: actorName) } },
                    onSendClientQuestion: { text in Task { await state.recordClientQuestionSent(findingID: findingID, actorName: actorName, questionText: text) } },
                    lastSentClientQuestion: state.activityLog
                        .filter { $0.findingID == findingID && $0.kind == .clientQuestionDrafted }
                        .max(by: { $0.recordedAt < $1.recordedAt })?.note,
                    clientQuestionAnswer: state.activityLog
                        .filter { $0.findingID == findingID && $0.kind == .clientQuestionAnswered }
                        .max(by: { $0.recordedAt < $1.recordedAt })?.note,
                    onRecordClientQuestionAnswer: { text in Task { await state.recordClientQuestionAnswer(findingID: findingID, actorName: actorName, answerText: text) } },
                    pendingWriteJournalEntry: pendingWriteJournalEntry,
                    isResolvingPendingWrite: isResolvingPendingWrite,
                    onResolvePendingWrite: {
                        if let journalID = finding.proposedActions.first?.apiWriteDetails.map({ "\($0.purchaseID):\($0.lineID)" }) {
                            Task { await state.resolvePendingWrite(journalEntryID: journalID, actorName: actorName) }
                        }
                    },
                    onRememberVendor: {
                        guard let vendorName = finding.vendorName else { return }
                        Task { await state.createClientMemoryRule(ruleID: finding.ruleID, vendorName: vendorName, actorName: actorName, note: nil, triggeringFindingID: findingID) }
                    },
                    onDismiss: { Task { await state.dismissFinding(findingID: findingID, actorName: actorName, reason: nil) } },
                    onMarkDone: { note in Task { await state.attestCompletion(findingID: findingID, actorName: actorName, note: note) } },
                    onMarkCarriedForward: { reason in Task { await state.markFindingCarriedForward(findingID: findingID, actorName: actorName, reason: reason) } },
                    onUnmarkCarriedForward: { Task { await state.unmarkCarriedForward(findingID: findingID, actorName: actorName) } },
                    aiStatus: state.aiStatus,
                    askAIAnswer: state.askAIAnswers[findingID],
                    isAskingAI: state.askingAIContextKeys.contains(findingID),
                    askAIError: state.askAIError?.contextKey == findingID ? state.askAIError?.message : nil,
                    onAskAI: { question in Task { await state.askAI(findingID: findingID, question: question) } },
                    secondOpinionAnswer: state.secondOpinionAnswers[findingID],
                    isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(findingID),
                    secondOpinionError: state.secondOpinionError?.contextKey == findingID ? state.secondOpinionError?.message : nil,
                    onAskSecondOpinion: { question in Task { await state.askSecondOpinion(findingID: findingID, question: question) } },
                    secondOpinionConfigured: state.aiStatus?.secondaryConfigured ?? false,
                    clientMessageAnswer: clientMessageAnswer,
                    isDraftingClientMessage: isDraftingClientMessage,
                    clientMessageError: clientMessageError,
                    onDraftClientMessage: { question in Task { await state.draftClientMessage(findingID: findingID, question: question) } },
                    onBack: { state.screen = .list }
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
                    attestError: state.findingActionError?.findingID == findingID ? state.findingActionError?.message : nil,
                    isAttesting: state.findingActionInFlightIDs.contains(findingID),
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
            let activityLogAskAIKey = "page:activity-log"
            let activityLogContext = AskAIContext.compose(
                pageTitle: "Activity & Correction Log",
                summaryLines: state.activityLog.sorted { $0.recordedAt > $1.recordedAt }.prefix(60).map {
                    "\($0.recordedAt.formatted(date: .abbreviated, time: .shortened)) — \($0.kind.humanLabel)\($0.findingSummary.map { s in ": \(s)" } ?? "") (\($0.actor.displayLabel))"
                }
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            ActivityLogView(
                entries: state.activityLog,
                onExport: { format in state.exportTable(Self.exportTable(activityLog: state.activityLog), format: format, suggestedFilename: "Activity Log") },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[activityLogAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(activityLogAskAIKey),
                askAIError: state.askAIError?.contextKey == activityLogAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: activityLogAskAIKey, contextText: activityLogContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[activityLogAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(activityLogAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == activityLogAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: activityLogAskAIKey, contextText: activityLogContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(activityLogAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(activityLogAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(activityLogAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(activityLogAskAIKey)-qwen", contextText: activityLogContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(activityLogAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(activityLogAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(activityLogAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(activityLogAskAIKey)-claude", contextText: activityLogContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { state.screen = .list }
                    }
                }

        case .cleanupAssessment:
            let cleanupAssessmentAskAIKey = "page:cleanup-assessment"
            CleanupAssessmentView(
                environment: state.environment == .production ? .production : .sandbox,
                coverageStatus: StatusMapping.status(for: coverageOutcome),
                coverageDetail: coverageDetail,
                summaries: cleanupAssessmentSummaries,
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) },
                onExport: { format in state.exportTable(Self.exportTable(findingSummaries: cleanupAssessmentSummaries), format: format, suggestedFilename: "Cleanup Assessment") },
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[cleanupAssessmentAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(cleanupAssessmentAskAIKey),
                askAIError: state.askAIError?.contextKey == cleanupAssessmentAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    let context = AskAIContext.compose(pageTitle: "Cleanup Assessment", findings: cleanupAssessmentSummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) })
                    Task { await state.askAI(contextKey: cleanupAssessmentAskAIKey, contextText: context, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[cleanupAssessmentAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(cleanupAssessmentAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == cleanupAssessmentAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    let context = AskAIContext.compose(pageTitle: "Cleanup Assessment", findings: cleanupAssessmentSummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) })
                    Task { await state.askSecondOpinion(contextKey: cleanupAssessmentAskAIKey, contextText: context, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(cleanupAssessmentAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(cleanupAssessmentAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(cleanupAssessmentAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Cleanup Assessment", findings: cleanupAssessmentSummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) })
                        Task { await state.askAI(contextKey: "\(cleanupAssessmentAskAIKey)-qwen", contextText: context, question: question, model: "qwen3:8b") }
                    }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(cleanupAssessmentAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(cleanupAssessmentAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(cleanupAssessmentAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Cleanup Assessment", findings: cleanupAssessmentSummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) })
                        Task { await state.askAI(contextKey: "\(cleanupAssessmentAskAIKey)-claude", contextText: context, question: question, model: "claude-haiku-4-5") }
                    }
                ) : nil
                ].compactMap { $0 }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .balanceSheetIntegrity:
            let balanceSheetIntegrityAskAIKey = "page:balance-sheet-integrity"
            BalanceSheetIntegrityView(
                environment: state.environment == .production ? .production : .sandbox,
                coverageStatus: StatusMapping.status(for: coverageOutcome),
                coverageDetail: coverageDetail,
                summaries: balanceSheetIntegritySummaries,
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) },
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[balanceSheetIntegrityAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(balanceSheetIntegrityAskAIKey),
                askAIError: state.askAIError?.contextKey == balanceSheetIntegrityAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    let context = AskAIContext.compose(pageTitle: "Balance Sheet Integrity", findings: balanceSheetIntegritySummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.balanceSheetIntegrityRuleIDs.contains($0.ruleID.rawValue) })
                    Task { await state.askAI(contextKey: balanceSheetIntegrityAskAIKey, contextText: context, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[balanceSheetIntegrityAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(balanceSheetIntegrityAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == balanceSheetIntegrityAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    let context = AskAIContext.compose(pageTitle: "Balance Sheet Integrity", findings: balanceSheetIntegritySummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.balanceSheetIntegrityRuleIDs.contains($0.ruleID.rawValue) })
                    Task { await state.askSecondOpinion(contextKey: balanceSheetIntegrityAskAIKey, contextText: context, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(balanceSheetIntegrityAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(balanceSheetIntegrityAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(balanceSheetIntegrityAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Balance Sheet Integrity", findings: balanceSheetIntegritySummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.balanceSheetIntegrityRuleIDs.contains($0.ruleID.rawValue) })
                        Task { await state.askAI(contextKey: "\(balanceSheetIntegrityAskAIKey)-qwen", contextText: context, question: question, model: "qwen3:8b") }
                    }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(balanceSheetIntegrityAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(balanceSheetIntegrityAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(balanceSheetIntegrityAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Balance Sheet Integrity", findings: balanceSheetIntegritySummaries.flatMap(\.findings)) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open && !AppState.balanceSheetIntegrityRuleIDs.contains($0.ruleID.rawValue) })
                        Task { await state.askAI(contextKey: "\(balanceSheetIntegrityAskAIKey)-claude", contextText: context, question: question, model: "claude-haiku-4-5") }
                    }
                ) : nil
                ].compactMap { $0 }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .bankFeedCleanup:
            let missingPostingFindings = state.findings.filter { $0.status == .open && $0.ruleID.rawValue == "VL-RECON-MISSING-001" }
            let ambiguousMatchFindings = state.findings.filter { $0.status == .open && $0.ruleID.rawValue == "VL-RECON-AMBIGUOUS-001" }
            // VL-RECON-DIFF-001 (2026-09-11 bug fix): this rule's own
            // findings were computed and stored like every other rule, but
            // this page never filtered for them or rendered a section — a
            // real balance-drift finding existed and was silently invisible
            // here, the exact false-negative CLAUDE.md rule 5 exists to
            // prevent.
            let driftFindings = state.findings.filter { $0.status == .open && $0.ruleID.rawValue == "VL-RECON-DIFF-001" }
            // Owner-visible bug, same date: `coverageStatus` collapsed
            // "zero findings" to `.notChecked` unconditionally, and the
            // detail text was a hardcoded "nothing imported yet" literal —
            // both false the moment a real statement WAS imported and came
            // back clean. Honest three-way split: nothing imported yet
            // (gray/notChecked), imported and clean (green/verified),
            // imported with findings (yellow/reviewNeeded) — CLAUDE.md rule
            // 5's "a rule returning zero findings is not sufficient, unless
            // the data was actually there" applied correctly instead of
            // being read backwards.
            let missingPostingCoverageStatus: VLStatus = state.importedStatementLineCount == 0
                ? .notChecked
                : (missingPostingFindings.isEmpty ? .verified : .reviewNeeded)
            let missingPostingDetail: String = {
                if state.importedStatementLineCount == 0 {
                    return "No statement imported for this period. Import a bank/card statement to run this check (docs/VOICE_LEDGER_SPEC.md Page 4)."
                }
                if missingPostingFindings.isEmpty {
                    return "No missing postings found against \(state.importedStatementLineCount) imported statement line(s)."
                }
                return "\(missingPostingFindings.count) of \(state.importedStatementLineCount) imported statement line(s) don't match anything posted in QuickBooks."
            }()
            let bankFeedCleanupAskAIKey = "page:bank-feed-cleanup"
            BankFeedCleanupView(
                environment: state.environment == .production ? .production : .sandbox,
                coverageStatus: missingPostingCoverageStatus,
                missingPostingOutcomeDetail: missingPostingDetail,
                findings: missingPostingFindings,
                ambiguousFindings: ambiguousMatchFindings,
                driftFindings: driftFindings,
                reconciliationSummary: state.importedStatementLineCount > 0
                    ? ReconciliationSummary.compute(totalStatementLines: state.importedStatementLineCount, unmatchedFindings: missingPostingFindings, ambiguousFindings: ambiguousMatchFindings)
                    : nil,
                importError: state.importError,
                onSelectFinding: { finding in state.screen = .detail(findingID: finding.id) },
                onImportTapped: { isImportingStatement = true },
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[bankFeedCleanupAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(bankFeedCleanupAskAIKey),
                askAIError: state.askAIError?.contextKey == bankFeedCleanupAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    let context = AskAIContext.compose(pageTitle: "Bank Feed Cleanup", findings: missingPostingFindings + ambiguousMatchFindings + driftFindings) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { finding in finding.status == .open && !(missingPostingFindings + ambiguousMatchFindings + driftFindings).contains(finding) })
                    Task { await state.askAI(contextKey: bankFeedCleanupAskAIKey, contextText: context, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[bankFeedCleanupAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(bankFeedCleanupAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == bankFeedCleanupAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    let context = AskAIContext.compose(pageTitle: "Bank Feed Cleanup", findings: missingPostingFindings + ambiguousMatchFindings + driftFindings) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { finding in finding.status == .open && !(missingPostingFindings + ambiguousMatchFindings + driftFindings).contains(finding) })
                    Task { await state.askSecondOpinion(contextKey: bankFeedCleanupAskAIKey, contextText: context, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(bankFeedCleanupAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(bankFeedCleanupAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(bankFeedCleanupAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Bank Feed Cleanup", findings: missingPostingFindings + ambiguousMatchFindings + driftFindings) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { finding in finding.status == .open && !(missingPostingFindings + ambiguousMatchFindings + driftFindings).contains(finding) })
                        Task { await state.askAI(contextKey: "\(bankFeedCleanupAskAIKey)-qwen", contextText: context, question: question, model: "qwen3:8b") }
                    }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(bankFeedCleanupAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(bankFeedCleanupAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(bankFeedCleanupAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in
                        let context = AskAIContext.compose(pageTitle: "Bank Feed Cleanup", findings: missingPostingFindings + ambiguousMatchFindings + driftFindings) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { finding in finding.status == .open && !(missingPostingFindings + ambiguousMatchFindings + driftFindings).contains(finding) })
                        Task { await state.askAI(contextKey: "\(bankFeedCleanupAskAIKey)-claude", contextText: context, question: question, model: "claude-haiku-4-5") }
                    }
                ) : nil
                ].compactMap { $0 }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }
            .fileImporter(isPresented: $isImportingStatement, allowedContentTypes: [.commaSeparatedText, .plainText, .data, .pdf, .png, .jpeg, .heic]) { result in
                // A `.failure` here is the user cancelling the panel or an
                // OS-level picker error — nothing to show; `selectFileForImport`
                // itself reports a real read/parse failure via `importError`.
                // `.data` is included so `.ofx`/`.qfx` (no dedicated UTType)
                // still pass the picker's filter; format is then decided by
                // extension inside `selectFileForImport`, not by this filter.
                // `.pdf`/`.png`/`.jpeg`/`.heic` are Universal Ingestion Tier
                // 2 (OCR) — same "decide by extension inside
                // selectFileForImport" posture.
                if case .success(let url) = result {
                    // The security-scoped session must stay open for the
                    // FULL async operation, not just this synchronous
                    // closure — `defer` inside the `Task` below fires when
                    // the async work finishes, not when this closure
                    // returns immediately after scheduling it.
                    Task {
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        await state.selectFileForImport(url: url)
                    }
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
                        isConfirming: state.isConfirmingImport,
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
                        isConfirming: state.isConfirmingImport,
                        onConfirm: { accountID in Task { await state.confirmOFXImport(statementAccountID: accountID) } },
                        onCancel: { state.cancelPendingImport() }
                    )
                case nil:
                    EmptyView()
                }
            }

        case .monthEndClose:
            let monthEndCloseAskAIKey = "page:month-end-close"
            let monthEndCloseContext = AskAIContext.compose(
                pageTitle: "Month-End Close",
                summaryLines: monthEndChecklistItemStates.map { itemState in
                    "\(itemState.item.title): \(itemState.completion != nil ? "completed" : "not completed")" + (itemState.openFindingsCount.map { " (\($0) open findings)" } ?? "")
                }
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            MonthEndCloseView(
                environment: state.environment == .production ? .production : .sandbox,
                items: monthEndChecklistItemStates,
                onComplete: { itemID, note in Task { await state.completeChecklistItem(itemID, actorName: actorName, note: note) } },
                onUncomplete: { itemID in Task { await state.uncompleteChecklistItem(itemID) } },
                onReviewFindings: { itemID in
                    switch itemID.rawValue {
                    case "resolve-cleanup-assessment": state.screen = .cleanupAssessment
                    case "review-balance-sheet-integrity": state.screen = .balanceSheetIntegrity
                    case "review-bank-feed": state.screen = .bankFeedCleanup
                    default: break
                    }
                },
                carryForwardItems: state.carryForwardMarks.compactMap { mark in
                    guard let finding = state.finding(id: mark.findingID) else { return nil }
                    return (mark: mark, findingTitle: finding.title, dollarExposure: finding.dollarExposure)
                },
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[monthEndCloseAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(monthEndCloseAskAIKey),
                askAIError: state.askAIError?.contextKey == monthEndCloseAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: monthEndCloseAskAIKey, contextText: monthEndCloseContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[monthEndCloseAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(monthEndCloseAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == monthEndCloseAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: monthEndCloseAskAIKey, contextText: monthEndCloseContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(monthEndCloseAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(monthEndCloseAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(monthEndCloseAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(monthEndCloseAskAIKey)-qwen", contextText: monthEndCloseContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(monthEndCloseAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(monthEndCloseAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(monthEndCloseAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(monthEndCloseAskAIKey)-claude", contextText: monthEndCloseContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .balanceSheetReport:
            let balanceSheetReportAskAIKey = "page:balance-sheet-report"
            let balanceSheetReportContext = AskAIContext.compose(pageTitle: "Balance Sheet", summaryLines: state.balanceSheetLines.filter(\.isSummary).map { "\($0.label): \($0.amount?.description ?? "—")" }) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            BalanceSheetReportView(
                sourceDescription: "Read directly from QuickBooks' own Balance Sheet report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.balanceSheetLines,
                isLoading: state.isLoadingBalanceSheet,
                errorMessage: state.balanceSheetError,
                onRefresh: { Task { await state.loadBalanceSheet() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Balance Sheet", lines: state.balanceSheetLines), format: format, suggestedFilename: "Balance Sheet") },
                priorPeriodLines: state.priorPeriodBalanceSheetLines,
                priorPeriodLabel: Self.periodLabel(state.currentPeriod.previousMonth),
                isLoadingVariance: state.isLoadingVarianceAnalysis,
                varianceError: state.varianceAnalysisError,
                onLoadVariance: { Task { await state.loadVarianceAnalysis() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[balanceSheetReportAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(balanceSheetReportAskAIKey),
                askAIError: state.askAIError?.contextKey == balanceSheetReportAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: balanceSheetReportAskAIKey, contextText: balanceSheetReportContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[balanceSheetReportAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(balanceSheetReportAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == balanceSheetReportAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: balanceSheetReportAskAIKey, contextText: balanceSheetReportContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(balanceSheetReportAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(balanceSheetReportAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(balanceSheetReportAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(balanceSheetReportAskAIKey)-qwen", contextText: balanceSheetReportContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(balanceSheetReportAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(balanceSheetReportAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(balanceSheetReportAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(balanceSheetReportAskAIKey)-claude", contextText: balanceSheetReportContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                // Owner directive (2026-08-30): "why should i have to click
                // on sections and then have to press refresh and wait" —
                // auto-load on first visit this session, same pattern
                // Close Package already used, so navigating here doesn't
                // require a manual Refresh click before there's anything
                // to look at. Guarded on `isEmpty`, not re-fetched on every
                // visit, so returning to an already-loaded page doesn't
                // repeat the API call for no reason.
                if state.balanceSheetLines.isEmpty { await state.loadBalanceSheet() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .profitAndLossReport:
            let profitAndLossReportAskAIKey = "page:profit-and-loss-report"
            let profitAndLossReportContext = AskAIContext.compose(pageTitle: "Profit & Loss", summaryLines: state.profitAndLossLines.filter(\.isSummary).map { "\($0.label): \($0.amount?.description ?? "—")" }) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            ProfitAndLossReportView(
                sourceDescription: "Read directly from QuickBooks' own Profit & Loss report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.profitAndLossLines,
                isLoading: state.isLoadingProfitAndLoss,
                errorMessage: state.profitAndLossError,
                onRefresh: { Task { await state.loadProfitAndLoss() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Profit & Loss", lines: state.profitAndLossLines), format: format, suggestedFilename: "Profit and Loss") },
                priorPeriodLines: state.priorPeriodProfitAndLossLines,
                priorPeriodLabel: Self.periodLabel(state.currentPeriod.previousMonth),
                isLoadingVariance: state.isLoadingVarianceAnalysis,
                varianceError: state.varianceAnalysisError,
                onLoadVariance: { Task { await state.loadVarianceAnalysis() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[profitAndLossReportAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(profitAndLossReportAskAIKey),
                askAIError: state.askAIError?.contextKey == profitAndLossReportAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: profitAndLossReportAskAIKey, contextText: profitAndLossReportContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[profitAndLossReportAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(profitAndLossReportAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == profitAndLossReportAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: profitAndLossReportAskAIKey, contextText: profitAndLossReportContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(profitAndLossReportAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(profitAndLossReportAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(profitAndLossReportAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(profitAndLossReportAskAIKey)-qwen", contextText: profitAndLossReportContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(profitAndLossReportAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(profitAndLossReportAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(profitAndLossReportAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(profitAndLossReportAskAIKey)-claude", contextText: profitAndLossReportContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.profitAndLossLines.isEmpty { await state.loadProfitAndLoss() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .cashFlowReport:
            let cashFlowReportAskAIKey = "page:cash-flow-report"
            let cashFlowReportContext = AskAIContext.compose(pageTitle: "Cash Flow", summaryLines: state.cashFlowLines.filter(\.isSummary).map { "\($0.label): \($0.amount?.description ?? "—")" }) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            FinancialReportView(
                title: "Cash Flow",
                sourceDescription: "Read directly from QuickBooks' own Statement of Cash Flows report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.cashFlowLines,
                isLoading: state.isLoadingCashFlow,
                errorMessage: state.cashFlowError,
                onRefresh: { Task { await state.loadCashFlow() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Cash Flow", lines: state.cashFlowLines), format: format, suggestedFilename: "Cash Flow") },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[cashFlowReportAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(cashFlowReportAskAIKey),
                askAIError: state.askAIError?.contextKey == cashFlowReportAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: cashFlowReportAskAIKey, contextText: cashFlowReportContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[cashFlowReportAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(cashFlowReportAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == cashFlowReportAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: cashFlowReportAskAIKey, contextText: cashFlowReportContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(cashFlowReportAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(cashFlowReportAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(cashFlowReportAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(cashFlowReportAskAIKey)-qwen", contextText: cashFlowReportContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(cashFlowReportAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(cashFlowReportAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(cashFlowReportAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(cashFlowReportAskAIKey)-claude", contextText: cashFlowReportContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.cashFlowLines.isEmpty { await state.loadCashFlow() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .trialBalanceReport:
            let trialBalanceAskAIKey = "page:trial-balance-report"
            // Owner directive (2026-08-31): summarize account totals rather
            // than blindly cap-and-drop when there are more accounts than
            // reasonably fit an Ask AI context — see
            // `AskAIContext.summarizeAccountTotals`'s doc comment. A full
            // Trial Balance (every account, not just summary rows) is
            // exactly the "more accounts than fit" case this exists for.
            let trialBalanceContext = AskAIContext.compose(
                pageTitle: "Trial Balance",
                summaryLines: AskAIContext.summarizeAccountTotals(state.trialBalanceLines.map { line in
                    (
                        text: "\(line.label): debit \(line.debit?.description ?? "—"), credit \(line.credit?.description ?? "—")",
                        amount: line.debit ?? line.credit ?? Money(minorUnits: 0, currency: .usd)
                    )
                })
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            TrialBalanceReportView(
                sourceDescription: "Read directly from QuickBooks' own Trial Balance report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.trialBalanceLines,
                isLoading: state.isLoadingTrialBalance,
                errorMessage: state.trialBalanceError,
                onRefresh: { Task { await state.loadTrialBalance() } },
                onExport: { format in state.exportTable(Self.exportTable(trialBalanceLines: state.trialBalanceLines), format: format, suggestedFilename: "Trial Balance") },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[trialBalanceAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(trialBalanceAskAIKey),
                askAIError: state.askAIError?.contextKey == trialBalanceAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: trialBalanceAskAIKey, contextText: trialBalanceContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[trialBalanceAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(trialBalanceAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == trialBalanceAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: trialBalanceAskAIKey, contextText: trialBalanceContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(trialBalanceAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(trialBalanceAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(trialBalanceAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(trialBalanceAskAIKey)-qwen", contextText: trialBalanceContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(trialBalanceAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(trialBalanceAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(trialBalanceAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(trialBalanceAskAIKey)-claude", contextText: trialBalanceContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.trialBalanceLines.isEmpty { await state.loadTrialBalance() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .agedReceivablesReport:
            let agedReceivablesAskAIKey = "page:aged-receivables"
            let agedReceivablesContext = AskAIContext.compose(
                pageTitle: "Aged Receivables",
                summaryLines: AskAIContext.summarizeAccountTotals(state.agedReceivablesLines.map { line in
                    (text: "\(line.label): total \(line.total?.description ?? "—")", amount: line.total ?? Money(minorUnits: 0, currency: .usd))
                })
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            AgingReportView(
                title: "Aged Receivables",
                rowLabel: "Customer",
                sourceDescription: "Read directly from QuickBooks' own Aged Receivables report, as of today (not period-scoped). Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.agedReceivablesLines,
                isLoading: state.isLoadingAgedReceivables,
                errorMessage: state.agedReceivablesError,
                onRefresh: { Task { await state.loadAgedReceivables() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Aged Receivables", agingLines: state.agedReceivablesLines), format: format, suggestedFilename: "Aged Receivables") },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[agedReceivablesAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(agedReceivablesAskAIKey),
                askAIError: state.askAIError?.contextKey == agedReceivablesAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: agedReceivablesAskAIKey, contextText: agedReceivablesContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[agedReceivablesAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(agedReceivablesAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == agedReceivablesAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: agedReceivablesAskAIKey, contextText: agedReceivablesContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(agedReceivablesAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(agedReceivablesAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(agedReceivablesAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(agedReceivablesAskAIKey)-qwen", contextText: agedReceivablesContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(agedReceivablesAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(agedReceivablesAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(agedReceivablesAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(agedReceivablesAskAIKey)-claude", contextText: agedReceivablesContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.agedReceivablesLines.isEmpty { await state.loadAgedReceivables() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .agedPayablesReport:
            let agedPayablesAskAIKey = "page:aged-payables"
            let agedPayablesContext = AskAIContext.compose(
                pageTitle: "Aged Payables",
                summaryLines: AskAIContext.summarizeAccountTotals(state.agedPayablesLines.map { line in
                    (text: "\(line.label): total \(line.total?.description ?? "—")", amount: line.total ?? Money(minorUnits: 0, currency: .usd))
                })
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            AgingReportView(
                title: "Aged Payables",
                rowLabel: "Vendor",
                sourceDescription: "Read directly from QuickBooks' own Aged Payables report, as of today (not period-scoped). Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.agedPayablesLines,
                isLoading: state.isLoadingAgedPayables,
                errorMessage: state.agedPayablesError,
                onRefresh: { Task { await state.loadAgedPayables() } },
                onExport: { format in state.exportTable(Self.exportTable(title: "Aged Payables", agingLines: state.agedPayablesLines), format: format, suggestedFilename: "Aged Payables") },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[agedPayablesAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(agedPayablesAskAIKey),
                askAIError: state.askAIError?.contextKey == agedPayablesAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: agedPayablesAskAIKey, contextText: agedPayablesContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[agedPayablesAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(agedPayablesAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == agedPayablesAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: agedPayablesAskAIKey, contextText: agedPayablesContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(agedPayablesAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(agedPayablesAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(agedPayablesAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(agedPayablesAskAIKey)-qwen", contextText: agedPayablesContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(agedPayablesAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(agedPayablesAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(agedPayablesAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(agedPayablesAskAIKey)-claude", contextText: agedPayablesContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.agedPayablesLines.isEmpty { await state.loadAgedPayables() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .generalLedgerReport:
            let generalLedgerAskAIKey = "page:general-ledger-report"
            let generalLedgerContext = AskAIContext.compose(
                pageTitle: "General Ledger",
                summaryLines: AskAIContext.summarizeAccountTotals(state.generalLedgerLines.filter(\.isSummary).map { line in
                    (
                        text: "\(line.label): \(line.amount?.description ?? "—"), balance \(line.balance?.description ?? "—")",
                        amount: line.balance ?? line.amount ?? Money(minorUnits: 0, currency: .usd)
                    )
                })
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            GeneralLedgerReportView(
                sourceDescription: "Read directly from QuickBooks' own General Ledger report for the synced period. Not a branded client-ready document — see the Close Package page for a consolidated summary.",
                environment: state.environment == .production ? .production : .sandbox,
                lines: state.generalLedgerLines,
                isLoading: state.isLoadingGeneralLedger,
                errorMessage: state.generalLedgerError,
                onRefresh: { Task { await state.loadGeneralLedger() } },
                onExport: { format in state.exportTable(Self.exportTable(generalLedgerLines: state.generalLedgerLines), format: format, suggestedFilename: "General Ledger") },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[generalLedgerAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(generalLedgerAskAIKey),
                askAIError: state.askAIError?.contextKey == generalLedgerAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: generalLedgerAskAIKey, contextText: generalLedgerContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[generalLedgerAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(generalLedgerAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == generalLedgerAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: generalLedgerAskAIKey, contextText: generalLedgerContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(generalLedgerAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(generalLedgerAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(generalLedgerAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(generalLedgerAskAIKey)-qwen", contextText: generalLedgerContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(generalLedgerAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(generalLedgerAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(generalLedgerAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(generalLedgerAskAIKey)-claude", contextText: generalLedgerContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.generalLedgerLines.isEmpty { await state.loadGeneralLedger() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .closePackage:
            let closePackageAskAIKey = "page:close-package"
            let closePackageContext = {
                var lines = state.balanceSheetLines.filter(\.isSummary).map { "Balance Sheet — \($0.label): \($0.amount?.description ?? "—")" }
                lines += state.profitAndLossLines.filter(\.isSummary).map { "P&L — \($0.label): \($0.amount?.description ?? "—")" }
                lines += state.cashFlowLines.filter(\.isSummary).map { "Cash Flow — \($0.label): \($0.amount?.description ?? "—")" }
                return AskAIContext.compose(pageTitle: "Close Package", summaryLines: lines) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            }
            // Owner directive (2026-08-31): "a narrated summary in the
            // Close Package PDF" — a distinct contextKey/prompt from the
            // page's general Q&A panel above, so a random follow-up
            // question never becomes what silently ends up in an exported
            // client PDF.
            let closePackageSummaryAskAIKey = "close-package-summary"
            let closePackageSummaryPrompt = "Write a short executive summary (2-4 sentences) of this close package for the client, in plain non-technical language: overall health, anything open worth noting, and what's already been handled this period."
            // Extracted to a local `let` (2026-09-07) — inlined directly in
            // the `ClosePackageView(...)` call below, the type checker
            // couldn't finish checking this expression in reasonable time
            // once a second (Claude) alternate tier was added alongside
            // Qwen3's.
            let closePackageAlternateModelTiers: [TwoTierAskAIPanel.AlternateModelTier] = [
                .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(closePackageAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(closePackageAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(closePackageAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(closePackageAskAIKey)-qwen", contextText: closePackageContext(), question: question, model: "qwen3:8b") } }
                ),
                state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(closePackageAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(closePackageAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(closePackageAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(closePackageAskAIKey)-claude", contextText: closePackageContext(), question: question, model: "claude-haiku-4-5") } }
                ) : nil
            ].compactMap { $0 }
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
                cashFlowLines: state.cashFlowLines,
                trialBalanceLines: state.trialBalanceLines,
                agedReceivablesLines: state.agedReceivablesLines,
                agedPayablesLines: state.agedPayablesLines,
                recentActivity: state.activityLog.sorted { $0.recordedAt > $1.recordedAt },
                carryForwardItems: state.carryForwardMarks.compactMap { mark in
                    guard let finding = state.finding(id: mark.findingID) else { return nil }
                    return (mark: mark, findingTitle: finding.title, dollarExposure: finding.dollarExposure)
                },
                clientQuestionThreads: ClientQuestionDrafter.threads(from: state.activityLog),
                conversationHistory: state.conversationHistory.sorted { $0.askedAt > $1.askedAt },
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
                            profitAndLossLines: state.profitAndLossLines,
                            cashFlowLines: state.cashFlowLines,
                            trialBalanceLines: state.trialBalanceLines,
                            agedReceivablesLines: state.agedReceivablesLines,
                            agedPayablesLines: state.agedPayablesLines
                        ),
                        format: format,
                        suggestedFilename: "Close Package"
                    )
                },
                onExportBrandedPDF: { executiveSummary in
                    let status = MonthEndChecklist.completionStatus(completions: state.checklistCompletions, period: state.currentPeriod)
                    let input = ClosePackagePDFExporter.Input(
                        companyName: state.companyInfo?.companyName,
                        environment: state.environment == .production ? "production" : "sandbox",
                        period: state.currentPeriod,
                        checklistCompleted: status.completed,
                        checklistTotal: status.total,
                        openCleanupCount: state.findings.filter { $0.status == .open && AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) }.count,
                        resolvedCleanupCount: state.findings.filter { $0.status == .resolved && AppState.cleanupAssessmentRuleIDs.contains($0.ruleID.rawValue) }.count,
                        balanceSheetLines: state.balanceSheetLines,
                        profitAndLossLines: state.profitAndLossLines,
                        cashFlowLines: state.cashFlowLines,
                        trialBalanceLines: state.trialBalanceLines,
                        agedReceivablesLines: state.agedReceivablesLines,
                        agedPayablesLines: state.agedPayablesLines,
                        corrections: state.activityLog.filter { $0.kind.isCorrection }.sorted { $0.recordedAt > $1.recordedAt },
                        carryForwardItems: state.carryForwardMarks.compactMap { mark in
                            guard let finding = state.finding(id: mark.findingID) else { return nil }
                            return (mark: mark, findingTitle: finding.title, dollarExposure: finding.dollarExposure)
                        },
                        clientQuestionThreads: ClientQuestionDrafter.threads(from: state.activityLog),
                        conversationHistory: state.conversationHistory.sorted { $0.askedAt > $1.askedAt },
                        recentActivity: state.activityLog.sorted { $0.recordedAt > $1.recordedAt },
                        executiveSummary: executiveSummary
                    )
                    state.exportClosePackagePDF(input)
                },
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[closePackageAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(closePackageAskAIKey),
                askAIError: state.askAIError?.contextKey == closePackageAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: closePackageAskAIKey, contextText: closePackageContext(), question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[closePackageAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(closePackageAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == closePackageAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: closePackageAskAIKey, contextText: closePackageContext(), question: question) }
                },
                alternateModelTiers: closePackageAlternateModelTiers,
                executiveSummaryAnswer: state.askAIAnswers[closePackageSummaryAskAIKey],
                isGeneratingExecutiveSummary: state.askingAIContextKeys.contains(closePackageSummaryAskAIKey),
                executiveSummaryError: state.askAIError?.contextKey == closePackageSummaryAskAIKey ? state.askAIError?.message : nil,
                onGenerateExecutiveSummary: {
                    Task { await state.askAI(contextKey: closePackageSummaryAskAIKey, contextText: closePackageContext(), question: closePackageSummaryPrompt, format: .report) }
                },
                executiveSummarySecondOpinionAnswer: state.secondOpinionAnswers[closePackageSummaryAskAIKey],
                isGeneratingExecutiveSummarySecondOpinion: state.askingSecondOpinionContextKeys.contains(closePackageSummaryAskAIKey),
                executiveSummarySecondOpinionError: state.secondOpinionError?.contextKey == closePackageSummaryAskAIKey ? state.secondOpinionError?.message : nil,
                onGenerateExecutiveSummarySecondOpinion: {
                    Task { await state.askSecondOpinion(contextKey: closePackageSummaryAskAIKey, contextText: closePackageContext(), question: closePackageSummaryPrompt, format: .report) }
                }
            )
            .task {
                if state.balanceSheetLines.isEmpty { await state.loadBalanceSheet() }
                if state.profitAndLossLines.isEmpty { await state.loadProfitAndLoss() }
                if state.cashFlowLines.isEmpty { await state.loadCashFlow() }
                if state.trialBalanceLines.isEmpty { await state.loadTrialBalance() }
                if state.agedReceivablesLines.isEmpty { await state.loadAgedReceivables() }
                if state.agedPayablesLines.isEmpty { await state.loadAgedPayables() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .clientMemory:
            let clientMemoryAskAIKey = "page:client-memory"
            let clientMemoryContext = AskAIContext.compose(
                pageTitle: "Client Memory",
                summaryLines: state.clientMemoryRules.map { "\($0.ruleID.rawValue) — \($0.vendorName), created by \($0.createdBy)\($0.note.map { n in ": \(n)" } ?? "")" }
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            ClientMemoryView(
                environment: state.environment == .production ? .production : .sandbox,
                rules: state.clientMemoryRules,
                inFlightRuleIDs: state.clientMemoryActionInFlightIDs,
                actionError: state.clientMemoryActionError,
                onForget: { rule in Task { await state.removeClientMemoryRule(id: rule.id, actorName: actorName) } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[clientMemoryAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(clientMemoryAskAIKey),
                askAIError: state.askAIError?.contextKey == clientMemoryAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: clientMemoryAskAIKey, contextText: clientMemoryContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[clientMemoryAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(clientMemoryAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == clientMemoryAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: clientMemoryAskAIKey, contextText: clientMemoryContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(clientMemoryAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(clientMemoryAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(clientMemoryAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(clientMemoryAskAIKey)-qwen", contextText: clientMemoryContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(clientMemoryAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(clientMemoryAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(clientMemoryAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(clientMemoryAskAIKey)-claude", contextText: clientMemoryContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { state.screen = .list }
                }
            }

        case .voiceHistory:
            AIConversationHistoryView(rows: Self.conversationHistoryRows(state.conversationHistory))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { state.screen = .list }
                    }
                }

        case .amountSearch:
            AmountSearchView(
                environment: state.environment == .production ? .production : .sandbox,
                transactions: state.transactions,
                accounts: state.accounts
            )

        case .pricingCalculator:
            // This page owns its own inputs as private view state (see
            // `PricingCalculatorView`'s own doc comment on `onDraftQuote`)
            // — it hands back the FULL composed context already built from
            // its current numbers, so this wiring just asks one fixed
            // question against whatever it's given, unlike every other
            // page's context-composition closures above.
            let pricingCalculatorAskAIKey = "page:pricing-calculator"
            let pricingCalculatorPrompt = "Draft a short, professional client-facing proposal using exactly the numbers given above, and follow any additional instruction given."
            let pricingCalculatorOpenFindings = state.findings.filter { $0.status == .open }
            PricingCalculatorView(
                environment: state.environment == .production ? .production : .sandbox,
                aiStatus: state.aiStatus,
                openFindings: pricingCalculatorOpenFindings,
                quoteDraftAnswer: state.askAIAnswers[pricingCalculatorAskAIKey],
                isDraftingQuote: state.askingAIContextKeys.contains(pricingCalculatorAskAIKey),
                quoteDraftError: state.askAIError?.contextKey == pricingCalculatorAskAIKey ? state.askAIError?.message : nil,
                onDraftQuote: { context in
                    Task { await state.askAI(contextKey: pricingCalculatorAskAIKey, contextText: context, question: pricingCalculatorPrompt, format: .clientMessage) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                quoteDraftSecondOpinionAnswer: state.secondOpinionAnswers[pricingCalculatorAskAIKey],
                isDraftingQuoteSecondOpinion: state.askingSecondOpinionContextKeys.contains(pricingCalculatorAskAIKey),
                quoteDraftSecondOpinionError: state.secondOpinionError?.contextKey == pricingCalculatorAskAIKey ? state.secondOpinionError?.message : nil,
                onDraftQuoteSecondOpinion: { context in
                    Task { await state.askSecondOpinion(contextKey: pricingCalculatorAskAIKey, contextText: context, question: pricingCalculatorPrompt, format: .clientMessage) }
                }
            )

        case .audioSettings:
            AudioSettingsView()

        case .cashFlowForecast:
            let cashFlowAskAIKey = "page:cash-flow-forecast"
            let forecast = state.cashFlowForecast
            let cashFlowContext = AskAIContext.compose(
                pageTitle: "Cash Flow Forecast",
                summaryLines: [
                    "Starting cash: \(forecast.startingCash?.description ?? "not available")"
                ] + forecast.horizons.map { horizon in
                    "In \(horizon.days) days: expected in \(horizon.expectedInflow?.description ?? "not available"), expected out \(horizon.expectedOutflow?.description ?? "not available"), projected ending cash \(horizon.projectedEndingCash?.description ?? "not available")"
                } + [
                    "At-risk receivables (91+ days overdue, not counted as expected cash): \(forecast.atRiskReceivables?.description ?? "none")"
                ]
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            CashFlowForecastView(
                state: CashFlowForecastView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    forecast: forecast,
                    isLoading: state.isLoadingBalanceSheet || state.isLoadingAgedReceivables || state.isLoadingAgedPayables || state.isLoadingTrailingPurchases
                ),
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[cashFlowAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(cashFlowAskAIKey),
                askAIError: state.askAIError?.contextKey == cashFlowAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: cashFlowAskAIKey, contextText: cashFlowContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[cashFlowAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(cashFlowAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == cashFlowAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: cashFlowAskAIKey, contextText: cashFlowContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(cashFlowAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(cashFlowAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(cashFlowAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(cashFlowAskAIKey)-qwen", contextText: cashFlowContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(cashFlowAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(cashFlowAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(cashFlowAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(cashFlowAskAIKey)-claude", contextText: cashFlowContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.balanceSheetLines.isEmpty { await state.loadBalanceSheet() }
                if state.agedReceivablesLines.isEmpty { await state.loadAgedReceivables() }
                if state.agedPayablesLines.isEmpty { await state.loadAgedPayables() }
                if state.trailingPurchases.isEmpty { await state.loadTrailingPurchases() }
            }

        case .recurringVendors:
            let recurringVendorsAskAIKey = "page:recurring-vendors"
            let recurringVendors = state.recurringVendors
            let missingVendors = state.missingRecurringVendors
            let recurringVendorsContext = AskAIContext.compose(
                pageTitle: "Recurring Vendors",
                summaryLines: recurringVendors.map { vendor in
                    "\(vendor.vendorName): \(vendor.averageAmount.description) roughly every \(Int(vendor.averageIntervalDays.rounded())) days, \(vendor.occurrenceCount) charges seen, next expected \(vendor.expectedNextChargeDate.formatted)\(vendor.lastAmountChanged ? " — last charge's amount changed" : "")\(missingVendors.contains(where: { $0.id == vendor.id }) ? " — OVERDUE for expected charge" : "")"
                }
            ) + AskAIContext.crossPageFindingsAddendum(state.findings.filter { $0.status == .open })
            RecurringVendorsView(
                state: RecurringVendorsView.ViewState(
                    environment: state.environment == .production ? .production : .sandbox,
                    recurringVendors: recurringVendors,
                    missingVendors: missingVendors,
                    monthsOfHistoryScanned: AppState.trailingPurchasesMonths,
                    isLoading: state.isLoadingTrailingPurchases
                ),
                isSyncing: state.loadState == .loading,
                onSync: { Task { await state.syncAndEvaluate() } },
                aiStatus: state.aiStatus,
                askAIAnswer: state.askAIAnswers[recurringVendorsAskAIKey],
                isAskingAI: state.askingAIContextKeys.contains(recurringVendorsAskAIKey),
                askAIError: state.askAIError?.contextKey == recurringVendorsAskAIKey ? state.askAIError?.message : nil,
                onAskAI: { question in
                    Task { await state.askAI(contextKey: recurringVendorsAskAIKey, contextText: recurringVendorsContext, question: question) }
                },
                secondOpinionConfigured: state.aiStatus?.secondaryConfigured == true,
                secondOpinionAnswer: state.secondOpinionAnswers[recurringVendorsAskAIKey],
                isAskingSecondOpinion: state.askingSecondOpinionContextKeys.contains(recurringVendorsAskAIKey),
                secondOpinionError: state.secondOpinionError?.contextKey == recurringVendorsAskAIKey ? state.secondOpinionError?.message : nil,
                onAskSecondOpinion: { question in
                    Task { await state.askSecondOpinion(contextKey: recurringVendorsAskAIKey, contextText: recurringVendorsContext, question: question) }
                },
                alternateModelTiers: [
                    .init(
                    label: "ASK QWEN3:8B",
                    modelName: "qwen3:8b",
                    disclaimer: "Same context as above, answered by qwen3:8b instead of the default local model — for comparing response quality. Still local and free, still cannot state a figure not already given.",
                    answer: state.askAIAnswers["\(recurringVendorsAskAIKey)-qwen"],
                    isAsking: state.askingAIContextKeys.contains("\(recurringVendorsAskAIKey)-qwen"),
                    error: state.askAIError?.contextKey == "\(recurringVendorsAskAIKey)-qwen" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(recurringVendorsAskAIKey)-qwen", contextText: recurringVendorsContext, question: question, model: "qwen3:8b") } }
                ),
                    state.aiStatus?.anthropicConfigured == true ? .init(
                    label: "ASK CLAUDE HAIKU 4.5",
                    modelName: "Claude Haiku 4.5",
                    disclaimer: "Same context as above, answered by Claude Haiku 4.5 instead of the default local model — cloud, ~$0.005/call, only runs when you ask.",
                    answer: state.askAIAnswers["\(recurringVendorsAskAIKey)-claude"],
                    isAsking: state.askingAIContextKeys.contains("\(recurringVendorsAskAIKey)-claude"),
                    error: state.askAIError?.contextKey == "\(recurringVendorsAskAIKey)-claude" ? state.askAIError?.message : nil,
                    onAsk: { question in Task { await state.askAI(contextKey: "\(recurringVendorsAskAIKey)-claude", contextText: recurringVendorsContext, question: question, model: "claude-haiku-4-5") } }
                ) : nil
                ].compactMap { $0 }
            )
            .task {
                if state.trailingPurchases.isEmpty { await state.loadTrailingPurchases() }
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
        let currentWatermark = AppState.currentEvidenceWatermark()

        func count(for ruleIDs: Set<String>) -> Int {
            openFindings.filter { ruleIDs.contains($0.ruleID.rawValue) }.count
        }
        func detail(for count: Int) -> String {
            count == 0 ? "No open findings." : "\(count) open finding\(count == 1 ? "" : "s")."
        }

        return MonthEndChecklist.defaultItems.map { item in
            let readyDetail: String?
            let openFindingsCount: Int?
            switch item.id.rawValue {
            case "resolve-cleanup-assessment":
                let c = count(for: AppState.cleanupAssessmentRuleIDs)
                readyDetail = detail(for: c)
                openFindingsCount = c
            case "review-balance-sheet-integrity":
                let c = count(for: AppState.balanceSheetIntegrityRuleIDs)
                readyDetail = detail(for: c)
                openFindingsCount = c
            case "review-bank-feed":
                let c = count(for: ["VL-RECON-MISSING-001", "VL-RECON-AMBIGUOUS-001", "VL-VENDOR-MISMATCH-001"])
                readyDetail = detail(for: c)
                openFindingsCount = c
            default:
                readyDetail = nil
                openFindingsCount = nil
            }
            let completion = completionsForPeriod.first { $0.itemID == item.id }
            return MonthEndCloseView.ItemState(
                item: item,
                isUnlocked: MonthEndChecklist.isUnlocked(item, completedItemIDs: completedIDs),
                completion: completion,
                readyDetail: readyDetail,
                openFindingsCount: openFindingsCount,
                isStale: completion.map { MonthEndChecklist.isStale($0, currentWatermark: currentWatermark) } ?? false
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
    /// list page's coverage strip. Gauntlet Loop, Gauntlet B round 12
    /// (2026-08-24): a critic found this comment's second sentence was
    /// simply false, and corrected it — `state.coverage` (`Coverage`,
    /// `.complete`/`.partial`) is computed purely from QBO paging counts of
    /// purchases/bills/invoices/payments (`QBOSyncClient.sync`); it has no
    /// relationship to any individual rule's `RuleOutcome.cannotEvaluate`.
    /// A rule like `VL-FORCED-RECON-001`/`VL-REPORT-TIE-001` can return
    /// `.cannotEvaluate` (e.g. its P&L/Balance Sheet report `try?`-fetch
    /// failed this sync) while `state.coverage == .complete` and this
    /// strip shows "Synced" — that per-rule reason is discarded at
    /// `AppState.syncAndEvaluate()`'s `case .cannotEvaluate: break` and has
    /// no UI surface anywhere today. Confirmed real, left undocumented as
    /// a known gap rather than fixed here — surfacing it is a UI feature
    /// addition, out of this hardening run's explicit scope ("no new
    /// pages/features"). `coverageOutcome` below maps ONLY the overall
    /// sync-level coverage, not any rule's own outcome.
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

    /// `AskAIConversationEntry` -> `AIConversationHistoryView.Row`. Lives
    /// here, not in `VoiceLedgerUI`, for the same reason `vlStatus(for:)`
    /// does — only the app layer is allowed to bridge a `Core` type into
    /// this UI module's primitive-only vocabulary. Reversed to most-recent-
    /// first — `conversationHistory` itself stays oldest-first (the order
    /// `ClientStore` persists it in, and the order new entries are
    /// appended), so this is a view-only ordering choice.
    private static func conversationHistoryRows(_ entries: [AskAIConversationEntry]) -> [AIConversationHistoryView.Row] {
        let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }()
        return entries.reversed().map { entry in
            AIConversationHistoryView.Row(
                id: entry.id,
                contextLabel: entry.contextLabel,
                tierLabel: entry.tier == .primary ? "Gemma (local, free)" : "OpenAI",
                question: entry.question,
                answer: entry.answer,
                timeLabel: formatter.string(from: entry.askedAt)
            )
        }
    }

    // MARK: - Export table builders
    //
    // Each report-style page already renders from real, already-computed
    // state (ReportLine, Finding, ActivityLogEntry) — these just reshape
    // that same data into the one generic `ExportTable` shape every format
    // writer consumes, rather than each page inventing its own export path.

    private static func periodLabel(_ period: AccountingPeriod) -> String {
        "\(period.year)-\(String(format: "%02d", period.month))"
    }

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
        profitAndLossLines: [ReportLine],
        cashFlowLines: [ReportLine] = [],
        trialBalanceLines: [TrialBalanceLine] = [],
        agedReceivablesLines: [AgingLine] = [],
        agedPayablesLines: [AgingLine] = []
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
        for line in cashFlowLines where line.isSummary {
            rows.append([ExportCell(text: "Cash Flow"), ExportCell(text: line.label), ExportCell.money(line.amount)])
        }
        if let line = trialBalanceLines.last(where: \.isSummary) {
            rows.append([ExportCell(text: "Trial Balance"), ExportCell(text: "\(line.label) — Debit"), ExportCell.money(line.debit)])
            rows.append([ExportCell(text: "Trial Balance"), ExportCell(text: "\(line.label) — Credit"), ExportCell.money(line.credit)])
        }
        if let line = agedReceivablesLines.last(where: \.isSummary) {
            rows.append([ExportCell(text: "Aged Receivables"), ExportCell(text: line.label), ExportCell.money(line.total)])
        }
        if let line = agedPayablesLines.last(where: \.isSummary) {
            rows.append([ExportCell(text: "Aged Payables"), ExportCell(text: line.label), ExportCell.money(line.total)])
        }
        return ExportTable(title: "Close Package", columns: ["Section", "Item", "Value"], rows: rows)
    }
}

/// The dashboard's own prominent voice entry point — see the `.list` case's
/// doc comment for why this exists alongside `AppSidebar`'s footer button.
/// Owner-facing (2026-09-06) — see this view's own call site's doc
/// comment. Deliberately its own small component, not folded into
/// `DashboardVoiceBanner`, since the two have genuinely different jobs:
/// that one starts/stops listening, this one submits typed text through
/// the exact same downstream pipeline.
private struct TypedCommandHarness: View {
    let isProcessing: Bool
    let lastMessage: String?
    let onSubmit: (String) -> Void

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VLSpacing.xs) {
            HStack(spacing: VLSpacing.sm) {
                TextField("Type a command or question — \"pull up the Acme bill\", \"chart expenses this month\"…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isProcessing)
                    .onSubmit(submit)
                Button(isProcessing ? "Thinking…" : "Ask") { submit() }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            // Owner-reported bug (2026-09-07): "the words get scrunched up
            // at the top of the screen" — Claude's replies here run
            // noticeably longer than Gemma's typically did, and with no
            // line spacing or `fixedSize` this Text let SwiftUI compress
            // several wrapped paragraphs into a cramped block instead of
            // laying them out with real line height. `lineSpacing` +
            // `fixedSize(vertical:)` fix the cramped rendering itself;
            // `lineLimit(6)` (up from 3) still caps runaway length without
            // cutting off a normal multi-sentence answer after one line.
            if let lastMessage, !isProcessing {
                Text(lastMessage)
                    .font(VLTypography.caption())
                    .foregroundStyle(VLColor.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, VLSpacing.xxs)
            }
        }
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        onSubmit(text)
    }
}

private struct DashboardVoiceBanner: View {
    let isListening: Bool
    let isProcessing: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: VLSpacing.sm) {
                Image(systemName: isListening ? "mic.fill" : "mic.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isListening ? .red : VLColor.cyan)
                VStack(alignment: .leading, spacing: VLSpacing.hairline) {
                    Text(isListening ? "Listening…" : (isProcessing ? "Thinking…" : "Ask Voice Ledger"))
                        .font(VLTypography.bodyEmphasis())
                        .foregroundStyle(VLColor.textPrimary)
                    if !isListening && !isProcessing {
                        Text("Navigate, review findings, or ask why something's flagged — by voice.")
                            .font(VLTypography.caption())
                            .foregroundStyle(VLColor.textMuted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VLColor.textMuted)
            }
            .padding(VLSpacing.sm)
            .background(VLColor.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: VLRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: VLRadius.card)
                    .stroke(isListening ? Color.red.opacity(0.6) : VLColor.border, lineWidth: VLBorder.hairline)
            )
        }
        .buttonStyle(.plain)
    }
}

/// A plain reference box `ContentHostingView` writes into — `@State`
/// needs a stable identity across view updates, and a class reference
/// (rather than a struct/`CGSize`) is what lets `RootView` read the
/// latest captured view without re-triggering a SwiftUI re-render every
/// time AppKit re-lays-out the window (which a `@State var view: NSView?`
/// would do on every single layout pass).
@MainActor
final class HostViewCaptureBox {
    weak var view: NSView?
}

/// Hosts `content` inside an `NSHostingView` this file creates and keeps
/// a direct reference to, rather than trying to locate SwiftUI's own
/// internal AppKit bridging after the fact.
///
/// **First attempt, reverted:** a zero-size `.background()` marker
/// reading its own `superview`. Live-reported result: "nothing to export
/// yet, try again" on every screen, not just some — the marker's
/// superview was either `nil` or zero-sized at export time (SwiftUI's
/// exact internal view structure around `.background()` isn't part of
/// its public contract, so that guess was never reliable to begin with,
/// only convenient). This wrapper removes the guessing entirely: the
/// `NSHostingView` returned by `makeNSView` below IS the one and only
/// view SwiftUI displays for the whole detail column — not a sibling of
/// it — so `box.view` is set synchronously, immediately, every time,
/// with no race to lose.
private struct ContentHostingView<Content: View>: NSViewRepresentable {
    let box: HostViewCaptureBox
    let content: Content

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: content)
        box.view = hostingView
        return hostingView
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content
    }
}
