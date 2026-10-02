import Foundation
import Observation
import AppKit
import Core
import Voice
import IntegrationsQuickBooks
import IntegrationsImports
import IntegrationsVoice
import DB
import Exporting
import VoiceLedgerUI

/// Wires QBOSyncClient -> RuleEngine -> ClientStore -> the UI layer for the
/// real end-to-end Branch B path (docs/phase-0/11_VERTICAL_SLICE.md §11.2,
/// steps 1-11). This is application glue, not domain logic — every decision
/// about what counts as a duplicate or how a finding resolves happens in
/// `Core`; this type only sequences the calls and holds view state.
@MainActor
@Observable
public final class AppState {
    public enum Screen: Equatable {
        /// Owner directive (2026-08-29): the app's real landing screen — a
        /// per-client KPI dashboard, distinct from `.list` (Findings).
        case clientDashboard
        case connection
        case scopeAndPeriodLock
        case list
        case findingGroup(FactFindingGroup)
        case detail(findingID: String)
        case procedure(findingID: String, actionID: String)
        case activityLog
        case cleanupAssessment
        case balanceSheetIntegrity
        case chartOfAccountsCleanup
        case batchFixes
        case salesTaxReview
        case taxes
        case firmCockpit
        case bankFeedCleanup
        case monthEndClose
        case balanceSheetReport
        case profitAndLossReport
        case cashFlowReport
        case trialBalanceReport
        case agedReceivablesReport
        case agedPayablesReport
        case generalLedgerReport
        case closePackage
        case clientMemory
        case voiceHistory
        /// Owner directive (2026-08-31): "search for a specific dollar
        /// amount and it brings back all the transactions that are that
        /// amount." Searches `transactions` (already synced, already in
        /// memory) client-side — no new QBO call.
        case amountSearch
        /// Owner directive (2026-08-31): a monthly-retainer + cleanup-project
        /// pricing calculator for quoting a prospect — deliberately usable
        /// with no client connected at all.
        case pricingCalculator
        /// Owner directive (2026-09-06): pick an audio input/output device
        /// from within the app instead of System Settings.
        case audioSettings
        /// Owner directive (2026-09-06): "build cash flow forecasting."
        case cashFlowForecast
        case diagnostics
        /// Owner directive (2026-09-06): "build... recurring-vendor
        /// detection."
        case recurringVendors
        /// Owner directive (2026-09-27): a discovery-call script — the same
        /// `PricingCalculator` inputs as `.pricingCalculator`, but scattered
        /// next to the intake question each one corresponds to, with a
        /// live-fillable answer field under every question, rather than
        /// grouped separately at the top. Also how a new prospect gets
        /// saved into the roster (`IntakeRosterStore`).
        case intakeQuestions
        /// Practice tools (owner directive 2026-10-02).
        case complianceCalendar
        case scopeRequests
        case industrySetup
        /// Clickable list of every card Moneypenny can show (2026-10-02).
        case chartsGallery
    }

    /// Which rules belong to the Cleanup Assessment view vs. Page 3's
    /// findings list — `Finding` itself doesn't carry a page/category
    /// distinction, only `ruleID`, so the view layer keys off the ID set.
    /// Moved to `Core.CleanupCategory.ruleIDs` 2026-09-06 — this used to be
    /// its own hand-typed literal (with a THIRD hand-mirrored copy in
    /// `CleanupCategoryTests`, since Core can't import `VoiceLedgerApp`),
    /// duplicating the exact same rule IDs `CleanupCategory`'s own
    /// category table already had to list. See that property's doc
    /// comment for why deriving from one dictionary beats three lists.
    public static let cleanupAssessmentRuleIDs: Set<String> = CleanupCategory.ruleIDs

    /// Page 8's rules — a subset of `cleanupAssessmentRuleIDs` that also
    /// belong to the real Balance Sheet Integrity workflow page, not just
    /// the cross-cutting Cleanup Assessment tool. The two sets overlapping
    /// is intentional (docs/backlog/CLEANUP_MODE.md's assessment is meant to
    /// span multiple pages' rules), not a bug.
    /// Derived from `CleanupCategory` (2026-09-11 fix, same "one dictionary,
    /// not a hand-typed literal" reasoning as `cleanupAssessmentRuleIDs`
    /// above): this used to be its own 5-ID literal that had drifted out of
    /// sync with `CleanupCategory`'s own `.balanceSheetIntegrity` grouping —
    /// `VL-CLOSED-PERIOD-DRIFT-001` and `VL-BS-DRCR-001` were both filed
    /// there but missing here, so neither ever rendered on this page.
    public static let balanceSheetIntegrityRuleIDs: Set<String> = CleanupCategory.ruleIDs(in: .balanceSheetIntegrity)

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var findings: [Finding] = []
    public private(set) var activityLog: [ActivityLogEntry] = []
    public private(set) var coverage: Coverage = .partial(reason: "not synced yet")
    /// The chart of accounts from the last sync — used to let the import
    /// UI ask "which QBO account is this statement FOR?" (never inferred
    /// from the file). Empty until the first `syncAndEvaluate()` completes.
    public private(set) var accounts: [LedgerAccount] = []
    /// The Search by Amount box. Voice fills it ("find 1420", "find Gusto")
    /// before opening the page, so the results are already showing.
    public var searchQuery = ""
    /// Vendor IDs from the last sync, for exact "Open in QBO" vendor links.
    public private(set) var vendors: [LedgerVendor] = []
    /// All synced (plus merged-in imported) transactions from the last
    /// sync — added for Page 2's period-lock warning
    /// (`PeriodLockCheck.transactionsInLockedPeriod`), which needs the same
    /// `LedgerTransaction` set the rule engine evaluates, not a
    /// rule-specific subset. Empty until the first `syncAndEvaluate()`
    /// completes, same posture as `accounts`.
    public private(set) var transactions: [LedgerTransaction] = []
    /// Added 2026-09-06 for `VoiceToolLoop`'s `get_sync_status` tool
    /// ("when was this last synced") — `nil` until the first
    /// `syncAndEvaluate()` in this session completes, set every time
    /// after that at the same atomic-publish point as `transactions`.
    public private(set) var lastSyncedAt: Date?
    /// When this realm's cached data was last synced, from disk — shown so
    /// cached data never reads "not synced yet". Status stays gray until a
    /// sync in this session (CLAUDE.md rule 5: cached is not current).
    public private(set) var cachedSyncedAt: Date?
    /// Multi-month history (owner decision 2026-09-29) behind the
    /// Diagnostics page. Persisted per realm; `nil` until first loaded.
    public private(set) var historySnapshot: HistorySnapshot?
    public private(set) var isLoadingHistory = false
    public private(set) var historyError: String?
    public private(set) var unreconciledMonths = 0

    private var diagnosticsAsOf: AccountingDate { AccountingDate(date: Date()) }

    public var cleanupScopeScore: CleanupScopeScore? {
        historySnapshot.map { ClientDiagnostics.scopeScore(history: $0, openFindings: findings, asOf: diagnosticsAsOf, inputs: CleanupScopeInputs(unreconciledMonths: unreconciledMonths)) }
    }

    public var bankFeedActivity: [BankFeedActivity] {
        historySnapshot.map { ClientDiagnostics.bankFeedActivity(history: $0, asOf: diagnosticsAsOf) } ?? []
    }

    public var fluxAlerts: [FluxAlert] {
        historySnapshot.map { ClientDiagnostics.fluxAlerts(history: $0, asOf: diagnosticsAsOf) } ?? []
    }

    /// Posting-level evidence for account-balance findings, keyed by
    /// account ID; fetched on demand when such a finding is opened.
    public private(set) var accountLedgerRows: [String: [GeneralLedgerLine]] = [:]
    public private(set) var loadingAccountLedgerIDs: Set<String> = []

    public var accountTypesByID: [String: LedgerAccountType] {
        let known = accounts.isEmpty ? (historySnapshot?.accounts ?? []) : accounts
        return Dictionary(known.map { ($0.id, $0.accountType) }, uniquingKeysWith: { first, _ in first })
    }

    /// Only real loaded history; never a manufactured series.
    public var historyTrend: TrendData? {
        guard let months = historySnapshot?.monthlyProfitAndLoss else { return nil }
        let trend = ChartData.trend(from: months)
        return trend.points.count >= 2 ? trend : nil
    }

    /// 12-month KPI sparklines; only from real loaded history.
    public var historySparklines: SparklineData? {
        guard let history = historySnapshot else { return nil }
        let today = AccountingDate(date: Date())
        let lastComplete = AccountingPeriod(year: today.year, month: today.month).previousMonth
        return ChartData.sparklines(months: history.monthlyProfitAndLoss, monthEndCash: history.monthEndCash ?? [], through: lastComplete)
    }

    public func loadAccountLedgerRows(accountID: String) async {
        guard !loadingAccountLedgerIDs.contains(accountID) else { return }
        loadingAccountLedgerIDs.insert(accountID)
        defer { loadingAccountLedgerIDs.remove(accountID) }
        if let rows = try? await syncClient.fetchAccountLedger(realmID: realmID, accountID: accountID, through: AccountingDate(date: Date())) {
            accountLedgerRows[accountID] = rows
        }
    }

    public func qboAccountURL(_ accountID: String) -> URL? {
        QBOWebLink.url(forRecordID: accountID, transactions: [], accounts: accounts.isEmpty ? (historySnapshot?.accounts ?? []) : accounts, isSandbox: environment != .production)
    }

    public func evidenceAccountID(for finding: Finding) -> String? {
        let known = accounts.isEmpty ? (historySnapshot?.accounts ?? []) : accounts
        return finding.evidence.lazy.map(\.transactionID).first { id in known.contains { $0.id == id } }
    }

    public func loadAccountLedgerRows(for finding: Finding) async {
        guard let accountID = evidenceAccountID(for: finding),
              accountLedgerRows[accountID] == nil, !loadingAccountLedgerIDs.contains(accountID) else { return }
        loadingAccountLedgerIDs.insert(accountID)
        defer { loadingAccountLedgerIDs.remove(accountID) }
        if let rows = try? await syncClient.fetchAccountLedger(realmID: realmID, accountID: accountID, through: AccountingDate(date: Date())) {
            accountLedgerRows[accountID] = rows
        }
    }

    /// Every exact-record QBO link the screens can show (see `QBOLinks`).
    public var qboLinks: QBOLinks {
        let isSandbox = environment != .production
        let known = accounts.isEmpty ? (historySnapshot?.accounts ?? []) : accounts
        var accountURLs: [String: URL] = [:]
        var accountIDsByName: [String: String] = [:]
        for account in known {
            if let url = QBOWebLink.url(forRecordID: account.id, transactions: [], accounts: [account], isSandbox: isSandbox) { accountURLs[account.id] = url }
            accountIDsByName[account.name.lowercased()] = account.id
            if let full = account.fullyQualifiedName { accountIDsByName[full.lowercased()] = account.id }
        }
        var findingURLs: [String: URL] = [:]
        for finding in findings { if let url = qboWebURL(for: finding) { findingURLs[finding.id] = url } }
        var vendorIDs: [String: String] = [:]
        for vendor in vendors { vendorIDs[vendor.displayName.trimmingCharacters(in: .whitespaces).lowercased()] = vendor.id }
        return QBOLinks(isSandbox: isSandbox, findingURLs: findingURLs, accountURLs: accountURLs, accountIDsByName: accountIDsByName, vendorIDsByName: vendorIDs)
    }

    public func qboWebURL(for finding: Finding) -> URL? {
        QBOWebLink.url(
            for: finding,
            transactions: transactions + (historySnapshot?.transactions ?? []),
            accounts: accounts.isEmpty ? (historySnapshot?.accounts ?? []) : accounts,
            isSandbox: environment != .production
        )
    }

    public var kpiSummary: KPISummary? {
        historySnapshot.map { ClientDiagnostics.kpiSummary(history: $0, asOf: diagnosticsAsOf) }
    }
    /// docs/VOICE_LEDGER_SPEC.md Page 2 — Voice Ledger's own stricter period
    /// lock, independent of QBO's unread `BookCloseDate`. `nil` until the
    /// bookkeeper sets one for this realm.
    public private(set) var periodLock: PeriodLock?
    public private(set) var engagementScope: EngagementScope = EngagementScope()
    /// All-time count of persisted imported statement lines for this realm
    /// (not period-filtered) — feeds `ReconciliationSummary.compute`'s
    /// `totalStatementLines`. Refreshed on every `syncAndEvaluate()`.
    public private(set) var importedStatementLineCount: Int = 0
    public private(set) var loadState: LoadState = .idle
    // Owner directive (2026-08-29): "the app should start with the client's
    // dashboard" — previously `.connection`, which meant every launch
    // landed on the connection-health screen regardless of whether a
    // client was already connected, with no auto-redirect anywhere in this
    // codebase (confirmed by search — the bookkeeper always navigated away
    // manually via the sidebar). `.connection` is still one click away in
    // the sidebar's SETUP section, unchanged.
    public var screen: Screen = .clientDashboard {
        didSet {
            // Real navigation history (owner bug 2026-09-30: "go back" always
            // jumped to Findings). Back/forward set `isNavigatingHistory`
            // so their own moves aren't recorded as new history.
            if !isNavigatingHistory, oldValue != screen {
                navigationHistory.append(oldValue)
                if navigationHistory.count > 50 { navigationHistory.removeFirst() }
                navigationForward.removeAll()
            }
            // Remember the page a finding was opened from, so Back returns
            // there instead of always to Findings (owner bug report 2026-09-29).
            switch screen {
            case .detail, .procedure:
                switch oldValue {
                case .detail, .procedure: break
                default: findingReturnScreen = oldValue
                }
            default: break
            }
        }
    }
    public var voiceLogLabel: String {
        switch screen {
        case .clientDashboard: return "Dashboard"
        case .connection: return "Connection"
        case .scopeAndPeriodLock: return "Scope & Period Lock"
        case .list: return "Findings"
        case .findingGroup(let group): return "Findings: \(group.rawValue)"
        case .detail: return "Finding Detail"
        case .procedure: return "Guided Procedure"
        case .activityLog: return "Activity Log"
        case .cleanupAssessment: return "Cleanup Assessment"
        case .balanceSheetIntegrity: return "Balance Sheet Integrity"
        case .chartOfAccountsCleanup: return "Chart of Accounts"
        case .batchFixes: return "Batch Fixes"
        case .salesTaxReview: return "Sales Tax Review"
        case .taxes: return "Taxes"
        case .firmCockpit: return "Firm Cockpit"
        case .bankFeedCleanup: return "Bank Feed Cleanup"
        case .monthEndClose: return "Month-End Close"
        case .balanceSheetReport: return "Balance Sheet"
        case .profitAndLossReport: return "Profit & Loss"
        case .cashFlowReport: return "Cash Flow"
        case .trialBalanceReport: return "Trial Balance"
        case .agedReceivablesReport: return "Aged Receivables"
        case .agedPayablesReport: return "Aged Payables"
        case .generalLedgerReport: return "General Ledger"
        case .closePackage: return "Close Package"
        case .clientMemory: return "Client Memory"
        case .voiceHistory: return "Voice History"
        case .amountSearch: return "Search by Amount"
        case .pricingCalculator: return "Pricing Calculator"
        case .audioSettings: return "Audio Settings"
        case .cashFlowForecast: return "Cash Flow Forecast"
        case .diagnostics: return "Client Diagnostics"
        case .recurringVendors: return "Recurring Vendors"
        case .intakeQuestions: return "Intake Questions"
        case .complianceCalendar: return "Compliance Calendar"
        case .scopeRequests: return "Scope Requests"
        case .industrySetup: return "Industry Setup"
        case .chartsGallery: return "Charts & Cards"
        }
    }

    public var visibleFindings: [Finding] {
        if case .findingGroup(let group) = screen {
            return FindingTriage.sorted(ClientFacts.findings(clientData, category: group).value ?? [])
        }
        return FindingTriage.sorted(findings.filter { $0.status == .open })
    }

    public var findingsPageTitle: String {
        if case .findingGroup(let group) = screen { return group.rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
        return "All Findings"
    }

    /// Where "Back" from a finding goes.
    public private(set) var findingReturnScreen: Screen = .list

    public private(set) var navigationHistory: [Screen] = []
    public private(set) var navigationForward: [Screen] = []
    private var isNavigatingHistory = false
    public var canGoBack: Bool { !navigationHistory.isEmpty }
    public var canGoForward: Bool { !navigationForward.isEmpty }

    @discardableResult
    public func goBack() -> Bool {
        guard let previous = navigationHistory.popLast() else { return false }
        isNavigatingHistory = true
        navigationForward.append(screen)
        screen = previous
        isNavigatingHistory = false
        return true
    }

    @discardableResult
    public func goForward() -> Bool {
        guard let next = navigationForward.popLast() else { return false }
        isNavigatingHistory = true
        navigationHistory.append(screen)
        screen = next
        isNavigatingHistory = false
        return true
    }

    public func leaveFinding() { screen = findingReturnScreen }

    /// On launch: always refresh from QuickBooks (changed 2026-10-01 from a
    /// 15-minute rule; the owner kept seeing "saved data"), then load the
    /// 24-month history in the background so Search, Diagnostics and the
    /// cleanup quote are ready. The user should almost never see "cached".
    public func syncOnLaunchIfStale() async {
        guard !realmID.rawValue.isEmpty else { return }
        let stale: Bool
        switch freshness {
        case .neverSynced: stale = true
        case .cached: stale = true   // every launch syncs: "saved data" should never be what the owner sees at startup
        default: stale = false
        }
        if stale { await syncDashboard() }
        // The launcher may still be starting the backend when checkHealth()
        // first ran, leaving the company name blank — try once more now.
        if companyInfo == nil { await checkHealth() }
        if historySnapshot == nil || (historySnapshot.map { Date().timeIntervalSince($0.fetchedAt) > 24 * 3600 } ?? false) {
            Task { [weak self] in await self?.loadHistory() }
        }
    }

    /// How current the loaded data is — the one value every page and
    /// Moneypenny read (docs/MONEYPENNY_CONSISTENCY_DESIGN.md).
    public var freshness: Freshness {
        if isSyncInFlight { return .syncing }
        if let synced = lastSyncedAt { return .synced(at: synced) }
        if let cached = cachedSyncedAt { return .cached(at: cached) }
        return .neverSynced
    }

    /// Everything already loaded, as plain values for `ClientFacts`.
    public var clientData: ClientData {
        ClientData(period: period, transactions: transactions, accounts: accounts, balanceSheet: balanceSheetLines,
                   priorBalanceSheet: priorPeriodBalanceSheetLines, profitAndLoss: profitAndLossLines,
                   priorProfitAndLoss: priorPeriodProfitAndLossLines, cashFlow: cashFlowLines, findings: findings,
                   history: historySnapshot, freshness: freshness, agedPayables: agedPayablesLines)
    }

    public var searchableTransactions: [LedgerTransaction] { clientData.searchableTransactions }
    public var searchScopeDescription: String { ClientFacts.searchScope(clientData) }

    public var findingReturnLabel: String {
        switch findingReturnScreen {
        case .clientDashboard: return "Back to Dashboard"
        case .cleanupAssessment: return "Back to Cleanup Assessment"
        case .balanceSheetIntegrity: return "Back to Balance Sheet Integrity"
        case .chartOfAccountsCleanup: return "Back to Chart of Accounts"
        case .batchFixes: return "Back to Batch Fixes"
        case .salesTaxReview: return "Back to Sales Tax Review"
        case .bankFeedCleanup: return "Back to Bank Feed Cleanup"
        case .firmCockpit: return "Back to Firm Cockpit"
        case .closePackage: return "Back to Close Package"
        case .monthEndClose: return "Back to Month-End Close"
        case .amountSearch: return "Back to Search"
        default: return "Back to Findings"
        }
    }
    /// Owner directive (2026-09-27): the Intake Questions page's live
    /// draft — bound directly into every text field/toggle on that page,
    /// the same way `PricingCalculatorView` owns its inputs as private
    /// view state, except this one needs to survive a save/reload/edit
    /// cycle against the roster file, so it lives here instead.
    public var currentIntake = ClientIntake()
    /// Engagement Agreement builder sheet (Intake Questions page).
    public var showingAgreementBuilder = false
    /// The full saved roster, loaded from `IntakeRosterStore` — every
    /// prospect/client intake ever saved, across realms (this is
    /// deliberately NOT per-`realmId` scoped; see that store's own doc
    /// comment for why).
    public private(set) var intakeRoster: [ClientIntake] = []
    /// Set by `saveCurrentIntake()`/`loadIntakeRoster()` — surfaced by
    /// `RootView` as a lightweight confirmation/error, same spirit as
    /// `exportError` but deliberately separate (a save here isn't a file
    /// export the user picked a location for; it's this file, always).
    public private(set) var intakeStatusMessage: String?
    private let intakeRosterStore = IntakeRosterStore()
    /// Owner-facing (2026-09-06): the voice assistant's chart-popup
    /// capability (`VoiceUIAction.presentChart`) — `RootView` presents a
    /// sheet bound to this being non-`nil`. A popup, not a page
    /// navigation, matching the owner's own framing ("make a pop up with
    /// chart for the graph"). Setting it to `nil` dismisses the sheet.
    public var presentedChart: ChartRequest?
    /// Owner-facing (2026-09-06): the voice assistant's side-by-side
    /// finding comparison ("pull up these two transactions") —
    /// `VoiceUIAction.openFindings`. `RootView` presents a sheet showing
    /// one card per id, each independently closable; the whole sheet
    /// dismisses once the list is empty. `nil`/empty both mean "not
    /// shown," so a caller can freely `.removeAll` down to zero without a
    /// separate dismiss step.
    public var comparedFindingIDs: [String] = []
    public let environment: QBOEnvironment
    /// Gauntlet Loop, Gauntlet B round 21 (2026-08-24): `syncAndEvaluate()`'s
    /// own re-entrancy guard — deliberately NOT `loadState == .loading`,
    /// because several unrelated methods independently write
    /// `loadState = .failed(...)` on their own catch paths. If one of
    /// those fired while a sync was genuinely still in flight, checking
    /// `loadState` would have been fooled into thinking no sync was
    /// running, letting a second, truly concurrent `syncAndEvaluate()`
    /// start — two overlapping runs could read `priorFindingIDs`/
    /// `dismissedFindingIDs` before each other's writes land, producing
    /// duplicate `findingDetected`/`findingResolved` Activity Log entries.
    /// This flag is written ONLY by `syncAndEvaluate()` itself, so nothing
    /// else can clobber it mid-sync.
    private var isSyncInFlight = false

    // Connection Page (step 1.3) state.
    public private(set) var companyInfo: CompanyConnectionInfo?
    public private(set) var healthResult: HealthCheckResult?
    public private(set) var healthCheckError: String?
    public private(set) var isCheckingHealth = false
    public private(set) var writeAccessEnabled: Bool?
    /// docs/VOICE_LEDGER_SPEC.md's Ask [AI] panel + kill switch. `nil`
    /// until the first `checkAIStatus()` completes — never assumed to be
    /// either configured or enabled before actually asking the backend.
    public private(set) var aiStatus: AIStatus?
    public private(set) var isCheckingAIStatus = false
    public private(set) var isTogglingAIEnabled = false
    public private(set) var aiStatusError: String?
    /// Per-context-key Ask AI answers, keyed by finding ID for
    /// `FindingDetailView` or a fixed page key (e.g. `"cleanup-assessment"`)
    /// for a page-level panel — one standing answer per key at a time;
    /// asking again replaces it, same posture as every other single-slot
    /// per-finding state in this file. Renamed from the finding-only
    /// `askAIAnswers`/`askingAIFindingIDs` when the Ask AI panel expanded
    /// beyond `FindingDetailView` to other pages (2026-08-28) — the
    /// dictionaries themselves didn't need to change shape, only what they
    /// mean.
    public private(set) var askAIAnswers: [String: String] = [:]
    public private(set) var askingAIContextKeys: Set<String> = []
    public private(set) var askAIError: (contextKey: String, message: String)?
    /// The opt-in "second opinion" (OpenAI) tier — 2026-08-29, kept as
    /// entirely separate state from `askAIAnswers`/etc above rather than a
    /// mode of the same maps, so a bookkeeper can see the free (Gemma) and
    /// paid (OpenAI) answers to the same finding side by side instead of
    /// one overwriting the other.
    public private(set) var secondOpinionAnswers: [String: String] = [:]
    public private(set) var askingSecondOpinionContextKeys: Set<String> = []
    public private(set) var secondOpinionError: (contextKey: String, message: String)?
    public private(set) var isTogglingWriteAccess = false

    // Apply Fix (staged API write, VL-CC-PAYMENT-001's first consumer).
    // Gauntlet Loop, Gauntlet B round 14 (2026-08-24): this used to be a
    // bare `Bool`, not scoped to a finding — same bleed class round 13
    // fixed for `applyFixError`, one line away in `RootView.swift`. A
    // bookkeeper could start Apply Fix on Finding A (a real in-flight QBO
    // network round-trip, not instant), navigate to unrelated Finding B
    // via any toolbar/back button (none are disabled mid-write), and see
    // B's Apply Fix button falsely show "Applying…" and disabled for an
    // operation that has nothing to do with B — including blocking B's own
    // real fix while A's write is still in flight or stuck. Now keyed by
    // `findingID` so a view only ever shows "applying" for its own finding.
    //
    // Gauntlet Loop, Gauntlet B round 20 (2026-08-24): the round-14 fix
    // above only closed the DISPLAY-side bleed — this remained a single
    // `String?`, so the round-19 fix to `findingActionInFlightIDs` was
    // never ported here. Starting Apply Fix on Finding A, then navigating
    // to Finding B and starting Apply Fix on B too (nothing prevented
    // this), overwrote A's marker with B's; A's re-enabled button then let
    // a double-tap launch a SECOND concurrent QBO write against the same
    // purchase line with the same (now stale) `expectedSyncToken` — a real
    // production write racing itself, not a cosmetic duplicate log entry.
    // A `Set<String>` tracks each finding's in-flight write independently.
    public private(set) var applyingFixFindingIDs: Set<String> = []
    /// docs/VOICE_LEDGER_SPEC.md Page 7 (Batch Fixes) — `applyBatchFix`'s
    /// own re-entrancy guard, same shape as `isSyncInFlight`.
    public private(set) var isApplyingBatchFix = false
    /// Which of `stagedFixFindings` are currently checked on the Batch
    /// Fixes screen. Lives here (not local `@State` in a view) because
    /// `RootView`'s screen switch is a computed property, not its own View
    /// struct — `@State` there wouldn't persist across re-renders. Reset on
    /// navigating to the screen fresh is deliberately NOT automatic; a
    /// selection persisting across a `syncAndEvaluate()` that removes an
    /// already-fixed finding is harmless (`toggleBatchFixSelection` below
    /// only ever adds/removes ids that exist).
    public var batchFixSelection: Set<String> = []
    // Gauntlet Loop, Gauntlet B round 13 (2026-08-24): this used to be a
    // bare `String?`, not scoped to a finding — a rejected/failed write on
    // Finding A left the error string standing until the NEXT
    // `applyStagedFix` call (for any finding), since navigating between
    // findings never cleared it. A bookkeeper who saw the error on A, went
    // back, and opened unrelated Finding B would see A's stale error
    // rendered on B — including a reference to A's own transaction id,
    // actively misattributed guidance rather than a merely-missing one.
    // Now keyed by `findingID` so a view only ever renders an error that's
    // actually about the finding it's showing.
    public private(set) var applyFixError: (findingID: String, message: String)?

    /// docs/VOICE_LEDGER_HANDOFF.md D4's write journal — every `.submitted`/
    /// `.success`/`.failed`/`.unknown`/`.ambiguous` entry ever recorded for
    /// this realm, loaded fresh alongside everything else
    /// `loadFromDiskOnly()`/`syncAndEvaluate()` already load. A
    /// `.submitted`/`.unknown` entry is what `applyStagedFix` checks
    /// before allowing a new write to the same purchase+line.
    public private(set) var writeJournal: [WriteJournalEntry] = []
    public private(set) var isResolvingWriteJournalEntryIDs: Set<String> = []
    public private(set) var writeJournalError: String?

    /// Owner directive (2026-08-29): the two AI-generated report buttons'
    /// "since last report" window. `nil` until the first report is ever
    /// generated for this client. The reports' own answer/error/in-flight
    /// state reuses `askAIAnswers`/`secondOpinionAnswers` below (generic,
    /// keyed by `contextKey`) with fixed keys `"health-report"`/
    /// `"value-summary"` — no new state dictionaries needed.
    public private(set) var lastReportGeneratedAt: Date?
    /// Owner directive (2026-08-29): the unified Ask AI conversation
    /// history — replaces voice transcript as the sidebar's "AI
    /// Conversations" screen. Every real question/answer exchange across
    /// every panel, oldest first (same order `ClientStore` persists it in).
    public private(set) var conversationHistory: [AskAIConversationEntry] = []
    /// Owner directive (2026-08-29): explicit feedback after "Mark as
    /// Done"/"I completed this in QBO" — which finding was just checked,
    /// and whether the resync that follows found it still open. `nil`
    /// before any attestation this session, or once the owner navigates
    /// away from the finding it was about.
    public private(set) var attestationOutcome: (findingID: String, stillOpen: Bool)?

    /// Gauntlet Loop, Gauntlet B round 15 (2026-08-24): a fresh critic
    /// found `attestCompletion`/`dismissFinding` both unconditionally did
    /// `screen = .list` after their `do`/`catch`, including when the catch
    /// fired — so a bookkeeper whose dismiss/attest write actually threw
    /// (a real `ClientStore` I/O error) was bounced back to the list
    /// exactly as if it had succeeded, with the only trace being
    /// `loadState.failed`, which no view anywhere reads or renders. Same
    /// per-finding scoping pattern as `applyFixError`, reused for these two
    /// actions rather than a third near-identical field.
    public private(set) var findingActionError: (findingID: String, message: String)?
    /// Gauntlet Loop, Gauntlet B round 18 (2026-08-24): unlike `applyStagedFix`
    /// (which already tracked `applyingFixFindingID`), `dismissFinding`,
    /// `attestCompletion`, `createClientMemoryRule`, and
    /// `recordClientQuestionSent` had no in-flight marker at all, so their
    /// buttons had nothing to disable — an ordinary rapid double-tap fired
    /// two concurrent calls. `ClientStore.dismissFinding` is idempotent at
    /// the status level, but `AppState.dismissFinding` still appended a
    /// second `ActivityLogEntry(kind: .findingDismissed)` unconditionally;
    /// `attestCompletion`/`recordClientQuestionSent`/`createClientMemoryRule`
    /// had no idempotency guard at any layer, so a double-tap produced two
    /// genuinely duplicate log entries or two duplicate `ClientMemoryRule`
    /// rows — a false record in the Activity & Correction Log.
    ///
    /// Gauntlet Loop, Gauntlet B round 19 (2026-08-24), fixed after
    /// consolidation surfaced it clearly: this used to be a single
    /// `String?`, which can only ever name ONE finding as "in flight" —
    /// starting an action on Finding B while Finding A's was still
    /// genuinely in flight would overwrite A's marker with B's, so A's
    /// completion later cleared B's still-running marker (unconditionally,
    /// `= nil`), re-enabling B's buttons and letting a double-tap on B
    /// launch a second concurrent write while the first was still
    /// outstanding — the exact duplicate-`ActivityLogEntry` bug this field
    /// exists to prevent, now reachable across two different findings
    /// instead of just one. A `Set<String>` tracks each finding
    /// independently; two genuinely different findings' actions can be in
    /// flight at once without interfering with each other.
    public private(set) var findingActionInFlightIDs: Set<String> = []

    // Universal Ingestion Tier 1 — Bank Feed Cleanup (Page 4) import state.
    public struct PendingCSVImport {
        public let filename: String
        public let allRows: [[String]]
        public let hasHeaderRow: Bool
        /// From a `MappingHint` matching this file's exact header row, when
        /// one exists — empty when there's no match, meaning the confirm
        /// screen starts blank as before. See `MappingHint`'s doc comment.
        public let suggestedFields: [MappedField]
        public let appliedHint: (id: MappingHintID, timesUsed: Int)?
    }
    public struct PendingOFXImport {
        public let filename: String
        public let rawText: String
        public let transactionCount: Int
        /// The file's own stated ending balance, shown to the user before
        /// confirming. Also the source of `VL-RECON-DIFF-001`'s baseline —
        /// once confirmed, `confirmOFXImport` persists this per account so
        /// later syncs can compare it against QBO's own current balance.
        /// `nil` when the file has no `<LEDGERBAL>`.
        public let statedEndingBalance: Money?
        public let statedAsOfDate: AccountingDate?
    }
    public enum PendingImport {
        case csv(PendingCSVImport)
        case ofx(PendingOFXImport)
    }
    public private(set) var pendingImport: PendingImport?
    public private(set) var importError: String?
    /// Fixed 2026-09-05 — was a documented, deliberately-deferred gap
    /// (Gauntlet Loop, Gauntlet B round 21, 2026-08-24): the same "single
    /// scalar meant for one in-flight operation, actually shared across
    /// however many a user can start" shape that
    /// `applyingFixFindingIDs`/`findingActionInFlightIDs` had before
    /// rounds 19/20 fixed them. `ImportBankStatementView`'s Cancel was
    /// never disabled while `confirmCSVImport`/`confirmOFXImport` awaited
    /// — cancelling and starting a second import on a different file let
    /// the FIRST import's `Task` resuming later unconditionally overwrite
    /// `pendingImport`/`importError`, silently discarding the second
    /// import's confirm-sheet state (or a real newer error). Applied the
    /// simpler of the two fixes the deferred writeup suggested: only one
    /// import confirm can be in flight at a time, `cancelPendingImport()`
    /// is a no-op while this is true, and the view layer disables Cancel
    /// (and Confirm) for the same reason — belt and suspenders, since a
    /// disabled button can still be raced by a rapid double-tap before
    /// SwiftUI re-renders, but the state-layer guard cannot be.
    public private(set) var isConfirmingImport = false
    /// Loaded on launch and refreshed after every confirmed CSV import —
    /// `selectFileForImport` reads this in-memory cache rather than
    /// hitting the store itself on every call (it gained an `async`
    /// context when Tier 2/OCR was added, but there's still no reason to
    /// re-read the store just to check for a matching mapping hint).
    public private(set) var mappingHints: [MappingHint] = []
    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Client Memory, With
    /// Approval" — loaded at launch and refreshed after every mutation,
    /// same caching reason as `mappingHints`.
    public private(set) var clientMemoryRules: [ClientMemoryRule] = []
    /// See `removeClientMemoryRule`'s doc comment — page-scoped in-flight
    /// guard and error, keyed by `ClientMemoryRule.id`, mirroring the
    /// finding surface's `findingActionInFlightIDs`/`findingActionError`.
    public private(set) var clientMemoryActionInFlightIDs: Set<String> = []
    public private(set) var clientMemoryActionError: (ruleID: String, message: String)?

    // Month-End Close checklist (Page 11) state.
    public private(set) var checklistCompletions: [ChecklistItemCompletion] = []
    public private(set) var carryForwardMarks: [CarryForwardMark] = []

    // Reporting (Page 12) state.
    public private(set) var balanceSheetLines: [ReportLine] = []
    public private(set) var isLoadingBalanceSheet = false
    public private(set) var balanceSheetError: String?
    public private(set) var profitAndLossLines: [ReportLine] = []
    public private(set) var isLoadingProfitAndLoss = false
    public private(set) var profitAndLossError: String?
    public private(set) var cashFlowLines: [ReportLine] = []
    public private(set) var isLoadingCashFlow = false
    public private(set) var cashFlowError: String?
    public private(set) var trialBalanceLines: [TrialBalanceLine] = []
    public private(set) var isLoadingTrialBalance = false
    public private(set) var trialBalanceError: String?
    public private(set) var agedReceivablesLines: [AgingLine] = []
    public private(set) var isLoadingAgedReceivables = false
    public private(set) var agedReceivablesError: String?
    public private(set) var agedPayablesLines: [AgingLine] = []
    public private(set) var isLoadingAgedPayables = false
    public private(set) var agedPayablesError: String?
    public private(set) var generalLedgerLines: [GeneralLedgerLine] = []
    public private(set) var isLoadingGeneralLedger = false
    public private(set) var generalLedgerError: String?

    /// Variance analysis (docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close
    /// Package section) — this period's Balance Sheet/P&L against the
    /// immediately prior calendar month, both real QBO data. Loaded
    /// separately from the current-period reports above (a second fetch,
    /// against a different period) rather than reusing them.
    public private(set) var priorPeriodBalanceSheetLines: [ReportLine] = []
    public private(set) var priorPeriodProfitAndLossLines: [ReportLine] = []
    public private(set) var isLoadingVarianceAnalysis = false
    public private(set) var varianceAnalysisError: String?

    /// docs/VOICE_LEDGER_SPEC.md Page 9 (Sales Tax Review) — codes/rates/
    /// agencies only, see `Core/SalesTax.swift`'s doc comment for what's
    /// not built (liability balances, transaction-level detail).
    public private(set) var taxCodes: [TaxCode] = []
    public private(set) var taxRates: [TaxRate] = []
    public private(set) var taxAgencies: [TaxAgency] = []
    public private(set) var isLoadingSalesTax = false
    public private(set) var salesTaxError: String?
    public private(set) var salesTaxAttestation = SalesTaxAttestation()

    /// docs/VOICE_LEDGER_SPEC.md Page 10 (Taxes) — see `Core/TaxEstimate
    /// .swift`'s doc comment: `ratePercent` is entirely the user's own
    /// input, never defaulted or guessed by this app.
    public private(set) var taxEstimateSettings = TaxEstimateSettings()

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit — every connected client's
    /// summary, from the backend's own connection registry plus a
    /// READ-ONLY local read of each client's own `ClientStore` (never a
    /// live QBO sync — that stays exclusive to whichever realm this
    /// `AppState` is actively running as).
    public private(set) var firmCockpitSummaries: [ClientCockpitSummary] = []
    public private(set) var isLoadingFirmCockpit = false
    public private(set) var firmCockpitError: String?
    /// docs/VOICE_LEDGER_SPEC.md's Client Switcher. `AppState` deliberately
    /// has no idea HOW to build another `AppState` (it would need its own
    /// `backend`/`ClientStore`/period, a different concern entirely) — it
    /// only owns the trigger and the in-flight/error UI state. The actual
    /// re-instantiation is `VoiceLedgerApp.swift`'s job, wired in here as a
    /// callback exactly once at construction.
    public var onSwitchToClient: ((RealmID, QBOEnvironment) async -> Void)?
    public private(set) var isSwitchingClient = false
    public private(set) var switchClientError: String?

    public let realmID: RealmID
    public let period: AccountingPeriod
    /// Exposed read-only so the view layer can filter period-scoped state
    /// (e.g. `checklistCompletions`) without duplicating the period value.
    public var currentPeriod: AccountingPeriod { period }
    /// docs/VOICE_LEDGER_SPEC.md's Client Switcher/Firm Cockpit —
    /// exposed read-only so a view can tell which connected client THIS
    /// `AppState` instance is currently running as, without waiting on
    /// `companyInfo` (only populated after the first health check).
    public var currentRealmID: RealmID { realmID }
    private let backend: BackendClient
    private let syncClient: QBOSyncClient
    private let store: ClientStore
    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit — the same Application
    /// Support root every realm's `ClientStore` lives under
    /// (`VoiceLedgerApp.swift`'s `configure()`), needed here to construct
    /// a READ-ONLY `ClientStore` for OTHER connected realms (never the
    /// live, actively-synced one this `AppState` itself owns). `nil` for
    /// callers that never pass it (`voiceledger-devtool`, tests) — Firm
    /// Cockpit simply reports unavailable rather than crashing.
    private let clientStoreRootDirectory: URL?
    private let engine: RuleEngine
    /// docs/VOICE_LEDGER_SPEC.md's `/voice` module. Assigned at the END of
    /// `init` below (once every other stored property has a value), not in
    /// this property's own initializer — `@Observable`'s macro expansion
    /// doesn't support `lazy`, and `VoiceEngine` holds an `unowned`
    /// reference back to this `AppState`, which can't be passed until
    /// `self` is fully initialized.
    public private(set) var voiceEngine: VoiceEngine!

    public init(realmID: RealmID, environment: QBOEnvironment, period: AccountingPeriod, backend: BackendClient, store: ClientStore, clientStoreRootDirectory: URL? = nil) {
        self.realmID = realmID
        self.environment = environment
        self.period = period
        self.backend = backend
        self.syncClient = QBOSyncClient(backend: backend)
        self.store = store
        self.clientStoreRootDirectory = clientStoreRootDirectory
        // All rules, not just Page 3's — Cleanup Assessment's rules must be
        // evaluated in the SAME engine call for §8.2a's relationship
        // gating to see both classes together (RuleEngineActor.swift).
        self.engine = RuleEngine(rules: RuleRegistry.all)
        self.voiceEngine = VoiceEngine(appState: self)
    }

    // Gauntlet Loop, Gauntlet C round 8 (2026-08-24): had the identical
    // pre-round-4 shape `syncAndEvaluate()` used to have — each `self.`
    // publish landed as its own `load` call succeeded, not resolved into
    // locals first. `ClientStore` is one independent JSON file per data
    // type; a single corrupted file (a real failure mode for this exact
    // storage design — a crash mid-write, a partial disk write) makes a
    // LATER call in the sequence throw while EARLIER ones have already
    // published real fresh data, leaving the app in a mixed fresh/stale
    // state with no way to tell which properties are which.
    // `RootView.swift`'s Month-End Close screen reads `checklistCompletions`
    // with zero staleness gating — if that load never completed, every
    // checklist item would render as confidently "not completed," a
    // specific wrong claim, not an honest gray state. All five loads are
    // now resolved into locals first; the five `self.` assignments that
    // follow have zero `await`/`try` between them, matching
    // `syncAndEvaluate()`'s atomic block exactly.
    public func loadFromDiskOnly() async {
        loadState = .loading
        do {
            let newFindings = try await store.loadFindings()
            let newActivityLog = try await store.loadActivityLog()
            let newChecklistCompletions = try await store.loadChecklistCompletions()
            let newMappingHints = try await store.loadMappingHints()
            let newClientMemoryRules = try await store.loadClientMemoryRules()
            let newEngagementScope = try await store.loadEngagementScope()
            let newPeriodLock = try await store.loadPeriodLock()
            let newCarryForwardMarks = try await store.loadCarryForwardMarks()
            let newSalesTaxAttestation = try await store.loadSalesTaxAttestation()
            let newTaxEstimateSettings = try await store.loadTaxEstimateSettings()
            let newWriteJournal = try await store.loadWriteJournal()
            let newLastReportGeneratedAt = try await store.loadLastReportGeneratedAt()
            let newConversationHistory = try await store.loadAskAIConversationHistory()
            let newHistorySnapshot = try? await store.loadHistorySnapshot()
            // Stores written before last-synced-at existed fall back to the
            // newest QBO read time recorded on the saved findings.
            let newestFindingRead = newFindings.flatMap(\.provenance).compactMap { provenance -> Date? in
                if case .qboAPI(let readAt) = provenance { return readAt }
                return nil
            }.max()
            let newCachedSyncedAt = ((try? await store.loadLastSyncedAt()) ?? nil) ?? newestFindingRead
            let newUnreconciledMonths = (try? await store.loadUnreconciledMonths()) ?? 0
            findings = newFindings
            activityLog = newActivityLog
            checklistCompletions = newChecklistCompletions
            mappingHints = newMappingHints
            clientMemoryRules = newClientMemoryRules
            engagementScope = newEngagementScope
            periodLock = newPeriodLock
            carryForwardMarks = newCarryForwardMarks
            salesTaxAttestation = newSalesTaxAttestation
            taxEstimateSettings = newTaxEstimateSettings
            writeJournal = newWriteJournal
            lastReportGeneratedAt = newLastReportGeneratedAt
            conversationHistory = newConversationHistory
            historySnapshot = newHistorySnapshot ?? nil
            cachedSyncedAt = newCachedSyncedAt
            unreconciledMonths = newUnreconciledMonths
            practiceProfile = (try? await store.loadPracticeProfile()) ?? ClientPracticeProfile()
            plannedCashItems = (try? await store.loadPlannedCashItems()) ?? []
            scopeRequests = (try? await store.loadScopeRequests()) ?? []
            newAccountAlerts = (try? await store.loadNewAccountAlerts()) ?? []
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Practice tools (owner directive 2026-10-02)

    /// This client's filings and industry (per realm).
    public private(set) var practiceProfile = ClientPracticeProfile()
    public private(set) var plannedCashItems: [PlannedCashItem] = []
    public private(set) var scopeRequests: [ScopeRequest] = []
    public private(set) var newAccountAlerts: [NewAccountAlert] = []
    /// Firm-wide preset prices for the Scope Requests buttons.
    public private(set) var scopePresets: [ScopePreset] = AppState.loadScopePresets()

    public var openNewAccountAlerts: [NewAccountAlert] { newAccountAlerts.filter { $0.acknowledgedAt == nil } }

    public var complianceDeadlines: [ComplianceDeadline] {
        ComplianceCalendar.deadlines(for: practiceProfile, from: AccountingDate(date: Date()), days: 120)
    }

    public var complianceChecks: [ComplianceCheck] { ComplianceCalendar.checks(for: practiceProfile) }

    /// Invoices for the nexus screen: the 24-month history, else this month.
    public var nexusRows: [NexusStateRow] {
        let pool = (historySnapshot?.transactions ?? []) + (historySnapshot == nil ? transactions : [])
        return EconomicNexusScreen.rows(sales: pool, homeState: practiceProfile.state, taxAgencyNames: taxAgencies.map(\.displayName), asOf: AccountingDate(date: Date()))
    }

    /// Why the nexus screen may be incomplete, or nil when it has what it needs.
    public var nexusNote: String? {
        guard let history = historySnapshot else { return "Only this month's invoices are loaded. Load the 24-month history for a full 12 months." }
        let invoices = history.transactions.filter { $0.entityKind == .invoice }
        if !invoices.isEmpty && invoices.allSatisfy({ $0.customerState == nil }) {
            return "The saved history predates state tracking. Reload the 24-month history to read customer states."
        }
        return nil
    }

    /// Cash in the bank right now: QuickBooks' current balance of every bank account.
    /// The balance sheet's figure is as of the reviewed month's end, which is the
    /// wrong start for a forecast that runs forward from today (owner test 2026-10-02).
    public var currentBankCash: Money? {
        let banks = accounts.filter { $0.accountType == .bank }
        guard let first = banks.first else { return nil }
        return Money(minorUnits: banks.reduce(0) { $0 + $1.currentBalance.minorUnits }, currency: first.currentBalance.currency)
    }

    public var thirteenWeekForecast: ThirteenWeekForecast? {
        guard let cash = currentBankCash ?? FinancialKPIs.cashBalance(from: balanceSheetLines) else { return nil }
        return ThirteenWeekForecastEngine.compute(currentCash: cash, agedReceivablesLines: agedReceivablesLines, agedPayablesLines: agedPayablesLines,
                                                  recurringVendors: recurringVendors, planned: plannedCashItems, asOf: AccountingDate(date: Date()))
    }

    public var inventoryReview: InventoryReview? {
        let known = accounts.isEmpty ? (historySnapshot?.accounts ?? []) : accounts
        guard historySnapshot != nil || !known.isEmpty else { return nil }
        return InventoryReview.build(monthlyProfitAndLoss: historySnapshot?.monthlyProfitAndLoss ?? [], accounts: known,
                                     count: practiceProfile.inventoryCount, countDate: practiceProfile.inventoryCountDate)
    }

    public func saveInventoryCount(_ amount: Money, on date: AccountingDate) async {
        var p = practiceProfile
        p.inventoryCount = amount
        p.inventoryCountDate = date
        await updatePracticeProfile(p)
    }

    public var industryComparison: IndustryTemplate.Comparison {
        IndustryTemplate.compare(practiceProfile.industry, accounts: accounts.isEmpty ? (historySnapshot?.accounts ?? []) : accounts)
    }

    public func updatePracticeProfile(_ profile: ClientPracticeProfile) async {
        var p = profile
        p.reviewed = true
        practiceProfile = p
        try? await store.savePracticeProfile(p)
    }

    public func addPlannedCashItem(_ item: PlannedCashItem) async {
        plannedCashItems.append(item)
        try? await store.savePlannedCashItems(plannedCashItems)
    }

    public func removePlannedCashItem(id: String) async {
        plannedCashItems.removeAll { $0.id == id }
        try? await store.savePlannedCashItems(plannedCashItems)
    }

    public func addScopeRequest(_ request: ScopeRequest) async {
        scopeRequests.insert(request, at: 0)
        try? await store.saveScopeRequests(scopeRequests)
    }

    public func updateScopeRequest(_ request: ScopeRequest) async {
        guard let i = scopeRequests.firstIndex(where: { $0.id == request.id }) else { return }
        scopeRequests[i] = request
        try? await store.saveScopeRequests(scopeRequests)
    }

    public func removeScopeRequest(id: String) async {
        scopeRequests.removeAll { $0.id == id }
        try? await store.saveScopeRequests(scopeRequests)
    }

    private static let scopePresetsDefaultsKey = "scopePresets.v1"

    static func loadScopePresets() -> [ScopePreset] {
        guard let data = UserDefaults.standard.data(forKey: scopePresetsDefaultsKey),
              let saved = try? JSONDecoder().decode([ScopePreset].self, from: data), !saved.isEmpty else { return ScopePreset.defaults }
        return saved
    }

    public func updateScopePresets(_ presets: [ScopePreset]) {
        scopePresets = presets
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: Self.scopePresetsDefaultsKey) }
    }

    public func resetScopePresets() { updateScopePresets(ScopePreset.defaults) }

    /// After each sync: record watched accounts, alert on ones not seen before.
    private func checkForNewAccounts(_ synced: [LedgerAccount]) async {
        let baseline = (try? await store.loadKnownAccountsBaseline()) ?? KnownAccountsBaseline()
        let result = NewAccountWatch.check(baseline: baseline, accounts: synced)
        try? await store.saveKnownAccountsBaseline(result.baseline)
        guard !result.newAlerts.isEmpty else { return }
        newAccountAlerts += result.newAlerts
        try? await store.saveNewAccountAlerts(newAccountAlerts)
    }

    public func acknowledgeNewAccount(id: String) async {
        guard let i = newAccountAlerts.firstIndex(where: { $0.accountID == id }) else { return }
        newAccountAlerts[i].acknowledgedAt = Date()
        try? await store.saveNewAccountAlerts(newAccountAlerts)
    }

    public func setUnreconciledMonths(_ months: Int) async {
        unreconciledMonths = months
        try? await store.saveUnreconciledMonths(months)
    }

    public func loadHistory(months: Int = 24) async {
        guard !isLoadingHistory else { return }
        isLoadingHistory = true
        historyError = nil
        defer { isLoadingHistory = false }
        do {
            let snapshot = try await syncClient.syncHistory(realmID: realmID, months: months, through: AccountingDate(date: Date()))
            try await store.saveHistorySnapshot(snapshot)
            historySnapshot = snapshot
        } catch {
            historyError = "\(error)"
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 2 — sets Voice Ledger's own stricter
    /// period lock. Never touches QBO; only this app's own screens read it.
    public func setPeriodLock(through: AccountingPeriod, actorName: String, note: String?) async {
        do {
            let lock = PeriodLock(lockedThrough: through, lockedBy: actorName, note: note)
            try await store.savePeriodLock(lock)
            periodLock = lock

            // VL-CLOSED-PERIOD-DRIFT-001's baseline. Fetched live, right now
            // — not from `self.trialBalanceLines`, which may be stale or for
            // a different period than `through` if the bookkeeper is
            // locking a period other than whatever they last viewed on the
            // Trial Balance page. Best-effort: a fetch failure here must not
            // fail the lock itself, same posture as every other optional
            // report fetch in this file — it just means the drift check
            // reports .cannotEvaluate until the period is re-locked.
            if let lines = try? await syncClient.fetchTrialBalance(realmID: realmID, period: through), !lines.isEmpty {
                let snapshot = PeriodLockSnapshot.capture(lockedThrough: through, from: lines)
                try? await store.savePeriodLockSnapshot(snapshot)
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// The reverse of `setPeriodLock` — a lock set in error must be as
    /// removable as a checklist completion.
    public func clearPeriodLock() async {
        do {
            try await store.clearPeriodLock()
            periodLock = nil
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 2 — records engagement scope and the
    /// QBOA-access attestation. Unverifiable via API by design (CLAUDE.md:
    /// attestation is recorded, not proof).
    public func updateEngagementScope(_ scope: EngagementScope) async {
        do {
            try await store.saveEngagementScope(scope)
            engagementScope = scope
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 11 — a human attestation, recorded not
    /// treated as proof (§11.4's same posture for finding completion).
    public func completeChecklistItem(_ itemID: ChecklistItemID, actorName: String, note: String?) async {
        do {
            // docs/VOICE_LEDGER_HANDOFF.md D3 — captured at completion
            // time so a later rule-version bump or materiality change can
            // be detected as staling this attestation (`AppState
            // .currentEvidenceWatermark`).
            let completion = ChecklistItemCompletion(itemID: itemID, period: period, completedBy: actorName, note: note, watermark: Self.currentEvidenceWatermark())
            try await store.upsertChecklistCompletion(completion)
            checklistCompletions = try await store.loadChecklistCompletions()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// docs/VOICE_LEDGER_HANDOFF.md D3's watermark, computed fresh — never
    /// cached, so a rule version bump takes effect on the very next call
    /// with no migration step of its own.
    static func currentEvidenceWatermark() -> EvidenceWatermark {
        // A `\.identity` keypath on `[any Rule.Type]` crashes SILGen
        // (Swift 6.3.3, existential-metatype keypath lowering) — an
        // explicit closure sidesteps the same compiler bug.
        let identities = RuleRegistry.all.map { ruleType in ruleType.identity }
        return EvidenceWatermark.current(ruleIdentities: identities, materiality: .defaultPolicy)
    }

    public func uncompleteChecklistItem(_ itemID: ChecklistItemID) async {
        do {
            try await store.removeChecklistCompletion(itemID: itemID, period: period)
            checklistCompletions = try await store.loadChecklistCompletions()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Real bug, found live 2026-09-17: every one of this file's `catch { X
    /// = error.localizedDescription }` blocks displayed whatever Foundation
    /// happened to produce for a cancelled request verbatim — on this app's
    /// bare SPM-built bundle (no Xcode-generated Foundation/CFNetwork
    /// localization resources), `URLError(.cancelled)`'s
    /// `localizedDescription` collapses to the single word "cancelled"
    /// instead of a full sentence, and that word rendered directly in a
    /// report page's error banner — live-reproduced by switching pages
    /// fast enough to cancel an in-flight report fetch (SwiftUI cancels a
    /// `.task {}`'s work when its view disappears). A cancelled request
    /// isn't a real failure worth telling the bookkeeper about — either
    /// they navigated away, or a fresh load superseded it — so every load
    /// call below now swallows it instead of surfacing raw error text.
    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 12 — a separate, on-demand fetch, not
    /// part of `syncAndEvaluate()`: a report read is comparatively
    /// expensive and no rule currently consumes it.
    public func loadBalanceSheet() async {
        isLoadingBalanceSheet = true
        balanceSheetError = nil
        do {
            balanceSheetLines = try await syncClient.fetchBalanceSheet(realmID: realmID, period: period)
        } catch {
            if !Self.isCancellation(error) {
                balanceSheetError = error.localizedDescription
            }
        }
        isLoadingBalanceSheet = false
    }

    public func loadProfitAndLoss() async {
        isLoadingProfitAndLoss = true
        profitAndLossError = nil
        do {
            profitAndLossLines = try await syncClient.fetchProfitAndLoss(realmID: realmID, period: period)
        } catch {
            if !Self.isCancellation(error) {
                profitAndLossError = error.localizedDescription
            }
        }
        isLoadingProfitAndLoss = false
    }

    public func loadCashFlow() async {
        isLoadingCashFlow = true
        cashFlowError = nil
        do {
            cashFlowLines = try await syncClient.fetchCashFlow(realmID: realmID, period: period)
        } catch {
            if !Self.isCancellation(error) {
                cashFlowError = error.localizedDescription
            }
        }
        isLoadingCashFlow = false
    }

    public func loadTrialBalance() async {
        isLoadingTrialBalance = true
        trialBalanceError = nil
        do {
            trialBalanceLines = try await syncClient.fetchTrialBalance(realmID: realmID, period: period)
        } catch {
            if !Self.isCancellation(error) {
                trialBalanceError = error.localizedDescription
            }
        }
        isLoadingTrialBalance = false
    }

    public func loadAgedReceivables() async {
        isLoadingAgedReceivables = true
        agedReceivablesError = nil
        do {
            agedReceivablesLines = try await syncClient.fetchAgedReceivables(realmID: realmID)
        } catch {
            if !Self.isCancellation(error) {
                agedReceivablesError = error.localizedDescription
            }
        }
        isLoadingAgedReceivables = false
    }

    public func loadAgedPayables() async {
        isLoadingAgedPayables = true
        agedPayablesError = nil
        do {
            agedPayablesLines = try await syncClient.fetchAgedPayables(realmID: realmID)
        } catch {
            if !Self.isCancellation(error) {
                agedPayablesError = error.localizedDescription
            }
        }
        isLoadingAgedPayables = false
    }

    /// Owner directive (2026-09-06): "recurring-vendor detection" needs
    /// several months of `Purchase` history to tell a real pattern from
    /// a coincidence — a single period's data (everything else in this
    /// file) isn't enough. Loops `fetchPurchases` per trailing period —
    /// the same call `VL-VEND-PRICE-001` already makes for exactly one
    /// prior period — rather than requiring a new backend endpoint.
    /// `try?`-wrapped per period, same posture as `syncAndEvaluate()`'s
    /// independent report fetches: one month's fetch failing (or
    /// genuinely having zero purchases) must not blank out the other
    /// five months' real data.
    public private(set) var trailingPurchases: [LedgerTransaction] = []
    public private(set) var isLoadingTrailingPurchases = false

    public static let trailingPurchasesMonths = 6

    public func loadTrailingPurchases() async {
        isLoadingTrailingPurchases = true
        var collected: [LedgerTransaction] = []
        var scanPeriod = period
        for _ in 0..<Self.trailingPurchasesMonths {
            if let fetched = try? await syncClient.fetchPurchases(realmID: realmID, period: scanPeriod) {
                collected.append(contentsOf: fetched)
            }
            scanPeriod = scanPeriod.previousMonth
        }
        trailingPurchases = collected
        isLoadingTrailingPurchases = false
    }

    /// Deterministic over already-loaded `trailingPurchases` — recomputed
    /// on every access rather than cached, since the input is bounded
    /// (a few hundred transactions at most) and this keeps it impossible
    /// for a stale cached result to survive a `trailingPurchases` reload.
    public var recurringVendors: [RecurringVendor] {
        RecurringVendorDetector.detect(from: trailingPurchases)
    }

    public var missingRecurringVendors: [RecurringVendor] {
        // The scan covers the six months ENDING at the period being reviewed,
        // so "overdue" is judged at that period's end (or today, if sooner).
        // Judging a July review against October's date flagged every
        // monthly vendor as overdue (owner screenshot 2026-10-02).
        let periodEnd = AccountingDate(year: period.year, month: period.month, day: period.daysInMonth)
        let today = AccountingDate(date: Date())
        return RecurringVendorDetector.missingAsOf(recurringVendors, asOf: min(periodEnd, today))
    }

    /// Owner directive (2026-09-06): "build cash flow forecasting" — see
    /// `CashFlowForecastEngine`'s own doc comment for the model. `asOf`
    /// is real wall-clock "today," not this client's loaded accounting
    /// period end, since the forecast is inherently forward-looking from
    /// right now.
    public var cashFlowForecast: CashFlowForecast {
        CashFlowForecastEngine.compute(
            currentCash: FinancialKPIs.cashBalance(from: balanceSheetLines),
            agedReceivablesLines: agedReceivablesLines,
            agedPayablesLines: agedPayablesLines,
            recurringVendors: recurringVendors,
            asOf: AccountingDate(date: Date())
        )
    }

    public func loadGeneralLedger() async {
        isLoadingGeneralLedger = true
        generalLedgerError = nil
        do {
            generalLedgerLines = try await syncClient.fetchGeneralLedger(realmID: realmID, period: period)
        } catch {
            if !Self.isCancellation(error) {
                generalLedgerError = error.localizedDescription
            }
        }
        isLoadingGeneralLedger = false
    }

    /// Fetches the immediately prior calendar month's Balance Sheet and
    /// P&L — real QBO reports for a real prior period, not an estimate.
    /// Both requests run concurrently; either can fail independently
    /// without blocking the other (same `try?`-per-report posture already
    /// used in `syncAndEvaluate()` for optional report data).
    public func loadVarianceAnalysis() async {
        isLoadingVarianceAnalysis = true
        varianceAnalysisError = nil
        let priorPeriod = period.previousMonth
        async let priorBalanceSheet = try? syncClient.fetchBalanceSheet(realmID: realmID, period: priorPeriod)
        async let priorProfitAndLoss = try? syncClient.fetchProfitAndLoss(realmID: realmID, period: priorPeriod)
        let (bs, pl) = await (priorBalanceSheet, priorProfitAndLoss)
        if bs == nil && pl == nil {
            varianceAnalysisError = "Could not load \(priorPeriod.year)-\(String(format: "%02d", priorPeriod.month))'s reports to compare against."
        }
        priorPeriodBalanceSheetLines = bs ?? []
        priorPeriodProfitAndLossLines = pl ?? []
        isLoadingVarianceAnalysis = false
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 9 (Sales Tax Review). All three
    /// fetched concurrently; each can fail independently without blocking
    /// the others, same `try?`-per-report posture `loadVarianceAnalysis`
    /// already uses.
    public func loadSalesTaxProfile() async {
        isLoadingSalesTax = true
        salesTaxError = nil
        async let codes = try? syncClient.fetchTaxCodes(realmID: realmID)
        async let rates = try? syncClient.fetchTaxRates(realmID: realmID)
        async let agencies = try? syncClient.fetchTaxAgencies(realmID: realmID)
        let (c, r, a) = await (codes, rates, agencies)
        if c == nil && r == nil && a == nil {
            salesTaxError = "Could not load sales tax data for this company."
        }
        taxCodes = c ?? []
        taxRates = r ?? []
        taxAgencies = a ?? []
        isLoadingSalesTax = false
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit. Fetches the backend's
    /// connection registry (every realm ever authorized, live — never
    /// cached), then for each one reads its own local `ClientStore`
    /// READ-ONLY to build a summary. One client's read failing (a realm
    /// whose local store hasn't been created yet, e.g. connected but
    /// never synced) does not fail the others — matches this app's
    /// existing "one report failing must not fail the whole sync" posture
    /// (`syncAndEvaluate()`), applied here across clients instead of
    /// across reports for one client.
    /// docs/VOICE_LEDGER_SPEC.md's Client Switcher — the trigger. Delegates
    /// entirely to `onSwitchToClient` (see that property's doc comment for
    /// why); this method's own job is just the in-flight/error UI state
    /// every other async action in this file already follows the same
    /// shape for. A no-op (never sets `isSwitchingClient`) if the app
    /// layer never wired the callback — e.g. a test or CLI context that
    /// has no notion of "another AppState to switch to."
    public func switchActiveClient(to targetRealmID: RealmID, environment targetEnvironment: QBOEnvironment) async {
        guard let onSwitchToClient, !isSwitchingClient else { return }
        isSwitchingClient = true
        switchClientError = nil
        await onSwitchToClient(targetRealmID, targetEnvironment)
        // Deliberately does NOT set `isSwitchingClient = false` on success —
        // a successful switch replaces this ENTIRE AppState instance (the
        // app layer swaps which one `RootView` displays), so there is no
        // "this instance, now idle" state to return to; only a failure
        // leaves this same instance still active and needing to reset.
        // `failClientSwitch` is `onSwitchToClient`'s only way back into
        // this instance on the failure path.
    }

    /// Called by `onSwitchToClient` (app layer) to get a fresh session
    /// token for the target realm, using THIS `AppState`'s own `backend`
    /// connection — the one piece of the switch the app layer genuinely
    /// cannot do itself, since `backend`/its session token are private to
    /// whichever `AppState` currently holds a valid one. Everything else
    /// about building the new `AppState` (a new `ClientStore`, a new
    /// `BackendClient` pointed at the new token) is the app layer's job,
    /// not this one's — this method's only responsibility is the one
    /// privileged call only the currently-active session can make.
    public func requestSwitchSessionToken(forRealmID targetRealmID: RealmID) async throws -> String {
        try await backend.requestSession(forRealmID: targetRealmID)
    }

    /// Called by `onSwitchToClient` (app layer) when the switch attempt
    /// itself fails — never called on success, since success means this
    /// `AppState` instance is about to be replaced, not updated.
    /// Set by the app layer, which owns what to show after the active
    /// client disappears (see `VoiceLedgerApp.performDisconnect`).
    public var onDisconnectClient: (() async -> Void)?
    public private(set) var isDisconnecting = false
    public private(set) var disconnectError: String?

    public func disconnectActiveClient() async {
        guard let onDisconnectClient, !isDisconnecting else { return }
        isDisconnecting = true
        disconnectError = nil
        await onDisconnectClient()
    }

    public func revokeConnection() async throws -> DisconnectResult {
        try await backend.disconnect(realmID: realmID)
    }

    public func connectedClients() async throws -> [ConnectedClient] {
        try await backend.getConnections()
    }

    public func failDisconnect(_ message: String) {
        isDisconnecting = false
        disconnectError = message
    }

    public func failClientSwitch(_ message: String) {
        isSwitchingClient = false
        switchClientError = message
    }

    public func loadFirmCockpit() async {
        isLoadingFirmCockpit = true
        firmCockpitError = nil
        do {
            // Owner-reported bug (2026-09-06): Firm Cockpit showed
            // "(unnamed company)" for the ACTIVE client even though every
            // other page in the app has its real name — the backend's own
            // connection record never got a company name written to it at
            // connect time, but `companyInfo` (fetched live from QBO on
            // this client's own connect/sync) already has it. Backfilling
            // only the active realm's row here is honest, not a guess:
            // it's the exact same name already trusted and displayed
            // everywhere else in this running session.
            let connections = try await backend.getConnections().map { connection -> ConnectedClient in
                guard connection.realmID == realmID, connection.companyName == nil, let activeName = companyInfo?.companyName else { return connection }
                return ConnectedClient(
                    realmID: connection.realmID,
                    companyName: activeName,
                    environment: connection.environment,
                    writeEnabled: connection.writeEnabled,
                    lastHealthCheckAt: connection.lastHealthCheckAt,
                    lastHealthCheckStatus: connection.lastHealthCheckStatus
                )
            }
            guard let rootDirectory = clientStoreRootDirectory else {
                firmCockpitSummaries = []
                firmCockpitError = "Firm Cockpit needs a local store location this session wasn't given."
                isLoadingFirmCockpit = false
                return
            }
            var summaries: [ClientCockpitSummary] = []
            for connection in connections {
                guard let clientStore = try? ClientStore(realmID: connection.realmID, rootDirectory: rootDirectory) else { continue }
                async let findingsResult = try? clientStore.loadFindings()
                async let checklistResult = try? clientStore.loadChecklistCompletions()
                async let importedResult = try? clientStore.loadImportedStatementLines()
                async let activityResult = try? clientStore.loadActivityLog()
                async let historyResult = try? clientStore.loadHistorySnapshot()
                let (f, c, imported, activity, history) = await (findingsResult, checklistResult, importedResult, activityResult, historyResult)
                let profile = try? await clientStore.loadPracticeProfile()
                let alerts = (try? await clientStore.loadNewAccountAlerts()) ?? []
                summaries.append(FirmCockpit.summarize(
                    client: connection,
                    findings: f ?? [],
                    checklistCompletions: c ?? [],
                    period: period,
                    importedStatementLineCount: (imported ?? []).count,
                    activityLog: activity ?? [],
                    history: history ?? nil,
                    practiceProfile: profile,
                    newAccountAlerts: alerts
                ))
            }
            firmCockpitSummaries = summaries
        } catch {
            if !Self.isCancellation(error) {
                firmCockpitError = error.localizedDescription
            }
        }
        isLoadingFirmCockpit = false
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 9 — records the filing-status
    /// attestation. Unverifiable via API by design (`CLAUDE.md`:
    /// attestation is recorded, not proof).
    public func updateSalesTaxAttestation(_ attestation: SalesTaxAttestation) async {
        do {
            try await store.saveSalesTaxAttestation(attestation)
            salesTaxAttestation = attestation
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 10 — records the user-supplied rate
    /// `TaxEstimate.estimatedSetAside` multiplies by. This app never
    /// proposes a rate of its own; it only stores whatever the user typed.
    public func updateTaxEstimateSettings(_ settings: TaxEstimateSettings) async {
        do {
            try await store.saveTaxEstimateSettings(settings)
            taxEstimateSettings = settings
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// docs/phase-0/02_QBO_CAPABILITY_MATRIX.md row C1: a live, timestamped
    /// call, never a cached assumption — the same guarantee
    /// `voiceledger-devtool health` already proved from the CLI, now
    /// reachable from inside the app itself (step 1.3).
    public func checkHealth() async {
        isCheckingHealth = true
        healthCheckError = nil
        // Three independent reads: one failing must not blank the others.
        // Seen 2026-09-30: QBO's CompanyInfo endpoint returned "System
        // Failure" (code 10000) for an hour while every other read worked.
        async let health = Result { try await backend.healthCheck(realmID: realmID) }
        async let info = Result { try await syncClient.fetchCompanyInfo(realmID: realmID) }
        async let writeAccess = Result { try await backend.getWriteAccess(realmID: realmID) }
        let (healthR, infoR, writeR) = await (health, info, writeAccess)
        if case .success(let v) = healthR { healthResult = v }
        if case .success(let v) = writeR { writeAccessEnabled = v }
        switch infoR {
        case .success(let v):
            companyInfo = v
            UserDefaults.standard.set(v.companyName, forKey: "companyName:\(realmID.rawValue)")
        case .failure(let error):
            if !Self.isCancellation(error) { healthCheckError = "Company name couldn't be read from QuickBooks: \(error.localizedDescription)" }
        }
        if case .failure(let error) = healthR, !Self.isCancellation(error) { healthCheckError = error.localizedDescription }
        isCheckingHealth = false
    }

    /// The company name to show: live if loaded, else the name from the last
    /// successful read (so a transient QuickBooks fault never blanks the UI).
    public var displayCompanyName: String {
        if let name = companyInfo?.companyName { return name }
        if let cached = UserDefaults.standard.string(forKey: "companyName:\(realmID.rawValue)"), !cached.isEmpty { return cached }
        return "No company connected"
    }

    /// CLAUDE.md rule 4's access-mode gate, desktop side. Optimistic UI is
    /// deliberately avoided here — `writeAccessEnabled` only updates after
    /// the backend confirms the new value, so a failed toggle doesn't leave
    /// the UI showing a state that isn't actually true on the server.
    public func setWriteAccess(_ enabled: Bool) async {
        isTogglingWriteAccess = true
        do {
            writeAccessEnabled = try await backend.setWriteAccess(realmID: realmID, enabled: enabled)
        } catch {
            if !Self.isCancellation(error) {
                healthCheckError = error.localizedDescription
            }
        }
        isTogglingWriteAccess = false
    }

    /// docs/VOICE_LEDGER_SPEC.md's AI kill switch, read side. Never
    /// cached/assumed — a live call, same posture as `checkHealth()`.
    public func checkAIStatus() async {
        isCheckingAIStatus = true
        aiStatusError = nil
        do {
            aiStatus = try await backend.getAIStatus()
        } catch {
            if !Self.isCancellation(error) {
                aiStatusError = error.localizedDescription
            }
        }
        isCheckingAIStatus = false
    }

    /// The kill switch's write side. Optimistic UI is deliberately avoided
    /// here too, same reasoning as `setWriteAccess` — `aiStatus` only
    /// updates after the backend confirms the new value.
    public func setAIEnabled(_ enabled: Bool) async {
        isTogglingAIEnabled = true
        do {
            aiStatus = try await backend.setAIEnabled(enabled)
        } catch {
            if !Self.isCancellation(error) {
                aiStatusError = error.localizedDescription
            }
        }
        isTogglingAIEnabled = false
    }

    /// docs/VOICE_LEDGER_SPEC.md's Ask [AI] panel: "Every page ends with an
    /// Ask [AI] panel." The general form, added 2026-08-28 when the panel
    /// expanded beyond `FindingDetailView` — any caller supplies its own
    /// `contextKey` (so its answer/error state doesn't collide with any
    /// other panel's) and pre-composed `contextText` (built by
    /// `AskAIContext`, Core, pure — this method never adds anything to it
    /// itself, preserving CLAUDE.md rule 1's boundary no matter which page
    /// calls this).
    /// `model` — see `BackendClient.askAI`'s doc comment. `VoiceEngine`'s
    /// two spoken reasoning-fallback call sites pass `"gemma4:e4b"`; every
    /// other caller (every on-screen Ask AI panel) leaves this `nil` and
    /// keeps using the app's configured default.
    /// `conversationTier` (2026-09-07): purely a label for
    /// `recordConversation`'s history/report-log entry — decoupled from the
    /// backend request itself (which is always the primary/Ollama route at
    /// the HTTP level regardless of `model`; the Anthropic override only
    /// ever activates on that same primary route, never `.secondary` — see
    /// `backend/src/routes/ai.ts`). Lets a model-override caller (Qwen3,
    /// Claude Haiku) record itself accurately instead of every override
    /// showing up mislabeled as "Gemma."
    public func askAI(contextKey: String, contextText: String, question: String, history: [AskAIHistoryTurn] = [], format: AskAIFormat = .concise, model: String? = nil, conversationTier: AskAIConversationEntry.Tier = .primary) async {
        guard !askingAIContextKeys.contains(contextKey) else { return }
        askingAIContextKeys.insert(contextKey)
        if askAIError?.contextKey == contextKey { askAIError = nil }
        do {
            let fullContext = Self.contextWithKnowledge(contextText, question: question)
            let raw = try await backend.askAI(realmID: realmID, question: question, context: fullContext, history: history, format: format, model: model)
            let answer = verifiedAnswer(raw, context: fullContext, question: question, history: history)
            askAIAnswers[contextKey] = answer
            await recordConversation(contextKey: contextKey, tier: conversationTier, question: question, answer: answer, format: format)
        } catch {
            askAIError = (contextKey: contextKey, message: error.localizedDescription)
        }
        askingAIContextKeys.remove(contextKey)
    }

    /// The tool-calling counterpart to `askAI`, for `VoiceToolLoop`
    /// (2026-09-06) — thin `backend.askAIWithTools` wrapper, same as every
    /// other `AppState` method that talks to the backend never does more
    /// than compose the call and surface the result; the actual tool
    /// definitions and dispatch logic live entirely in `VoiceToolLoop`.
    public func askAIWithTools(question: String, context: String, history: [AskAIHistoryTurn], model: String, tools: [[String: JSONValue]]) async throws -> (answer: String, toolCalls: [AIToolCall]) {
        try await backend.askAIWithTools(realmID: realmID, question: question, context: context, history: history, model: model, tools: tools)
    }

    /// `FindingDetailView`'s call site — a thin wrapper over the general
    /// form above, keyed by finding ID, context composed from that
    /// finding's own already-computed fields.
    public func askAI(findingID: String, question: String) async {
        guard let finding = finding(id: findingID) else { return }
        await askAI(contextKey: findingID, contextText: AskAIContext.compose(finding: finding), question: question)
    }

    /// Owner directive (2026-08-31): "a 'Draft a message to the client
    /// about this' button on a finding." Deliberately a DIFFERENT feature
    /// from `ClientQuestionDrafter` (Core, pure, no AI) — that one is a
    /// fixed template for "I'm not sure, can you confirm this?" uncertain
    /// findings; this narrates a flexible, plain-English update for when
    /// the bookkeeper wants to explain what's going on, adapted to this
    /// finding's actual specifics, using `format: .clientMessage`'s
    /// separate client-facing system prompt (backend `routes/ai.ts`) — no
    /// internal tool jargon, never a wrong number (same Context-grounded
    /// boundary as every other Ask AI call). A distinct `contextKey`
    /// ("client-message:<id>", not the bare finding ID `askAI(findingID:)`
    /// uses) so its answer/error state doesn't collide with that panel's.
    private static let draftClientMessagePrompt = "Draft a short, professional message explaining this to the client and what, if anything, is needed from them."

    public func draftClientMessage(findingID: String, question: String? = nil) async {
        guard let finding = finding(id: findingID) else { return }
        await askAI(
            contextKey: "client-message:\(findingID)",
            contextText: AskAIContext.compose(finding: finding),
            question: question ?? Self.draftClientMessagePrompt,
            format: .clientMessage
        )
    }

    /// The opt-in "second opinion" tier (2026-08-29, owner directive): asks
    /// the SAME question through OpenAI instead of the app's default free
    /// local model, for a bookkeeper who wants a more capable read on a
    /// finding they're still unsure about. Two things this deliberately
    /// does differently from `askAI(findingID:question:)` above:
    ///
    /// 1. Composes context with `AskAIContext.composeRedacted`, not
    ///    `.compose` — the vendor name never leaves this machine for this
    ///    tier (see that function's doc comment for the honest scope of
    ///    what is and isn't redacted).
    /// 2. Passes `tier: .secondary`, which the backend only ever honors
    ///    when explicitly asked — this is never invoked from any
    ///    automatic/default flow, only from a button the owner clicks
    ///    themselves each time, since every call here is a real,
    ///    non-free API request.
    /// The general form, mirroring `askAI(contextKey:contextText:question:)`
    /// above — extracted 2026-08-29 so the report buttons (page-level
    /// context, not one finding's) can reuse the same opt-in paid tier
    /// without a finding ID.
    public func askSecondOpinion(contextKey: String, contextText: String, question: String, format: AskAIFormat = .concise) async {
        guard !askingSecondOpinionContextKeys.contains(contextKey) else { return }
        askingSecondOpinionContextKeys.insert(contextKey)
        if secondOpinionError?.contextKey == contextKey { secondOpinionError = nil }
        do {
            let fullContext = Self.contextWithKnowledge(contextText, question: question)
            let raw = try await backend.askAI(realmID: realmID, question: question, context: fullContext, tier: .secondary, format: format)
            let answer = verifiedAnswer(raw, context: fullContext, question: question, history: [])
            secondOpinionAnswers[contextKey] = answer
            await recordConversation(contextKey: contextKey, tier: .secondary, question: question, answer: answer, format: format)
        } catch {
            secondOpinionError = (contextKey: contextKey, message: error.localizedDescription)
        }
        askingSecondOpinionContextKeys.remove(contextKey)
    }

    /// `FindingDetailView`'s call site — a thin wrapper, context composed
    /// (and redacted) from that finding's own fields.
    public func askSecondOpinion(findingID: String, question: String) async {
        guard let finding = finding(id: findingID) else { return }
        await askSecondOpinion(contextKey: findingID, contextText: AskAIContext.composeRedacted(finding: finding), question: question)
    }

    /// Public so `RootView` can read `askAIAnswers`/`secondOpinionAnswers`
    /// by the same fixed key these methods write to, without duplicating
    /// the literal string.
    public static let healthReportContextKey = "health-report"
    public static let valueSummaryContextKey = "value-summary"
    private static let healthReportPrompt = "In plain English: how healthy are this client's books right now? Cover the negative (open issues) and the positive (what's been fixed), the key financial metrics, and how things have changed since the last report if that data is available."
    private static let valueSummaryPrompt = "In plain English, written for a client with no bookkeeping background: summarize what was found and corrected in their books, and what that means for them. Be specific about the real numbers given, and do not claim a dollar figure was literally saved unless the context says so."

    /// Findings whose Activity Log entry of the given `kind` was recorded
    /// after `lastReportGeneratedAt` (or ALL such entries, when no report
    /// has ever been generated) — the deterministic "since last report"
    /// window both report functions share. A finding can appear here even
    /// after its own status has moved on since the log entry, which is
    /// correct: the log entry is what happened during the window, not a
    /// live re-check of current status.
    private func findingsChanged(kind: ActivityKind, since: Date?) -> [Finding] {
        let ids = Set(activityLog
            .filter { $0.kind == kind && (since == nil || $0.recordedAt > since!) }
            .compactMap(\.findingID))
        return findings.filter { ids.contains($0.id) }
    }

    private func composedHealthReportContext() -> String {
        AskAIContext.composeHealthReport(
            openFindings: findings.filter { $0.status == .open },
            resolvedFindings: findingsChanged(kind: .findingResolved, since: lastReportGeneratedAt),
            dismissedFindings: findingsChanged(kind: .findingDismissed, since: lastReportGeneratedAt),
            balanceSheetLines: balanceSheetLines,
            profitAndLossLines: profitAndLossLines,
            priorBalanceSheetLines: priorPeriodBalanceSheetLines,
            priorProfitAndLossLines: priorPeriodProfitAndLossLines,
            agedReceivablesLines: agedReceivablesLines.isEmpty ? nil : agedReceivablesLines,
            agedPayablesLines: agedPayablesLines.isEmpty ? nil : agedPayablesLines,
            period: currentPeriod
        )
    }

    private func composedValueSummaryContext() -> String {
        AskAIContext.composeValueSummary(
            resolvedFindings: findingsChanged(kind: .findingResolved, since: lastReportGeneratedAt),
            dismissedFindings: findingsChanged(kind: .findingDismissed, since: lastReportGeneratedAt),
            corrections: activityLog.filter { $0.kind.isCorrection && (lastReportGeneratedAt == nil || $0.recordedAt > lastReportGeneratedAt!) },
            since: lastReportGeneratedAt
        )
    }

    /// Records that a report was generated right now — updates the "since
    /// last report" baseline both compose functions read, persisted so it
    /// survives a restart. Errors are swallowed the same way other
    /// best-effort persistence in this class is (the report itself already
    /// succeeded by the time this is called; a disk write failure here
    /// shouldn't surface as if the report failed).
    private func recordReportGenerated() async {
        let now = Date()
        lastReportGeneratedAt = now
        try? await store.saveLastReportGeneratedAt(now)
    }

    /// A human-readable name for a raw `contextKey` — the one place that
    /// mapping happens, so `AskAIConversationEntry`/the on-disk report log
    /// never carry an internal key like a finding's raw UUID.
    private func conversationLabel(for contextKey: String) -> String {
        // Strip a model-override suffix (Qwen3, Claude) before matching —
        // those reuse the same base context key as the Gemma tier
        // (`"<key>-qwen"`/`"<key>-claude"`) so their state doesn't collide
        // with it, but the label should read the same either way.
        let base: String
        if contextKey.hasSuffix("-claude") {
            base = String(contextKey.dropLast("-claude".count))
        } else if contextKey.hasSuffix("-qwen") {
            base = String(contextKey.dropLast("-qwen".count))
        } else {
            base = contextKey
        }
        if base == Self.healthReportContextKey { return "Book Health Report" }
        if base == Self.valueSummaryContextKey { return "Client Value Summary" }
        if let title = finding(id: base)?.title { return title }
        return contextKey
    }

    /// Owner directive (2026-08-29): "change voice history to the
    /// conversation from asking gemma and or open ai" plus "when I
    /// generate a report it logs it somewhere... and possibly on a text
    /// file." Called from both `askAI`/`askSecondOpinion` on every
    /// successful answer, primary and secondary tier alike — this is the
    /// one place both halves of that request are satisfied: the in-app
    /// history (`conversationHistory`, persisted via `ClientStore`) always
    /// gets an entry; the on-disk text file only gets one when this was a
    /// real report generation (`format == .report`), not every incidental
    /// follow-up question — the file is meant to be a week-over-week/
    /// month-over-month report record, not a full chat transcript.
    /// QuickBooks and bookkeeping reference notes (ProAdvisor training,
    /// Intuit help pages, Voice Ledger's workflow), ported from the Talking
    /// Buddy project 2026-10-02. In the built app they sit in the bundle's
    /// Resources/knowledge; in a dev build, in desktop/Knowledge.
    public static let knowledge: KnowledgeLibrary = {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("knowledge")) }
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Knowledge"))
        guard let root = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else { return KnowledgeLibrary(notes: []) }
        return KnowledgeLibrary.load(from: root)
    }()

    /// The page's own context plus any reference notes that fit the question.
    /// Kept under the backend's context limit; the page data always wins room.
    public static func contextWithKnowledge(_ context: String, question: String, limit: Int = 23_000) -> String {
        let room = limit - context.count - 200
        guard room > 600, let block = KnowledgeLibrary.referenceBlock(knowledge.search(question, limit: 3, budget: min(3000, room - 500))) else { return context }
        return context + "\n\n" + block
    }

    /// Every typed Ask AI answer passes through here (rule 1: the model never
    /// supplies an authoritative number). A sentence citing a figure that is
    /// not in the context the model was given, or in what the user typed, is
    /// removed; the rest is shown with dollars formatted like the pages.
    private func verifiedAnswer(_ raw: String, context: String, question: String, history: [AskAIHistoryTurn]) -> String {
        let source = ([context, question] + history.map(\.content)).joined(separator: "\n")
        let guarded = NumberGuard.scrubProse(ClientText.polish(raw), source: ClientText.polish(source))
        return guarded.text
    }

    private var dataSnapshotPeriod: String { "\(period.year)-\(String(format: "%02d", period.month))" }
    var openFindingTotal: Int { findings.filter { $0.status == .open }.count }

    private func recordConversation(contextKey: String, tier: AskAIConversationEntry.Tier, question: String, answer: String, format: AskAIFormat) async {
        let entry = AskAIConversationEntry(
            contextLabel: conversationLabel(for: contextKey),
            tier: tier,
            question: question,
            answer: answer,
            period: dataSnapshotPeriod,
            openFindingCount: openFindingTotal
        )
        conversationHistory.append(entry)
        try? await store.appendAskAIConversationEntry(entry)

        guard format == .report else { return }
        let providerLabel: String
        switch tier {
        case .primary: providerLabel = "Gemma (local, free)"
        case .secondary: providerLabel = "OpenAI"
        case .claude: providerLabel = "Claude Haiku 4.5 (cloud)"
        }
        ReportHistoryLogger.append(
            reportTitle: entry.contextLabel,
            companyName: companyInfo?.companyName,
            environment: environment == .production ? "production" : "sandbox",
            period: currentPeriod,
            providerLabel: providerLabel,
            bodyText: answer
        )
    }

    // The "since last report" baseline only advances on a genuine success
    // — `askAI`/`askSecondOpinion` catch their own errors internally rather
    // than throwing, so success is read back as "no error was just set for
    // this key," the same signal `FindingDetailView`'s error binding
    // already relies on elsewhere.
    public func generateHealthReport() async {
        await askAI(contextKey: Self.healthReportContextKey, contextText: composedHealthReportContext(), question: Self.healthReportPrompt, format: .report)
        if askAIError?.contextKey != Self.healthReportContextKey { await recordReportGenerated() }
    }

    public func generateHealthReportSecondOpinion() async {
        await askSecondOpinion(contextKey: Self.healthReportContextKey, contextText: composedHealthReportContext(), question: Self.healthReportPrompt, format: .report)
        if secondOpinionError?.contextKey != Self.healthReportContextKey { await recordReportGenerated() }
    }

    public func generateValueSummary() async {
        await askAI(contextKey: Self.valueSummaryContextKey, contextText: composedValueSummaryContext(), question: Self.valueSummaryPrompt, format: .report)
        if askAIError?.contextKey != Self.valueSummaryContextKey { await recordReportGenerated() }
    }

    public func generateValueSummarySecondOpinion() async {
        await askSecondOpinion(contextKey: Self.valueSummaryContextKey, contextText: composedValueSummaryContext(), question: Self.valueSummaryPrompt, format: .report)
        if secondOpinionError?.contextKey != Self.valueSummaryContextKey { await recordReportGenerated() }
    }

    /// Owner directive (2026-09-07): "generate report with claude button" —
    /// a THIRD report tier alongside Gemma (free) and OpenAI (second
    /// opinion). Reuses `askAI`'s own model-override plumbing (the same
    /// mechanism `RootView`'s Qwen3 tier already uses) rather than a new
    /// backend concept: same free/report context, same `askAIAnswers`
    /// dictionary, just a "-claude" suffixed context key so its answer
    /// renders in its own panel instead of overwriting Gemma's, and
    /// `conversationTier: .claude` so the report history log/conversation
    /// history say which model actually answered.
    static let claudeModel = "claude-haiku-4-5"

    public func generateHealthReportClaude() async {
        let key = "\(Self.healthReportContextKey)-claude"
        await askAI(contextKey: key, contextText: composedHealthReportContext(), question: Self.healthReportPrompt, format: .report, model: Self.claudeModel, conversationTier: .claude)
        if askAIError?.contextKey != key { await recordReportGenerated() }
    }

    public func generateValueSummaryClaude() async {
        let key = "\(Self.valueSummaryContextKey)-claude"
        await askAI(contextKey: key, contextText: composedValueSummaryContext(), question: Self.valueSummaryPrompt, format: .report, model: Self.claudeModel, conversationTier: .claude)
        if askAIError?.contextKey != key { await recordReportGenerated() }
    }

    // Owner directive (2026-08-29): a real bug, found live — the "Ask a
    // question" box under each report panel was wired to just call
    // `generateHealthReport()`/etc again, silently discarding whatever the
    // owner actually typed ("what should I look at first?" produced
    // another full canned report instead of an answer). These four give
    // that box a real destination: the SAME composed context (so the
    // answer is grounded in the real 17-finding data, not re-summarized
    // from scratch), asked in `.concise` format specifically so the model
    // answers the actual question instead of regenerating the whole
    // report structure. Deliberately does NOT call `recordReportGenerated()`
    // — an incidental follow-up question isn't "a report was generated,"
    // and shouldn't reset the "since last report" window the real Generate
    // Report buttons use.
    public func askHealthReportFollowUp(_ question: String) async {
        await askAI(contextKey: Self.healthReportContextKey, contextText: composedHealthReportContext(), question: question, format: .concise)
    }

    public func askHealthReportFollowUpSecondOpinion(_ question: String) async {
        await askSecondOpinion(contextKey: Self.healthReportContextKey, contextText: composedHealthReportContext(), question: question, format: .concise)
    }

    public func askValueSummaryFollowUp(_ question: String) async {
        await askAI(contextKey: Self.valueSummaryContextKey, contextText: composedValueSummaryContext(), question: question, format: .concise)
    }

    public func askValueSummaryFollowUpSecondOpinion(_ question: String) async {
        await askSecondOpinion(contextKey: Self.valueSummaryContextKey, contextText: composedValueSummaryContext(), question: question, format: .concise)
    }

    public func askHealthReportFollowUpClaude(_ question: String) async {
        await askAI(contextKey: "\(Self.healthReportContextKey)-claude", contextText: composedHealthReportContext(), question: question, format: .concise, model: Self.claudeModel, conversationTier: .claude)
    }

    public func askValueSummaryFollowUpClaude(_ question: String) async {
        await askAI(contextKey: "\(Self.valueSummaryContextKey)-claude", contextText: composedValueSummaryContext(), question: question, format: .concise, model: Self.claudeModel, conversationTier: .claude)
    }

    // MARK: - Finding comparison

    /// Owner directive (2026-09-06): "the app should be able to find
    /// similarities and detect if they are a duplicate or explain and
    /// justify when they are totally different." Reuses the same generic
    /// `askAI(contextKey:...)`/`askAIAnswers` machinery as every other Ask
    /// AI surface — a comparison is keyed by its exact (sorted, so order
    /// doesn't matter) set of finding ids, so re-opening the same
    /// comparison later reuses the cached answer instead of re-asking, and
    /// a DIFFERENT set of findings never collides with it.
    private static let comparisonPrompt = "Explain whether these findings are duplicates of each other, meaningfully similar, or genuinely different. Justify your answer using only the finding details and computed comparison signals given — never assert a similarity or difference the signals don't support."

    public func comparisonContextKey(for findingIDs: [String]) -> String {
        "compare-" + findingIDs.sorted().joined(separator: ",")
    }

    public func generateComparisonAnalysis() async {
        let ids = comparedFindingIDs
        guard ids.count >= 2 else { return }
        let comparedFindings = ids.compactMap { finding(id: $0) }
        await askAI(
            contextKey: comparisonContextKey(for: ids),
            contextText: AskAIContext.composeComparison(findings: comparedFindings),
            question: Self.comparisonPrompt,
            format: .concise
        )
    }

    public func generateComparisonAnalysisSecondOpinion() async {
        let ids = comparedFindingIDs
        guard ids.count >= 2 else { return }
        let comparedFindings = ids.compactMap { finding(id: $0) }
        await askSecondOpinion(
            contextKey: comparisonContextKey(for: ids),
            contextText: AskAIContext.composeComparison(findings: comparedFindings),
            question: Self.comparisonPrompt,
            format: .concise
        )
    }

    /// Same "an incidental follow-up isn't a full re-analysis" reasoning as
    /// `askHealthReportFollowUp` above — a typed follow-up question about
    /// the same compared set, grounded in the identical composed context.
    public func askComparisonFollowUp(_ question: String) async {
        let ids = comparedFindingIDs
        guard ids.count >= 2 else { return }
        await askAI(contextKey: comparisonContextKey(for: ids), contextText: AskAIContext.composeComparison(findings: ids.compactMap { finding(id: $0) }), question: question, format: .concise)
    }

    public func askComparisonFollowUpSecondOpinion(_ question: String) async {
        let ids = comparedFindingIDs
        guard ids.count >= 2 else { return }
        await askSecondOpinion(contextKey: comparisonContextKey(for: ids), contextText: AskAIContext.composeComparison(findings: ids.compactMap { finding(id: $0) }), question: question, format: .concise)
    }

    public func generateComparisonAnalysisClaude() async {
        let ids = comparedFindingIDs
        guard ids.count >= 2 else { return }
        let comparedFindings = ids.compactMap { finding(id: $0) }
        await askAI(
            contextKey: "\(comparisonContextKey(for: ids))-claude",
            contextText: AskAIContext.composeComparison(findings: comparedFindings),
            question: Self.comparisonPrompt,
            format: .concise,
            model: Self.claudeModel,
            conversationTier: .claude
        )
    }

    public func askComparisonFollowUpClaude(_ question: String) async {
        let ids = comparedFindingIDs
        guard ids.count >= 2 else { return }
        await askAI(
            contextKey: "\(comparisonContextKey(for: ids))-claude",
            contextText: AskAIContext.composeComparison(findings: ids.compactMap { finding(id: $0) }),
            question: question,
            format: .concise,
            model: Self.claudeModel,
            conversationTier: .claude
        )
    }

    /// docs/phase-0/11_VERTICAL_SLICE.md §11.2 pipeline steps 2-6: sync,
    /// normalize, evaluate, persist, re-render. Re-running this is what
    /// makes the isVoided exclusion resolve a finding (§11.1) — see
    /// `ClientStore.reconcileAgainstLatestRun`.
    public func syncAndEvaluate() async {
        // Gauntlet Loop, Gauntlet B round 21 (2026-08-24): this had no
        // re-entrancy guard at all — see `isSyncInFlight`'s doc comment for
        // why `loadState` itself can't be trusted for this check.
        guard !isSyncInFlight else { return }
        isSyncInFlight = true
        defer { isSyncInFlight = false }
        loadState = .loading
        do {
            let syncedDataSet = try await syncClient.sync(realmID: realmID, period: period)

            // Merge in any previously-imported, persisted statement lines
            // (Universal Ingestion Tier 1) so VL-RECON-MISSING-001 sees them
            // on every sync, not just the run right after import.
            //
            // Gauntlet Loop, Gauntlet C round 6 (2026-08-24): a fresh
            // critic found `importedStatementLineCount` had the identical
            // non-atomic-publish shape rounds 4/5 fixed for
            // `coverage`/`accounts`/`findings`/`activityLog` — this used
            // to publish immediately here, long before the many further
            // throwing calls below. A throw after this line left this
            // sync's fresh count published while `findings` stayed stale,
            // which `RootView`'s `ReconciliationSummary.compute` mixes
            // together (fresh statement-line count against a stale
            // unmatched-finding count) into a specific, wrong "Matched" /
            // "Unmatched" claim on the Bank Feed Cleanup page — the same
            // false-data shape, on a different rule's surface, reached
            // through this same shared method. Deferred into a local until
            // the atomic publish block below.
            let importedLines = try await store.loadImportedStatementLines()

            // VL-FORCED-RECON-001 needs the P&L report (see that rule's doc
            // comment for why — the only API surface that shows a forced
            // reconciliation's discrepancy). Fetched here, not just on the
            // P&L page's own lazy Refresh, so the rule runs on every sync
            // rather than only after someone happens to visit that page.
            // A fetch failure here does NOT fail the whole sync — it just
            // means this one rule reports .cannotEvaluate, same as any
            // other optional-coverage source.
            // Independent report reads share the backend's per-realm limit.
            // Reuse these results for the dashboard instead of fetching its
            // Balance Sheet and P&L a second time during the same refresh.
            let agingAsOf = QBOSyncClient.agingDate(for: period, today: AccountingDate(date: Date()))
            async let profitAndLossRead = try? syncClient.fetchProfitAndLoss(realmID: realmID, period: period)
            async let balanceSheetRead = try? syncClient.fetchBalanceSheet(realmID: realmID, period: period)
            async let receivablesRead = try? syncClient.fetchAgedReceivables(realmID: realmID, asOf: agingAsOf)
            async let payablesRead = try? syncClient.fetchAgedPayables(realmID: realmID, asOf: agingAsOf)
            async let trialBalanceRead = try? syncClient.fetchTrialBalance(realmID: realmID, period: period)
            async let priorPurchasesRead = try? syncClient.fetchPurchases(realmID: realmID, period: period.previousMonth)
            let (pl, bs, ar, ap, tb, prior) = await (profitAndLossRead, balanceSheetRead, receivablesRead, payablesRead, trialBalanceRead, priorPurchasesRead)
            try Task.checkCancellation()
            let profitAndLossLines = pl ?? []
            let balanceSheetLines = bs ?? []
            let agedReceivablesLines = ar ?? []
            let agedPayablesLines = ap ?? []
            let trialBalanceLinesForSync = tb ?? []
            let priorPeriodTransactionsForSync = prior ?? []

            let dataSet = NormalizedDataSet(
                realmID: syncedDataSet.realmID,
                period: syncedDataSet.period,
                transactions: syncedDataSet.transactions + importedLines,
                accounts: syncedDataSet.accounts,
                vendors: syncedDataSet.vendors,
                deposits: syncedDataSet.deposits,
                // Real bug, found 2026-08-18 while wiring VL-FORCED-RECON-001:
                // this was missing entirely, silently defaulting to `[]` via
                // NormalizedDataSet's init default. VL-VENDCREDIT-UNAPPLIED-001
                // has been returning a FALSE `.pass` in the live app this
                // whole time — `input.coverage` reflects the overall sync
                // (which succeeds), not whether vendor credits specifically
                // were carried through, so the rule had no way to tell
                // "genuinely zero vendor credits" from "never given any."
                // Only ever caught via the devtool CLI, which built its
                // NormalizedDataSet correctly — this exact class of gap is
                // why "the CLI proved it once" is not the same claim as
                // "the app has always done this."
                vendorCredits: syncedDataSet.vendorCredits,
                profitAndLossLines: profitAndLossLines,
                balanceSheetLines: balanceSheetLines,
                agedReceivablesLines: agedReceivablesLines,
                agedPayablesLines: agedPayablesLines,
                trialBalanceLines: trialBalanceLinesForSync,
                priorPeriodTransactions: priorPeriodTransactionsForSync,
                coverage: syncedDataSet.coverage,
                companyFacts: syncedDataSet.companyFacts
            )

            // Loaded fresh, not read from `self.findings` — this must
            // reflect exactly what's on disk right now, not whatever the
            // last render happened to hold. A rule checks this set to skip
            // reproducing a finding at all (`CLAUDE.md` rule 2's
            // dismiss-is-real posture — not just hidden by a UI filter).
            let dismissedFindingIDs = Set(try await store.loadFindings().filter { $0.status == .dismissed }.map(\.id))
            // Loaded fresh rather than read from `self.periodLock` — this
            // sync may be racing `loadFromDiskOnly()` (still in flight from
            // app launch) or a fresh `setPeriodLock`/`clearPeriodLock` call,
            // and `VL-PERIOD-CLOSED-001` needs the real on-disk value, not
            // whatever the last render happened to hold.
            let currentPeriodLock = try await store.loadPeriodLock()
            // Same "loaded fresh, not from `self`" reasoning as
            // `currentPeriodLock` immediately above — VL-CLOSED-PERIOD-DRIFT-001
            // needs the on-disk snapshot as of right now.
            let currentPeriodLockSnapshot = try await store.loadPeriodLockSnapshot()
            let currentBankStatementSnapshots = try await store.loadBankStatementReconciliationSnapshots()
            let context = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: dataSet.companyFacts, dismissedFindingIDs: dismissedFindingIDs, periodLock: currentPeriodLock, periodLockSnapshot: currentPeriodLockSnapshot, bankStatementSnapshots: currentBankStatementSnapshots)
            let evaluation = await engine.evaluate(pages: [.page3Transactions, .cleanupAssessment, .bankFeedCleanup], input: dataSet, context: context)

            // Gauntlet Loop, Gauntlet B round 11 (2026-08-24): a fresh
            // critic found this used to collapse `.cannotEvaluate` into the
            // same "empty current-run set" as a genuine `.pass` — so a
            // transient failure (e.g. `try?` swallowing a P&L fetch error
            // elsewhere in this method) would resolve every open finding
            // for that rule with the Activity Log claiming "the underlying
            // issue appears to be fixed," which is false: the rule never
            // actually re-ran the check. `.cannotEvaluate` is excluded from
            // `currentRunIDsByRule` entirely, so `reconcileAgainstLatestRun`
            // is simply not called for that rule this cycle — its findings
            // stay exactly as they were until a sync actually re-evaluates
            // them, rather than being resolved on a false pretense.
            // Gauntlet Loop, Gauntlet B round 11 (2026-08-24): a fresh
            // critic also found `ActivityKind.findingDetected` — labeled,
            // documented, tested for round-trip — was never actually
            // produced anywhere, the same "case exists but no real call
            // site" gap round 10 found for `findingResolved`. Loaded once
            // up front (not re-read per rule) so a finding already on disk
            // from a prior sync is never mistaken for new.
            let priorFindingIDs = Set(try await store.loadFindings().map(\.id))

            var currentRunIDsByRule: [RuleID: Set<String>] = [:]
            for (ruleID, result) in evaluation.results {
                switch result.outcome {
                case .findings(let ruleFindings):
                    try await store.upsertFindings(ruleFindings)
                    currentRunIDsByRule[ruleID] = Set(ruleFindings.map(\.id))
                    for finding in ruleFindings where !priorFindingIDs.contains(finding.id) {
                        try await store.appendActivityLogEntry(ActivityLogEntry(
                            realmID: realmID,
                            actor: .system,
                            kind: .findingDetected,
                            findingID: finding.id,
                            ruleID: finding.ruleID,
                            ruleVersion: finding.ruleVersion,
                            findingSummary: finding.title,
                            note: nil
                        ))
                    }
                case .pass:
                    currentRunIDsByRule[ruleID] = []
                case .cannotEvaluate:
                    break
                }
            }
            for (ruleID, currentIDs) in currentRunIDsByRule {
                let resolvedFindings = try await store.reconcileAgainstLatestRun(currentRunFindingIDs: currentIDs, ruleID: ruleID)
                for finding in resolvedFindings {
                    try await store.appendActivityLogEntry(ActivityLogEntry(
                        realmID: realmID,
                        actor: .system,
                        kind: .findingResolved,
                        findingID: finding.id,
                        ruleID: finding.ruleID,
                        ruleVersion: finding.ruleVersion,
                        findingSummary: finding.title,
                        note: "No longer detected on this sync — the underlying issue appears to be fixed."
                    ))
                }
            }

            // Client Memory: an open finding matching an existing
            // ClientMemoryRule is auto-dismissed right here, on every sync —
            // this is what makes "always dismiss future Odessa Water
            // transactions" actually apply to FUTURE occurrences, not just
            // the one that existed when the rule was created. Never silent:
            // each one gets its own Activity Log entry naming the rule.
            let memoryRules = try await store.loadClientMemoryRules()
            if !memoryRules.isEmpty {
                let openFindings = try await store.loadFindings().filter { $0.status == .open }
                for finding in openFindings {
                    guard let matchedRule = memoryRules.first(where: { $0.matches(ruleID: finding.ruleID, findingVendorName: finding.vendorName) }) else { continue }
                    // Gauntlet Loop, Gauntlet B round 22 (2026-08-24): same
                    // fix as `dismissFinding` — only log when this call
                    // actually changed the status. A concurrent manual
                    // Dismiss on the same finding (nothing prevents that;
                    // `isSyncInFlight` only guards a second sync) could
                    // have already dismissed it between the `.filter` above
                    // and this call, making `store.dismissFinding` a
                    // genuine no-op that shouldn't be logged as if the
                    // client memory rule was what did it.
                    if try await store.dismissFinding(id: finding.id) {
                        try await store.appendActivityLogEntry(ActivityLogEntry(
                            realmID: realmID,
                            actor: .system,
                            kind: .findingAutoDismissedByClientMemory,
                            findingID: finding.id,
                            ruleID: finding.ruleID,
                            ruleVersion: finding.ruleVersion,
                            findingSummary: finding.title,
                            note: "Matched client memory rule for \(matchedRule.vendorName) (created by \(matchedRule.createdBy))"
                        ))
                    }
                }
            }

            // Gauntlet Loop, Gauntlet C rounds 4-5 (2026-08-24): `coverage`/
            // `accounts` used to be published immediately after the first
            // `await` far above — so a throw anywhere in between (any of
            // the several `store`/`engine` calls this method makes, all
            // genuinely capable of failing) left them holding this sync's
            // NEW, freshly-`.complete` result while `findings` kept its OLD
            // (often empty, e.g. on a first-ever sync) value. `FindingsListView`'s
            // coverage strip reads exactly that combination as "Verified —
            // None," a false green for a sync that provably never
            // finished. Round 4's fix moved the four assignments together
            // but LEFT `try await` calls between them (`loadFindings()`,
            // `loadActivityLog()`) — a fresh round-5 critic found that
            // still isn't atomic: `coverage`/`accounts` are plain,
            // non-throwing reads that publish immediately, while
            // `loadFindings()` on the very next line is a genuine
            // suspension/throw point, so the exact same false-green
            // sequence was still reachable if THAT call failed. Every
            // throwing load is now resolved into a LOCAL variable first;
            // the five `self.` assignments that follow (including
            // `importedStatementLineCount`, round 6) are all plain,
            // non-throwing writes with no `await` between any of them —
            // an actual atomic publish, not just adjacent lines.
            let newFindings = try await store.loadFindings()
            let newActivityLog = try await store.loadActivityLog()
            coverage = syncedDataSet.coverage
            accounts = syncedDataSet.accounts
            vendors = syncedDataSet.vendors
            await checkForNewAccounts(syncedDataSet.accounts)
            transactions = dataSet.transactions
            findings = newFindings
            activityLog = newActivityLog
            importedStatementLineCount = importedLines.count
            if let bs { self.balanceSheetLines = bs }
            if let pl { self.profitAndLossLines = pl }
            balanceSheetError = bs == nil ? "Balance Sheet refresh failed; showing previously loaded data." : nil
            profitAndLossError = pl == nil ? "Profit & Loss refresh failed; showing previously loaded data." : nil
            let syncedAt = Date()
            lastSyncedAt = syncedAt
            cachedSyncedAt = syncedAt
            loadState = .loaded
            try? await store.saveLastSyncedAt(syncedAt)
            if let snapshot = FinancialSnapshot.fromCompleteSync(dataSet, syncedAt: syncedAt) {
                try? await store.saveFinancialSnapshot(snapshot)
            }
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// The rule sync also publishes its freshly fetched dashboard reports
    /// and persists a snapshot only when all required inputs succeeded.
    public func syncDashboard() async {
        await syncAndEvaluate()
        // A report failure is optional for rule evaluation. Preserve the
        // dashboard's previous behavior by retrying only the report that is
        // still empty; successful consolidated syncs make no duplicate calls.
        async let balanceSheetFallback: Void = balanceSheetLines.isEmpty ? loadBalanceSheet() : ()
        async let profitAndLossFallback: Void = profitAndLossLines.isEmpty ? loadProfitAndLoss() : ()
        _ = await (balanceSheetFallback, profitAndLossFallback)
    }

    /// docs/phase-0/09_INGESTION_PIPELINE.md §9.0/§9.2: parses the file
    /// (Tier 1, deterministic) and stops there — this does NOT import
    /// anything yet. Format is detected from the file extension only (OFX
    /// vs CSV need different confirm screens — OFX has no column mapping
    /// to confirm at all); `declaredKind`-style semantic guessing is not
    /// attempted. `pendingImport` drives the confirm screen (§9.4 for CSV,
    /// account-only for OFX); nothing is normalized or persisted until
    /// `confirmCSVImport`/`confirmOFXImport` is called with an explicitly
    /// human-confirmed mapping/account.
    public func selectFileForImport(url: URL) async {
        importError = nil
        let ext = url.pathExtension.lowercased()
        do {
            if ext == "pdf" || ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "heic" {
                // docs/VOICE_LEDGER_SPEC.md's Universal Ingestion Tier 2:
                // Apple Vision on-device OCR. Gated on the REAL runtime
                // requirement `VisionDocumentOCR.swift` discovered by
                // compiling against the SDK (macOS 26.0, not the spec's
                // stated 15 — see that file's doc comment) — never a
                // crash on an older system, a clear message instead.
                guard #available(macOS 26.0, *) else {
                    importError = "Importing a PDF or photo needs macOS 26 or later. Use a CSV/OFX/QFX/XLSX export instead on this Mac."
                    return
                }
                let rows: [[String]]
                do {
                    rows = ext == "pdf" ? try await VisionDocumentOCR.extractRows(fromPDFAt: url) : try await VisionDocumentOCR.extractRows(fromImageFileAt: url)
                } catch VisionDocumentOCR.OCRError.noTableDetected {
                    importError = "\(url.lastPathComponent): couldn't find a table in this document. A CSV/OFX/QFX/XLSX export will work more reliably."
                    return
                } catch VisionDocumentOCR.OCRError.unsupportedFile {
                    importError = "\(url.lastPathComponent) couldn't be read as an image or PDF."
                    return
                }
                let matchedHint = mappingHints.first { $0.id == MappingHint.makeID(headers: rows[0]) }
                // Reuses PendingCSVImport/confirmCSVImport unchanged, same
                // as the .xlsx path above — once OCR produces `[[String]]`,
                // a scanned statement and a real CSV are the same shape
                // all the way through the existing confirm-and-correct +
                // BankStatementCSVImporter pipeline. No second
                // normalization path.
                pendingImport = .csv(PendingCSVImport(
                    filename: url.lastPathComponent, allRows: rows, hasHeaderRow: true,
                    suggestedFields: matchedHint?.fields ?? [],
                    appliedHint: matchedHint.map { (id: $0.id, timesUsed: $0.timesUsed) }
                ))
            } else if ext == "ofx" || ext == "qfx" {
                let text = try String(contentsOf: url, encoding: .utf8)
                let count = OFXParser.parseTransactions(text).count
                guard count > 0 else {
                    importError = "\(url.lastPathComponent) has no <STMTTRN> transactions."
                    return
                }
                let ledgerBalance = OFXParser.parseLedgerBalance(text)
                pendingImport = .ofx(PendingOFXImport(
                    filename: url.lastPathComponent, rawText: text, transactionCount: count,
                    statedEndingBalance: ledgerBalance.flatMap { OFXBankStatementImporter.parseOFXAmount($0.balanceAmount) },
                    statedAsOfDate: ledgerBalance.flatMap { OFXBankStatementImporter.parseOFXDate($0.asOfDate) }
                ))
            } else if ext == "xlsx" || ext == "xls" {
                // .xlsx is a binary (ZIP) container, not UTF-8 text — read
                // as Data, not String, unlike every other format here.
                let data = try Data(contentsOf: url)
                let rows = try XLSXParser.parse(data)
                guard !rows.isEmpty else {
                    importError = "\(url.lastPathComponent) has no rows on its first sheet."
                    return
                }
                let matchedHint = mappingHints.first { $0.id == MappingHint.makeID(headers: rows[0]) }
                // Reuses PendingCSVImport/confirmCSVImport unchanged — once
                // parsed into `[[String]]`, an .xlsx statement and a .csv
                // one are the same shape all the way through the existing
                // confirm-and-correct + BankStatementCSVImporter pipeline.
                pendingImport = .csv(PendingCSVImport(
                    filename: url.lastPathComponent, allRows: rows, hasHeaderRow: true,
                    suggestedFields: matchedHint?.fields ?? [],
                    appliedHint: matchedHint.map { (id: $0.id, timesUsed: $0.timesUsed) }
                ))
            } else {
                let text = try String(contentsOf: url, encoding: .utf8)
                let rows = CSVParser.parse(text)
                guard !rows.isEmpty else {
                    importError = "\(url.lastPathComponent) is empty."
                    return
                }
                let matchedHint = mappingHints.first { $0.id == MappingHint.makeID(headers: rows[0]) }
                pendingImport = .csv(PendingCSVImport(
                    filename: url.lastPathComponent, allRows: rows, hasHeaderRow: true,
                    suggestedFields: matchedHint?.fields ?? [],
                    appliedHint: matchedHint.map { (id: $0.id, timesUsed: $0.timesUsed) }
                ))
            }
        } catch XLSXParser.ParseError.unsupportedLegacyFormat {
            importError = "\(url.lastPathComponent) is a legacy .xls file (pre-2007 format), which isn't supported. Please re-save it as .xlsx or export as CSV."
        } catch {
            importError = "Could not read \(url.lastPathComponent): \(error)"
        }
    }

    /// No-op while a confirm is already in flight (`isConfirmingImport`) —
    /// see that property's doc comment. Without this guard, cancelling
    /// mid-confirm would clear `pendingImport` out from under the awaiting
    /// `confirmCSVImport`/`confirmOFXImport` call, which would then let a
    /// second, newly-started import through only for the first call's
    /// eventual completion to silently clobber it.
    public func cancelPendingImport() {
        guard !isConfirmingImport else { return }
        pendingImport = nil
    }

    /// The confirm step (§9.4) — `mappings` are already `confirmed: true`
    /// by the time they reach here (`ImportBankStatementView` only emits
    /// confirmed mappings via its Confirm button). Persists the normalized
    /// lines via `ClientStore` and immediately re-evaluates so the result
    /// is visible without a separate manual sync.
    public func confirmCSVImport(mappings: [ColumnMapping], statementAccountID: String) async {
        guard case .csv(let pending) = pendingImport, !isConfirmingImport else { return }
        isConfirmingImport = true
        defer { isConfirmingImport = false }
        let documentID = ImportedDocumentID(rawValue: "\(pending.filename)-\(Date().timeIntervalSince1970)")
        let result = BankStatementCSVImporter.import(
            rows: pending.allRows,
            mappings: mappings,
            hasHeaderRow: pending.hasHeaderRow,
            realmID: realmID,
            documentID: documentID,
            importedAt: Date(),
            statementAccountID: statementAccountID
        )
        guard result.defects.isEmpty else {
            importError = "Import produced \(result.defects.count) issue(s): " + result.defects.map(\.humanDescription).joined(separator: "; ")
            return
        }
        do {
            try await store.upsertImportedStatementLines(result.transactions)
            // §9.6 stage 6: learn this mapping for next time, keyed on the
            // header row exactly as it appeared. Only meaningful when the
            // file actually has a header row to fingerprint against.
            if pending.hasHeaderRow, let headerRow = pending.allRows.first {
                var fields = Array(repeating: MappedField.unmapped, count: headerRow.count)
                for mapping in mappings where mapping.sourceColumn < fields.count {
                    fields[mapping.sourceColumn] = mapping.target
                }
                try await store.upsertMappingHint(headers: headerRow, fields: fields)
                mappingHints = try await store.loadMappingHints()
            }
            pendingImport = nil
            await syncAndEvaluate()
        } catch {
            if !Self.isCancellation(error) {
                importError = error.localizedDescription
            }
        }
    }

    /// OFX's counterpart — no column mapping to confirm (self-describing
    /// tags), so only the account needs an explicit human choice.
    public func confirmOFXImport(statementAccountID: String) async {
        guard case .ofx(let pending) = pendingImport, !isConfirmingImport else { return }
        isConfirmingImport = true
        defer { isConfirmingImport = false }
        let documentID = ImportedDocumentID(rawValue: "\(pending.filename)-\(Date().timeIntervalSince1970)")
        let result = OFXBankStatementImporter.import(
            ofxText: pending.rawText,
            realmID: realmID,
            documentID: documentID,
            importedAt: Date(),
            statementAccountID: statementAccountID
        )
        guard result.defects.isEmpty else {
            importError = "Import produced \(result.defects.count) issue(s): " + result.defects.map(\.humanDescription).joined(separator: "; ")
            return
        }
        do {
            try await store.upsertImportedStatementLines(result.transactions)
            // VL-RECON-DIFF-001's baseline. Only saved when the file
            // actually had a `<LEDGERBAL>` block — no invented balance for
            // a file that never stated one.
            if let statedEndingBalance = result.statedEndingBalance {
                let snapshot = BankStatementReconciliationSnapshot(
                    accountID: statementAccountID,
                    statedEndingBalance: statedEndingBalance,
                    statedAsOfDate: result.statedAsOfDate
                )
                try await store.saveBankStatementReconciliationSnapshot(snapshot)
            }
            pendingImport = nil
            await syncAndEvaluate()
        } catch {
            if !Self.isCancellation(error) {
                importError = error.localizedDescription
            }
        }
    }

    public func finding(id: String) -> Finding? {
        findings.first { $0.id == id }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 7 (Batch Fixes) — every open finding
    /// with a real, unambiguous staged API write available, the same gate
    /// `BatchFixPlan.preview` applies. Computed fresh from `findings` on
    /// every access rather than cached, matching `finding(id:)`'s own
    /// posture just above.
    public var stagedFixFindings: [Finding] {
        findings.filter { $0.status == .open && $0.proposedActions.first?.apiWriteDetails != nil }
    }

    public func toggleBatchFixSelection(_ findingID: String) {
        if batchFixSelection.contains(findingID) {
            batchFixSelection.remove(findingID)
        } else {
            batchFixSelection.insert(findingID)
        }
    }

    public func selectAllBatchFix() {
        batchFixSelection = Set(stagedFixFindings.map(\.id))
    }

    public func deselectAllBatchFix() {
        batchFixSelection.removeAll()
    }

    /// Gauntlet Loop, Gauntlet B round 19 (2026-08-24): consolidates a
    /// shape that six straight rounds (13-18) independently rediscovered
    /// and patched, one method at a time, in `dismissFinding`,
    /// `attestCompletion`, `createClientMemoryRule`, and
    /// `recordClientQuestionSent` — no re-entry guard (a rapid double-tap
    /// fired two concurrent calls and produced duplicate Activity Log
    /// entries, since none of the underlying store writes are idempotent),
    /// a stale error left standing after a DIFFERENT action later
    /// succeeded (the two error fields never cleared each other), and an
    /// unconditional navigation on success that could yank the bookkeeper
    /// back to `.list` off a screen they'd since navigated to on purpose
    /// (the toolbar stays live during any in-flight write). Every future
    /// "act on a finding" method should route through this rather than
    /// reimplementing the shape by hand again.
    ///
    /// `applyStagedFix` deliberately does NOT route through this — its
    /// verified/rejected two-branch outcome, its own `syncAndEvaluate()`
    /// call, and its own `applyingFixFindingIDs` (driving the "Applying…"
    /// button label, not just a disabled state) mean folding it in here
    /// would be a larger, riskier rewrite of already-distinct control flow
    /// for no real simplification. Gauntlet Loop, Gauntlet B round 20
    /// (2026-08-24): an earlier version of this comment claimed
    /// `applyStagedFix`'s concurrency handling was "already hardened" —
    /// false with respect to cross-finding interference specifically; it
    /// had the identical `Set`-vs-`String?` bug this method's own
    /// `findingActionInFlightIDs` was just fixed for, ported over
    /// separately to `applyingFixFindingIDs` in the same round.
    ///
    /// - `navigateToListIfScreenMatches`: when non-nil, success navigates
    ///   to `.list` only if this returns true for the CURRENT `screen` at
    ///   the moment `work` finishes — never unconditionally. `nil` means
    ///   this action never navigates (e.g. `recordClientQuestionSent`,
    ///   which always stays on `FindingDetailView`).
    /// - `failureMessage`: builds `findingActionError`'s exact wording from
    ///   the underlying error — each action's honest phrasing differs
    ///   ("wasn't dismissed" vs. "wasn't recorded as sent", etc.), so this
    ///   isn't collapsed into one generic string.
    private func performFindingAction(
        findingID: String,
        navigateToListIfScreenMatches screenMatches: ((Screen) -> Bool)? = nil,
        failureMessage: (Error) -> String,
        _ work: () async throws -> Void
    ) async {
        guard !findingActionInFlightIDs.contains(findingID) else { return }
        // Gauntlet Loop, Gauntlet B round 19 (2026-08-24): scoped to THIS
        // finding only — clearing unconditionally would wipe a different,
        // still-valid finding's error the instant an unrelated action
        // started on this one. Still clears a stale error for the SAME
        // finding left by a DIFFERENT prior action (round 16's original
        // intent), since that comparison is exactly `.findingID == findingID`.
        if findingActionError?.findingID == findingID { findingActionError = nil }
        if applyFixError?.findingID == findingID { applyFixError = nil }
        findingActionInFlightIDs.insert(findingID)
        do {
            try await work()
            findingActionInFlightIDs.remove(findingID)
            if let screenMatches, screenMatches(screen) {
                screen = findingReturnScreen
            }
        } catch {
            findingActionInFlightIDs.remove(findingID)
            findingActionError = (findingID: findingID, message: failureMessage(error))
        }
    }

    /// docs/phase-0/11_VERTICAL_SLICE.md §11.4: attestation is recorded, not
    /// treated as proof. The finding itself only resolves on the NEXT
    /// `syncAndEvaluate()` call, when the isVoided exclusion actually fires
    /// (acceptance criterion 14) — this method does not touch finding status.
    ///
    /// Owner directive (2026-08-29): "a checkmark I click when I've taken
    /// care of it" must actually behave like one — previously, tapping "I
    /// completed this in QBO" recorded the attestation and returned to a
    /// list that still showed the finding open, with nothing telling the
    /// owner a manual Sync was the missing step to see it clear. Rather
    /// than trust the click itself (would violate CLAUDE.md rule 5 — green
    /// only after the required check actually re-ran), this now triggers
    /// that re-check immediately: `syncAndEvaluate()` re-fetches from QBO
    /// and re-runs the rule, so the finding either genuinely disappears
    /// (verified fixed) or honestly stays open (not actually fixed yet, or
    /// QBO hasn't caught up) within the same interaction, not silently
    /// pending until whenever the next unrelated sync happens to occur.
    public func attestCompletion(findingID: String, actorName: String, note: String?) async {
        guard let finding = finding(id: findingID), let action = finding.proposedActions.first else { return }
        let entry = ActivityLogEntry(
            realmID: realmID,
            actor: .user(actorName),
            kind: .manualCompletionAttested,
            findingID: findingID,
            ruleID: finding.ruleID,
            ruleVersion: finding.ruleVersion,
            procedure: action.guidedProcedure,
            findingSummary: finding.title,
            note: note
        )
        await performFindingAction(
            findingID: findingID,
            navigateToListIfScreenMatches: { if case .procedure(let currentFindingID, _) = $0 { return currentFindingID == findingID }; return false },
            failureMessage: { "Your attestation wasn't recorded: \($0). Try again before leaving this screen." }
        ) {
            try await self.store.appendActivityLogEntry(entry)
            self.activityLog = try await self.store.loadActivityLog()
        }
        guard findingActionError?.findingID != findingID else { return }
        await syncAndEvaluate()
        // Owner directive (2026-08-29): "I pressed mark as done... yet
        // after doing this the page still looks the same" — the resync
        // above IS the real check (CLAUDE.md rule 5: never trust the
        // click itself), and here it correctly found the underlying issue
        // still present in QBO — but nothing told the owner that's what
        // just happened, so a genuinely-working re-check looked
        // indistinguishable from nothing happening at all. This records
        // which outcome just occurred so the screen can say so explicitly.
        attestationOutcome = (findingID: findingID, stillOpen: self.finding(id: findingID)?.status == .open)
    }

    /// The explicit "Remember this vendor" action — deliberately separate
    /// from `dismissFinding`, never a checkbox bundled into it, per spec's
    /// "never silently." Also retroactively dismisses every currently-open
    /// finding that already matches (so the finding that prompted this
    /// doesn't linger open until the next sync), each logged the same way
    /// `syncAndEvaluate`'s per-sync auto-dismissal is.
    // Gauntlet Loop, Gauntlet B round 16 (2026-08-24): a fresh critic found
    // "Remember this vendor" and "Send client question" are literally
    // adjacent buttons on the SAME `FindingDetailView` screen as Dismiss —
    // round 15's boundary excluding them from the same fix was wrong by
    // its own stated criterion. Both used to fail with zero signal: the
    // local confirm/draft UI collapsed unconditionally on tap regardless
    // of outcome, and the only trace of a real failure was the unread
    // `loadState.failed`. `triggeringFindingID` is optional (this method
    // isn't inherently about one finding — it can auto-dismiss several) —
    // when the caller knows which finding's button was actually tapped,
    // passing it lets the error render on that finding's own screen,
    // scoped the same way `dismissError`/`attestError` already are.
    public func createClientMemoryRule(ruleID: RuleID, vendorName: String, actorName: String, note: String?, triggeringFindingID: String? = nil) async {
        let rule = ClientMemoryRule(ruleID: ruleID, vendorName: vendorName, createdBy: actorName, note: note)
        let work: () async throws -> Void = {
            try await self.store.addClientMemoryRule(rule)
            try await self.store.appendActivityLogEntry(ActivityLogEntry(
                realmID: self.realmID,
                actor: .user(actorName),
                kind: .clientMemoryRuleCreated,
                ruleID: ruleID,
                note: "Always dismiss \(ruleID.rawValue) findings for \(vendorName)" + (note.map { " — \($0)" } ?? "")
            ))

            let matchingOpenFindings = try await self.store.loadFindings().filter { $0.status == .open && rule.matches(ruleID: $0.ruleID, findingVendorName: $0.vendorName) }
            for finding in matchingOpenFindings {
                // Gauntlet Loop, Gauntlet B round 22 (2026-08-24): same fix
                // as `dismissFinding`/`syncAndEvaluate`'s auto-dismiss loop
                // — only log when this call actually changed the status.
                if try await self.store.dismissFinding(id: finding.id) {
                    try await self.store.appendActivityLogEntry(ActivityLogEntry(
                        realmID: self.realmID,
                        actor: .system,
                        kind: .findingAutoDismissedByClientMemory,
                        findingID: finding.id,
                        ruleID: finding.ruleID,
                        ruleVersion: finding.ruleVersion,
                        findingSummary: finding.title,
                        note: "Matched client memory rule for \(vendorName) (created by \(actorName))"
                    ))
                }
            }

            // Gauntlet Loop, Gauntlet C round 9 (2026-08-24): resolved into
            // locals before publishing — the most severe instance of this
            // pass's atomicity bug class. This block auto-dismisses
            // matching open findings on disk above; if `loadFindings()`
            // threw after `clientMemoryRules` had already published,
            // `self.findings` would keep its STALE value — meaning
            // `FindingsListView` kept showing findings as open that were
            // just dismissed on disk. A specific false claim, not just
            // missing data.
            let newClientMemoryRules = try await self.store.loadClientMemoryRules()
            let newFindings = try await self.store.loadFindings()
            let newActivityLog = try await self.store.loadActivityLog()
            self.clientMemoryRules = newClientMemoryRules
            self.findings = newFindings
            self.activityLog = newActivityLog
        }
        // `triggeringFindingID` is optional — this action isn't inherently
        // about one finding, it can auto-dismiss several. When the caller
        // knows which finding's button was tapped, it gets the full
        // in-flight/error/re-entry treatment via `performFindingAction`
        // (never navigates: `navigateToListIfScreenMatches` omitted).
        // Without it, there's no finding to attribute a failure to.
        if let triggeringFindingID {
            await performFindingAction(
                findingID: triggeringFindingID,
                failureMessage: { "This vendor wasn't remembered: \($0). Try again." },
                work
            )
        } else {
            do {
                try await work()
            } catch {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    /// The reversal for `createClientMemoryRule`. Does NOT retroactively
    /// un-dismiss findings that were already auto-dismissed by it — same
    /// one-way posture `ClientStore.dismissFinding` already has, documented
    /// there as a real, acknowledged gap rather than an oversight.
    ///
    /// Fixed 2026-09-05 — was two documented, deliberately-deferred gaps
    /// (Gauntlet Loop, Gauntlet B rounds 17 and 23, 2026-08-24):
    ///
    /// 1. On failure this used to only set the unread `loadState.failed`,
    ///    with no page-scoped error field or in-flight guard — a double-tap
    ///    on `ClientMemoryView`'s "Forget" could fire two concurrent
    ///    removals of the same rule with no indication anything went wrong.
    ///    Fixed the same way `findingActionInFlightIDs`/`findingActionError`
    ///    fixed the identical shape on the finding surface, scoped to
    ///    `ClientMemoryRule.id` instead of a finding id via
    ///    `clientMemoryActionInFlightIDs`/`clientMemoryActionError` below.
    /// 2. `ClientStore.removeClientMemoryRule` used to be a silent no-op on
    ///    an unknown id with no return value, while this method
    ///    unconditionally logged `.clientMemoryRuleRemoved` regardless — a
    ///    double-tap's second call was a genuine no-op still logged as if
    ///    it removed something, a false record in the Activity Log. Now
    ///    mirrors `dismissFinding`'s identical round-22 fix: only logs when
    ///    the store call actually removed a rule.
    public func removeClientMemoryRule(id: String, actorName: String) async {
        guard let rule = clientMemoryRules.first(where: { $0.id == id }), !clientMemoryActionInFlightIDs.contains(id) else { return }
        if clientMemoryActionError?.ruleID == id { clientMemoryActionError = nil }
        clientMemoryActionInFlightIDs.insert(id)
        defer { clientMemoryActionInFlightIDs.remove(id) }
        do {
            guard try await store.removeClientMemoryRule(id: id) else { return }
            try await store.appendActivityLogEntry(ActivityLogEntry(
                realmID: realmID,
                actor: .user(actorName),
                kind: .clientMemoryRuleRemoved,
                ruleID: rule.ruleID,
                note: "No longer always dismissing \(rule.ruleID.rawValue) findings for \(rule.vendorName)"
            ))
            // Gauntlet Loop, Gauntlet C round 9 (2026-08-24): resolved into
            // locals before publishing, same fix as `dismissFinding`'s
            // matching pair — a stale `activityLog` would hide the
            // `.clientMemoryRuleRemoved` entry just written above.
            let newClientMemoryRules = try await store.loadClientMemoryRules()
            let newActivityLog = try await store.loadActivityLog()
            clientMemoryRules = newClientMemoryRules
            activityLog = newActivityLog
        } catch {
            clientMemoryActionError = (ruleID: id, message: "This rule wasn't removed: \(error). Try again.")
        }
    }

    /// Any error from the last export attempt — surfaced so the caller can
    /// show it, rather than a silent failure if e.g. the chosen location
    /// isn't writable.
    public private(set) var exportError: String?

    /// The one export entry point every report-style page calls through.
    /// Presents a native `NSSavePanel` (the user picks the location and
    /// clicks Save themselves — this is a normal local save action, not
    /// something the app does on its own) then writes the chosen format's
    /// bytes. `suggestedFilename` should NOT include an extension; one is
    /// appended for the chosen format.
    public func exportTable(_ table: ExportTable, format: ReportExportFormat, suggestedFilename: String) {
        exportError = nil
        let data: Data
        let fileExtension: String
        switch format {
        case .csv:
            data = CSVReportExporter.export(table)
            fileExtension = "csv"
        case .xlsx:
            data = XLSXReportExporter.export(table)
            fileExtension = "xlsx"
        case .pdf:
            data = PDFReportExporter.export(table)
            fileExtension = "pdf"
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedFilename).\(fileExtension)"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportError = "Could not save \(url.lastPathComponent): \(error)"
        }
    }

    /// `ClosePackageView`'s "Export Branded PDF" — a separate save path
    /// from `exportTable` because `ClosePackagePDFExporter.Input` isn't an
    /// `ExportTable` (it's a multi-section document, not one flat table).
    /// Same `NSSavePanel` posture as `exportTable`.
    public func exportClosePackagePDF(_ input: ClosePackagePDFExporter.Input) {
        exportError = nil
        let data = ClosePackagePDFExporter.export(input)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Close Package.pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportError = "Could not save \(url.lastPathComponent): \(error)"
        }
    }

    /// Owner directive (2026-08-29): a client-facing PDF for the two
    /// AI-generated reports (Book Health Report, Client Value Summary),
    /// now that the report content itself is proven good. Same
    /// `NSSavePanel` posture as `exportTable`/`exportClosePackagePDF` — a
    /// normal local save the owner drives themselves, never sent anywhere
    /// on its own.
    public func exportAIReportPDF(reportTitle: String, providerLabel: String, bodyText: String, suggestedFilename: String) {
        exportError = nil
        let input = AIReportPDFExporter.Input(
            reportTitle: reportTitle,
            companyName: companyInfo?.companyName,
            environment: environment == .production ? "production" : "sandbox",
            period: currentPeriod,
            providerLabel: providerLabel,
            bodyText: bodyText
        )
        let data = AIReportPDFExporter.export(input)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedFilename).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportError = "Could not save \(url.lastPathComponent): \(error)"
        }
    }

    /// File > "Export Page as PDF…" — `RootView` renders whichever page is
    /// currently on screen into PDF `Data` itself (SwiftUI rendering isn't
    /// something `AppState` has access to, the same reason `RootView` also
    /// owns the ImageRenderer call) and hands the finished bytes here to
    /// save. Same `NSSavePanel` posture as `exportTable`/
    /// `exportClosePackagePDF`/`exportAIReportPDF` above — a normal local
    /// save the user drives themselves, never sent anywhere on its own.
    public func savePDFData(_ data: Data, suggestedFilename: String) {
        exportError = nil
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedFilename).pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportError = "Could not save \(url.lastPathComponent): \(error)"
        }
    }

    /// `RootView.exportCurrentPageAsPDF`'s failure path before there's any
    /// `Data` to hand to `savePDFData` at all (e.g. the page hasn't laid
    /// out yet) — reuses the same `exportError` the alert in `RootView
    /// .body` already displays, rather than introducing a second error
    /// channel for one more export path.
    public func reportPDFExportFailure(_ message: String) {
        exportError = message
    }

    public func clearExportError() {
        exportError = nil
    }

    // MARK: Client Intake

    /// Loads the roster from `IntakeRosterStore` — called on launch
    /// (`RootView`'s `.task`) and available as an explicit "Reload from
    /// File" action for picking up edits made directly in Google Sheets
    /// or Excel, never automatically/silently (see that store's own doc
    /// comment on why this is never a background watcher).
    public func loadIntakeRoster() {
        intakeRoster = intakeRosterStore.loadAll()
        intakeStatusMessage = nil
    }

    /// Clears the draft for a brand-new prospect — does NOT touch the
    /// saved roster.
    /// From the Pricing Calculator's "Save as Client…": copies only the
    /// pricing choices into the intake being edited (names and answers
    /// already typed there are kept) and opens Intake Questions.
    public func carryPricingToIntake(_ pricing: ClientIntake) {
        currentIntake.hourlyRateText = pricing.hourlyRateText
        currentIntake.volumeTier = pricing.volumeTier
        currentIntake.monthlyFlags = pricing.monthlyFlags
        currentIntake.needsCleanup = pricing.needsCleanup
        currentIntake.monthsBehind = pricing.monthsBehind
        currentIntake.cleanupIssues = pricing.cleanupIssues
        currentIntake.includeFindingsSummary = pricing.includeFindingsSummary
        screen = .intakeQuestions
        intakeStatusMessage = "Your pricing was carried over (\(currentIntake.monthlyQuote.monthlyInvestment.accountingDescription)/mo\(currentIntake.needsCleanup ? " + clean-up" : "")). Fill in the business name and the contact's name and email, then press Save Client at the top."
    }

    public func startNewIntake() {
        currentIntake = ClientIntake()
        intakeStatusMessage = nil
    }

    /// Loads an existing roster entry back into the live draft for
    /// editing — e.g. a follow-up call with the same prospect, or
    /// correcting something after the fact.
    public func loadIntakeForEditing(_ intake: ClientIntake) {
        currentIntake = intake
        intakeStatusMessage = nil
    }

    /// Upserts `currentIntake` into the roster by `id` and rewrites the
    /// whole CSV file — this is also, per the owner's own framing, "how a
    /// new client gets set up in the app": the roster is the firm's list
    /// of prospects/clients independent of which ones have gone on to
    /// authorize a real QBO connection.
    public func saveCurrentIntake() {
        if let index = intakeRoster.firstIndex(where: { $0.id == currentIntake.id }) {
            intakeRoster[index] = currentIntake
        } else {
            intakeRoster.append(currentIntake)
        }
        do {
            try intakeRosterStore.saveAll(intakeRoster)
            intakeStatusMessage = "Saved \(currentIntake.displayName) to \(intakeRosterStore.fileURL.path)"
        } catch {
            intakeStatusMessage = "Could not save: \(error)"
        }
    }

    public func clearIntakeStatusMessage() {
        intakeStatusMessage = nil
    }

    // MARK: AI Conversation History

    /// Owner directive (2026-09-28): an explicit, human-initiated wipe —
    /// see `AIConversationHistoryView`'s own doc comment on why this
    /// matters for data hygiene between clients. Only this realm's AI
    /// conversation log is touched; findings, activity log, and every
    /// other persisted record are untouched.
    public func clearConversationHistory() {
        conversationHistory = []
        Task { try? await store.clearAskAIConversationHistory() }
    }

    /// CLAUDE.md-adjacent honesty fix: every "Dismiss" button in the app
    /// previously just navigated back to the list without persisting
    /// anything — `Finding.status` never actually became `.dismissed`
    /// anywhere, and `RuleContext.dismissedFindingIDs` was never fed from
    /// real data, even though all 15 rules already check it. The very next
    /// sync would silently re-show the exact same "dismissed" finding.
    /// This closes that gap. No "un-dismiss" UI exists yet — a real gap,
    /// not an oversight; `ClientStore.dismissFinding` stays a one-way
    /// operation for now.
    public func dismissFinding(findingID: String, actorName: String, reason: String?) async {
        guard let finding = finding(id: findingID) else { return }
        let entry = ActivityLogEntry(
            realmID: realmID,
            actor: .user(actorName),
            kind: .findingDismissed,
            findingID: findingID,
            ruleID: finding.ruleID,
            ruleVersion: finding.ruleVersion,
            findingSummary: finding.title,
            note: reason
        )
        await performFindingAction(
            findingID: findingID,
            navigateToListIfScreenMatches: { if case .detail(let currentFindingID) = $0 { return currentFindingID == findingID }; return false },
            failureMessage: { "This finding wasn't dismissed: \($0). Try again." }
        ) {
            // Gauntlet Loop, Gauntlet B round 22 (2026-08-24): only logs
            // when this call actually changed the finding's status. If a
            // concurrent sync (an `isVoided` exclusion, or the client-
            // memory auto-dismiss loop) already resolved/dismissed it
            // first, `store.dismissFinding` is a genuine no-op — logging
            // `.findingDismissed` anyway would plant a false, user-
            // attributed claim in the Activity Log for what was actually a
            // system-driven change. The finding still ends up not-open
            // either way, so the user's intent is satisfied; only the
            // false record is what's being avoided.
            if try await self.store.dismissFinding(id: findingID) {
                try await self.store.appendActivityLogEntry(entry)
            }
            // Gauntlet Loop, Gauntlet C round 9 (2026-08-24): resolved into
            // locals before publishing — same atomicity fix as
            // `syncAndEvaluate()`/`loadFromDiskOnly()`. If `loadActivityLog()`
            // threw after `findings` had already published, the Activity
            // Log would silently miss the entry just written above while
            // `findings` correctly showed the dismissal — a real,
            // inconsistent combination, not just one stale property.
            let newFindings = try await self.store.loadFindings()
            let newActivityLog = try await self.store.loadActivityLog()
            self.findings = newFindings
            self.activityLog = newActivityLog
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package section:
    /// "carry-forward items." Never touches `Finding.status` — the finding
    /// stays exactly as open/resolved/dismissed as it already was; this
    /// only records that a human chose to defer it, for the Close Package
    /// to list.
    public func markFindingCarriedForward(findingID: String, actorName: String, reason: String?) async {
        guard let finding = finding(id: findingID) else { return }
        let mark = CarryForwardMark(findingID: findingID, period: period, markedBy: actorName, reason: reason)
        let entry = ActivityLogEntry(
            realmID: realmID,
            actor: .user(actorName),
            kind: .findingCarriedForward,
            findingID: findingID,
            ruleID: finding.ruleID,
            ruleVersion: finding.ruleVersion,
            findingSummary: finding.title,
            note: reason
        )
        await performFindingAction(
            findingID: findingID,
            failureMessage: { "This finding wasn't marked carried forward: \($0). Try again." }
        ) {
            try await self.store.addCarryForwardMark(mark)
            try await self.store.appendActivityLogEntry(entry)
            let newCarryForwardMarks = try await self.store.loadCarryForwardMarks()
            let newActivityLog = try await self.store.loadActivityLog()
            self.carryForwardMarks = newCarryForwardMarks
            self.activityLog = newActivityLog
        }
    }

    /// The reversal for `markFindingCarriedForward`.
    public func unmarkCarriedForward(findingID: String, actorName: String) async {
        guard let finding = finding(id: findingID) else { return }
        let entry = ActivityLogEntry(
            realmID: realmID,
            actor: .user(actorName),
            kind: .findingCarryForwardRemoved,
            findingID: findingID,
            ruleID: finding.ruleID,
            ruleVersion: finding.ruleVersion,
            findingSummary: finding.title,
            note: nil
        )
        await performFindingAction(
            findingID: findingID,
            failureMessage: { "This carry-forward mark wasn't removed: \($0). Try again." }
        ) {
            try await self.store.removeCarryForwardMark(findingID: findingID)
            try await self.store.appendActivityLogEntry(entry)
            let newCarryForwardMarks = try await self.store.loadCarryForwardMarks()
            let newActivityLog = try await self.store.loadActivityLog()
            self.carryForwardMarks = newCarryForwardMarks
            self.activityLog = newActivityLog
        }
    }

    /// Records that a `ClientQuestionDrafter`-drafted question was sent —
    /// Voice Ledger never sends it itself (no email/messaging integration
    /// exists), this only logs the human's own action, same "recorded, not
    /// verified by the app" posture as `attestCompletion`.
    public func recordClientQuestionSent(findingID: String, actorName: String, questionText: String) async {
        guard let finding = finding(id: findingID) else { return }
        let entry = ActivityLogEntry(
            realmID: realmID,
            actor: .user(actorName),
            kind: .clientQuestionDrafted,
            findingID: findingID,
            ruleID: finding.ruleID,
            ruleVersion: finding.ruleVersion,
            findingSummary: finding.title,
            note: questionText
        )
        // Never navigates — stays on FindingDetailView either way, so
        // `navigateToListIfScreenMatches` is omitted.
        await performFindingAction(
            findingID: findingID,
            failureMessage: { "This question wasn't recorded as sent: \($0). Try again." }
        ) {
            try await self.store.appendActivityLogEntry(entry)
            self.activityLog = try await self.store.loadActivityLog()
        }
    }

    /// Records the client's reply to a previously-sent question —
    /// `ClientQuestionDrafter`'s doc comment has the full "what this is and
    /// isn't" (still no real two-way channel; the bookkeeper types in what
    /// the client said). Attached to the finding the same way
    /// `recordClientQuestionSent` attaches the question itself: a new
    /// `ActivityLogEntry` keyed by `findingID`, not a separate record.
    public private(set) var reCatImportMessage: String?

    // MARK: Monthly client report (ECharts + WeasyPrint, rendered locally)
    public private(set) var isGeneratingMonthlyReport = false
    public private(set) var monthlyReportStage: String?
    public private(set) var monthlyReportError: String?
    private(set) var monthlyReportHistory: [MonthlyReportService.GeneratedReport] = []
    var previewedMonthlyReport: MonthlyReportService.GeneratedReport?

    func refreshMonthlyReportHistory() {
        guard let root = clientStoreRootDirectory else { return }
        monthlyReportHistory = MonthlyReportService.history(root: root, realmID: realmID)
    }

    public func generateMonthlyReport() async {
        guard !isGeneratingMonthlyReport else { return }
        guard let root = clientStoreRootDirectory else {
            monthlyReportError = "No local store location for this client."
            return
        }
        isGeneratingMonthlyReport = true
        monthlyReportError = nil
        defer { isGeneratingMonthlyReport = false; monthlyReportStage = nil }
        // A report is only as current as its findings: sync first unless
        // this session synced in the last 15 minutes (owner request 2026-09-29).
        if lastSyncedAt.map({ Date().timeIntervalSince($0) > 15 * 60 }) ?? true {
            monthlyReportStage = "Syncing with QuickBooks first…"
            let before = lastSyncedAt
            if isSyncInFlight {
                for _ in 0..<240 where isSyncInFlight { try? await Task.sleep(for: .milliseconds(500)) }
            } else {
                await syncAndEvaluate()
            }
            guard let after = lastSyncedAt, after != before else {
                if case .failed(let reason) = loadState {
                    monthlyReportError = "Report not generated: the sync with QuickBooks failed (\(reason)). Try Sync on the Dashboard, then generate again."
                } else {
                    monthlyReportError = "Report not generated: the sync with QuickBooks didn't finish. Try Sync on the Dashboard, then generate again."
                }
                return
            }
        }
        monthlyReportStage = "Reading 13 months of reports from QuickBooks…"
        do {
            let inputs = try await syncClient.loadMonthlyReportInputs(
                realmID: realmID, period: period,
                clientName: companyInfo?.companyName ?? "Client",
                environment: environment == .production ? "production" : "sandbox",
                findings: findings, coverage: coverage, today: AccountingDate(date: Date())
            )
            monthlyReportStage = "Checking figures…"
            var fullInputs = inputs
            fullInputs.activityLog = activityLog
            fullInputs.clientQuestions = ClientQuestionDrafter.threads(from: activityLog)
            let report = MonthlyReportBuilder.build(fullInputs)
            let generated = try await MonthlyReportService.render(report: report, root: root, realmID: realmID) { [weak self] stage in
                let text: String
                switch stage {
                case "charts": text = "Drawing charts…"
                case "html": text = "Laying out pages…"
                case "pdf": text = "Creating the PDF…"
                default: text = "Finishing…"
                }
                Task { @MainActor [weak self] in self?.monthlyReportStage = text }
            }
            refreshMonthlyReportHistory()
            previewedMonthlyReport = generated
        } catch {
            monthlyReportError = "Report not generated: \(error.localizedDescription)"
        }
    }

    /// Reads a client-filled ReCat sheet and records each explanation as
    /// that finding's client answer. Never writes to QBO.
    public func importReCatAnswers(from url: URL, actorName: String) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            reCatImportMessage = "Couldn't read that file. Save the sheet as CSV and try again."
            return
        }
        let answers = ReCatSheet.answers(fromRows: CSVParser.parse(text), openFindings: findings)
        for answer in answers {
            await recordClientQuestionAnswer(findingID: answer.findingID, actorName: "\(actorName) (from client ReCat sheet)", answerText: answer.text)
        }
        reCatImportMessage = answers.isEmpty
            ? "No filled-in answers found. Make sure the client typed in the \"\(ReCatSheet.explanationColumn)\" column and kept the ID column."
            : "Recorded \(answers.count) client answer\(answers.count == 1 ? "" : "s") onto their findings."
    }

    public func recordClientQuestionAnswer(findingID: String, actorName: String, answerText: String) async {
        guard let finding = finding(id: findingID) else { return }
        let entry = ActivityLogEntry(
            realmID: realmID,
            actor: .user(actorName),
            kind: .clientQuestionAnswered,
            findingID: findingID,
            ruleID: finding.ruleID,
            ruleVersion: finding.ruleVersion,
            findingSummary: finding.title,
            note: answerText
        )
        await performFindingAction(
            findingID: findingID,
            failureMessage: { "This answer wasn't recorded: \($0). Try again." }
        ) {
            try await self.store.appendActivityLogEntry(entry)
            self.activityLog = try await self.store.loadActivityLog()
        }
    }

    /// CLAUDE.md rule 2's "push" step for `.stagedAPI` actions — the only
    /// write path in the app. The caller (the view) is responsible for the
    /// "review" step: showing before/after and requiring an explicit tap,
    /// gated on `writeAccessEnabled == true`. This method does not check
    /// `writeAccessEnabled` itself — same reasoning as
    /// `QBOSyncClient.reclassifyPurchaseLine`'s doc comment: the backend's
    /// check is the authoritative one, a client-side pre-check would only
    /// be a second, spoofable copy of it. `verified: false` is recorded as
    /// an error, never silently treated as success (CLAUDE.md rule 5's
    /// "green means verified" posture applied to writes, not just checks).
    public func applyStagedFix(findingID: String, actorName: String) async {
        guard let finding = finding(id: findingID),
              let action = finding.proposedActions.first,
              let details = action.apiWriteDetails,
              !applyingFixFindingIDs.contains(findingID) else { return }

        // docs/VOICE_LEDGER_HANDOFF.md D4: "It blocks all further writes
        // to that entity until a resolution probe settles it." Checked
        // BEFORE anything else — a pending `.submitted`/`.unknown` entry
        // for this exact purchase+line means a prior attempt's true
        // outcome is still unresolved, so a second write here could
        // double-apply it.
        let journalID = "\(details.purchaseID):\(details.lineID)"
        if let pending = (try? await store.loadWriteJournal())?.first(where: { $0.id == journalID && ($0.state == .submitted || $0.state == .unknown) }) {
            applyFixError = (findingID: findingID, message: "A previous write to this transaction is still unresolved (recorded \(pending.submittedAt.formatted(date: .abbreviated, time: .shortened))) — resolve it first (\(Self.resolvePendingWriteActionName)) before trying again.")
            return
        }

        applyingFixFindingIDs.insert(findingID)
        // Gauntlet Loop, Gauntlet B round 20 (2026-08-24): scoped to THIS
        // finding, matching `performFindingAction`'s entry clearing —
        // unconditional clears here would wipe a different, still-valid
        // finding's error the instant Apply Fix started on this one.
        if applyFixError?.findingID == findingID { applyFixError = nil }
        if findingActionError?.findingID == findingID { findingActionError = nil }

        // Phase 1 — SUBMITTED, persisted and flushed BEFORE the network
        // call. A journal written after the call would lose the record of
        // a write that may have landed but whose response never arrived.
        let journalEntry = WriteJournalEntry(
            findingID: findingID, purchaseID: details.purchaseID, lineID: details.lineID,
            syncTokenBeforeWrite: details.expectedSyncToken, targetAccountID: details.suggestedAccountID
        )
        do {
            try await store.upsertWriteJournalEntry(journalEntry)
        } catch {
            applyFixError = (findingID: findingID, message: "Could not record the write attempt before starting it — nothing was sent to QBO: \(error)")
            applyingFixFindingIDs.remove(findingID)
            return
        }

        do {
            let result = try await syncClient.reclassifyPurchaseLine(
                realmID: realmID,
                purchaseID: details.purchaseID,
                lineID: details.lineID,
                expectedSyncToken: details.expectedSyncToken,
                newAccountID: details.suggestedAccountID
            )
            guard result.verified else {
                // Phase 2 — the call returned a definite, KNOWN answer:
                // QBO responded and its own round-trip check said no. Not
                // ambiguous — safe to mark `.failed` and let a retry
                // happen.
                var failedEntry = journalEntry
                failedEntry.state = .failed
                failedEntry.resolvedAt = Date()
                try? await store.upsertWriteJournalEntry(failedEntry)

                let message = "QBO did not confirm the change — nothing was recorded as resolved. Re-sync and check the transaction directly before retrying."
                applyFixError = (findingID: findingID, message: message)
                try await store.appendActivityLogEntry(ActivityLogEntry(
                    realmID: realmID,
                    actor: .user(actorName),
                    kind: .apiWriteRejected,
                    findingID: findingID,
                    ruleID: finding.ruleID,
                    ruleVersion: finding.ruleVersion,
                    findingSummary: finding.title,
                    note: "Attempted to reclassify purchase \(details.purchaseID) line \(details.lineID) from \(details.currentAccountName) to \(details.suggestedAccountName) — QBO did not confirm the change."
                ))
                activityLog = try await store.loadActivityLog()
                applyingFixFindingIDs.remove(findingID)
                return
            }

            // Phase 2 — SUCCESS, QBO-verified.
            var successEntry = journalEntry
            successEntry.state = .success
            successEntry.resolvedAt = Date()
            try? await store.upsertWriteJournalEntry(successEntry)

            let entry = ActivityLogEntry(
                realmID: realmID,
                actor: .user(actorName),
                kind: .apiWriteApplied,
                findingID: findingID,
                ruleID: finding.ruleID,
                ruleVersion: finding.ruleVersion,
                findingSummary: finding.title,
                note: "Reclassified purchase \(details.purchaseID) line \(details.lineID) from \(details.currentAccountName) to \(details.suggestedAccountName), QBO-verified",
                beforeSnapshotJSON: result.beforeSnapshotJSON,
                afterSnapshotJSON: result.afterSnapshotJSON
            )
            try await store.appendActivityLogEntry(entry)
            activityLog = try await store.loadActivityLog()
            applyingFixFindingIDs.remove(findingID)
            // The finding only actually resolves once a resync sees the
            // corrected account — same posture as attestCompletion's doc
            // comment: this is not treated as proof by itself.
            await syncAndEvaluate()
            // Gauntlet Loop, Gauntlet B round 18 (2026-08-24): only
            // navigate away if the user is STILL viewing this finding —
            // this is the widest window of any of the finding-action
            // methods (a real QBO network round-trip plus a full
            // `syncAndEvaluate()`), so it was the most reachable instance
            // of the navigation-hijack a fresh critic found: the app's
            // toolbar stays fully live during any in-flight write, so a
            // bookkeeper who navigated elsewhere while this awaited would
            // otherwise get yanked back to `.list` with no warning.
            if case .detail(let currentFindingID) = screen, currentFindingID == findingID {
                screen = findingReturnScreen
            }
        } catch {
            // Phase 2 — UNKNOWN. The call threw before any
            // `WriteVerificationResult` could be parsed: a timeout, a
            // dropped connection, a cancelled task. This is NOT the same
            // as a clean rejection — the request may have already reached
            // QBO and applied. Recorded as `.unknown`, which blocks any
            // further write to this same purchase+line until a resolution
            // probe settles it (`resolvePendingWrite`).
            var unknownEntry = journalEntry
            unknownEntry.state = .unknown
            try? await store.upsertWriteJournalEntry(unknownEntry)

            applyFixError = (findingID: findingID, message: "The write's outcome is unknown — the network call didn't return an answer, so it's not safe to assume it failed. This is now blocked from retrying until resolved (\(Self.resolvePendingWriteActionName)).")
            try? await store.appendActivityLogEntry(ActivityLogEntry(
                realmID: realmID,
                actor: .user(actorName),
                kind: .apiWriteUnknown,
                findingID: findingID,
                ruleID: finding.ruleID,
                ruleVersion: finding.ruleVersion,
                findingSummary: finding.title,
                note: "Attempted to reclassify purchase \(details.purchaseID) line \(details.lineID) from \(details.currentAccountName) to \(details.suggestedAccountName) — the call's outcome is unknown (no response received): \(error). This write is blocked from retrying until resolved."
            ))
            activityLog = (try? await store.loadActivityLog()) ?? activityLog
            applyingFixFindingIDs.remove(findingID)
        }
    }

    /// Named once so `applyStagedFix`'s two blocking-error messages stay
    /// in sync with whatever the UI actually calls this action.
    static let resolvePendingWriteActionName = "Resolve Pending Write"

    /// docs/VOICE_LEDGER_SPEC.md's `/voice` module — `VoiceEngine`'s only
    /// two touchpoints with `store`, which stays `private` to this type
    /// otherwise. Thin pass-throughs, same shape as every other
    /// load/save pair `AppState` already exposes.
    public func loadVoiceSessionContext() async -> VoiceSessionContext? {
        (try? await store.loadVoiceSessionContext()) ?? nil
    }

    public func saveVoiceSessionContext(_ context: VoiceSessionContext) async {
        try? await store.saveVoiceSessionContext(context)
    }

    public func appendVoiceTranscriptEntry(_ entry: VoiceTranscriptEntry) async {
        try? await store.appendVoiceTranscriptEntry(entry)
    }

    public func loadVoiceTranscript() async -> [VoiceTranscriptEntry] {
        (try? await store.loadVoiceTranscript()) ?? []
    }

    /// docs/VOICE_LEDGER_HANDOFF.md D4's resolution probe. Re-reads the
    /// purchase this journal entry targeted and compares its CURRENT
    /// `SyncToken`/line account against what the entry recorded before
    /// the write attempt (`WriteJournalResolution.resolve`, Core, pure —
    /// this method only fetches the inputs and records the outcome).
    /// Only meaningful for a `.submitted`/`.unknown` entry; a no-op for
    /// anything already resolved.
    public func resolvePendingWrite(journalEntryID: String, actorName: String) async {
        guard !isResolvingWriteJournalEntryIDs.contains(journalEntryID) else { return }
        isResolvingWriteJournalEntryIDs.insert(journalEntryID)
        defer { isResolvingWriteJournalEntryIDs.remove(journalEntryID) }

        do {
            guard var entry = try await store.loadWriteJournal().first(where: { $0.id == journalEntryID }) else { return }
            guard entry.state == .submitted || entry.state == .unknown else { return }

            let purchases = try await syncClient.fetchPurchases(realmID: realmID, period: period)
            let match = purchases.first { $0.id == entry.purchaseID }
            let currentSyncToken = match?.syncToken
            let currentAccountID = match?.lines.first { $0.id == entry.lineID }?.accountID

            let resolvedState = WriteJournalResolution.resolve(entry: entry, currentSyncToken: currentSyncToken, currentAccountID: currentAccountID)
            entry.state = resolvedState
            entry.resolvedAt = Date()
            let note: String
            switch resolvedState {
            case .failed:
                note = "Resolved: SyncToken unchanged since the write attempt — it did not land. Safe to retry."
            case .success:
                note = "Resolved: SyncToken changed and the line now shows the intended account — the write landed after all."
            case .ambiguous:
                note = "Could not resolve automatically — the purchase's SyncToken changed but not to what this write intended (or the purchase could no longer be found). Review this transaction directly in QBO."
            case .submitted, .unknown:
                note = "" // unreachable — resolve() never returns these
            }
            entry.resolutionNote = note
            try await store.upsertWriteJournalEntry(entry)

            try await store.appendActivityLogEntry(ActivityLogEntry(
                realmID: realmID,
                actor: .user(actorName),
                kind: resolvedState == .ambiguous ? .apiWriteAmbiguous : .apiWriteUnknownResolved,
                findingID: entry.findingID,
                note: note
            ))
            activityLog = try await store.loadActivityLog()
            writeJournal = try await store.loadWriteJournal()
        } catch {
            writeJournalError = "Could not resolve this pending write: \(error)"
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 7 (Batch Fixes) — applies the SAME
    /// `applyStagedFix` write, sequentially, to each finding in
    /// `findingIDs`. No new write logic: same round-trip verification,
    /// same Activity Log entries, same per-finding `applyingFixFindingIDs`/
    /// `applyFixError` tracking `FindingDetailView`'s single "Apply Fix"
    /// already uses — `BatchFixesView` renders those same per-finding
    /// signals for each row. Sequential, not concurrent: `applyStagedFix`
    /// itself calls `syncAndEvaluate()` after every success, so running
    /// these in parallel would mean overlapping syncs reading/writing
    /// `findings` at once — the exact race `isSyncInFlight` exists to
    /// prevent elsewhere in this file. `isApplyingBatchFix` is this
    /// method's own re-entrancy guard, the same shape `isSyncInFlight` uses
    /// for `syncAndEvaluate()`, so a rapid double-tap on "Apply All" cannot
    /// start two overlapping batches.
    public func applyBatchFix(findingIDs: [String], actorName: String) async {
        guard !isApplyingBatchFix else { return }
        isApplyingBatchFix = true
        for findingID in findingIDs {
            await applyStagedFix(findingID: findingID, actorName: actorName)
        }
        isApplyingBatchFix = false
    }

    /// Builds Ask AI context for the currently displayed page.
    /// Used by VoiceToolLoop to ground questions in the active screen's data.
    /// Moneypenny's picture of the current page. Every page — no exceptions —
    /// gets the same freshness sentence first and the same money formatting
    /// as the pages themselves (docs/MONEYPENNY_CONSISTENCY_DESIGN.md).
    public func currentPageAskAIContext() -> String {
        let data = clientData
        return "Data status: \(ClientFacts.freshnessSentence(data)) Period: \(ClientFacts.periodLabel(period)).\n"
            + ClientText.polish(pageBodyAskAIContext(data))
    }

    private func findingsPageContext(_ title: String, _ group: FactFindingGroup, _ data: ClientData) -> String {
        let list = ClientFacts.findings(data, category: group).value ?? []
        var lines = ["Page: \(title)."]
        if let exposure = ClientFacts.totalExposure(data, category: group).value { lines.append("Open findings on this page: \(list.count); total dollar exposure \(exposure.accountingDescription).") }
        for finding in list.prefix(25) { lines.append("- [ID: \(finding.id)] \(finding.title) (\(finding.severity.rawValue), \(finding.dollarExposure.accountingDescription))") }
        if list.count > 25 { lines.append("...and \(list.count - 25) more on the page.") }
        return lines.joined(separator: "\n")
    }

    private func reportPageContext(_ title: String, _ kind: ReportKind, _ data: ClientData) -> String {
        let fact = ClientFacts.reportLines(data, kind: kind)
        guard let lines = fact.value else { return "Page: \(title). \(fact.note ?? "Not loaded yet.")" }
        let totals = lines.filter(\.isSummary).compactMap { l in l.amount.map { "\(l.label): \($0.accountingDescription)" } }
        return "Page: \(title) (\(lines.count) lines on screen).\n" + totals.prefix(40).joined(separator: "\n")
    }

    private func pageBodyAskAIContext(_ data: ClientData) -> String {
        switch screen {
        case .cleanupAssessment: return findingsPageContext("Cleanup Assessment", .cleanupAssessment, data)
        case .balanceSheetIntegrity: return findingsPageContext("Balance Sheet Integrity", .balanceSheetIntegrity, data)
        case .bankFeedCleanup: return findingsPageContext("Bank Feed Cleanup", .cleanupAssessment, data)
        case .cashFlowReport: return reportPageContext("Cash Flow (Statement of Cash Flows)", .cashFlow, data)
        case .closePackage:
            return "Page: Close Package (monthly client report, balance sheet summary, month-end checklist for \(ClientFacts.periodLabel(period))). Open findings: \(ClientFacts.openFindingCount(data))."
        case .monthEndClose:
            return "Page: Month-End Close checklist for \(ClientFacts.periodLabel(period)). Open findings: \(ClientFacts.openFindingCount(data))."
        case .firmCockpit: return "Page: Firm Cockpit (all connected clients ranked by urgent findings)."
        case .taxes: return "Page: Taxes (tax estimate from net income)."
        case .salesTaxReview: return "Page: Sales Tax Review."
        case .batchFixes: return "Page: Batch Fixes (staged corrections awaiting approval)."
        case .activityLog: return "Page: Activity & Correction Log."
        case .clientMemory: return "Page: Client Memory (rules learned from this client's answers)."
        case .connection: return "Page: Connection (QuickBooks connection and AI settings)."
        case .scopeAndPeriodLock: return "Page: Scope & Period Lock."
        case .voiceHistory: return "Page: Voice history."
        case .audioSettings: return "Page: Audio Settings."
        case .trialBalanceReport: return "Page: Trial Balance (\(trialBalanceLines.count) lines on screen)."
        case .procedure: return "Page: guided fix procedure for the open finding."
        default: return legacyPageAskAIContext()
        }
    }

    private func legacyPageAskAIContext() -> String {
        switch screen {
        case .clientDashboard:
            var lines = ["Page: Client Dashboard (KPI dashboard with top findings, financial summary, working capital, and recurring vendor issues)."]
            let openFindings = findings.filter { $0.status == .open }
            if let workingCapital = FinancialKPIs.workingCapital(from: balanceSheetLines) {
                lines.append("Working capital: \(workingCapital.description)")
            }
            if let netIncome = TaxEstimate.netIncome(from: profitAndLossLines) {
                lines.append("Net income: \(netIncome.description)")
            }
            lines.append("Total open findings: \(openFindings.count)")
            if !cashFlowForecast.horizons.isEmpty {
                lines.append("Cash flow forecast available for the next 12 months")
            }
            return lines.joined(separator: "\n")

        case .list, .findingGroup:
            let openFindings = visibleFindings
            var lines = ["Page: \(findingsPageTitle) (filtered list visible on screen)."]
            lines.append("Open findings shown: \(openFindings.count)")
            lines.append("")
            lines.append("FINDINGS CURRENTLY LISTED ON THIS PAGE:")
            for finding in openFindings.prefix(20) {
                lines.append("- \(finding.title) (\(finding.severity.rawValue) severity, \(finding.dollarExposure.description)) [ID: \(finding.id)]")
            }
            if openFindings.count > 20 {
                lines.append("...and \(openFindings.count - 20) more findings below (scroll to see)")
            }
            return lines.joined(separator: "\n")

        case .detail(let findingID):
            if let finding = self.finding(id: findingID) {
                return "Page: Finding Detail (detailed view of a single finding).\n" + AskAIContext.compose(finding: finding)
            }
            return "Page: Finding Detail"

        case .balanceSheetReport:
            var lines = ["Page: Balance Sheet Report (assets, liabilities, and equity as of \(currentPeriod.year)-\(String(format: "%02d", currentPeriod.month)))."]
            if !balanceSheetLines.isEmpty {
                lines.append("Report contains \(balanceSheetLines.count) line items")
                if let totalAssets = balanceSheetLines.first(where: { $0.label.contains("TOTAL ASSETS") }), let amount = totalAssets.amount {
                    lines.append("Total Assets: \(amount.description)")
                }
            }
            return lines.joined(separator: "\n")

        case .profitAndLossReport:
            var lines = ["Page: Profit & Loss Report (income and expenses for period \(currentPeriod.year)-\(String(format: "%02d", currentPeriod.month)))."]
            if !profitAndLossLines.isEmpty {
                lines.append("Report contains \(profitAndLossLines.count) line items")
                if let totalIncome = TaxEstimate.netIncome(from: profitAndLossLines) {
                    lines.append("Net Income: \(totalIncome.description)")
                }
            }
            return lines.joined(separator: "\n")

        case .agedReceivablesReport:
            var lines = ["Page: Aged Receivables Report (amounts owed by customers)."]
            if !agedReceivablesLines.isEmpty {
                lines.append("Report contains \(agedReceivablesLines.count) customer entries")
            }
            return lines.joined(separator: "\n")

        case .agedPayablesReport:
            var lines = ["Page: Aged Payables Report (amounts owed to vendors)."]
            if !agedPayablesLines.isEmpty {
                lines.append("Report contains \(agedPayablesLines.count) vendor entries")
            }
            return lines.joined(separator: "\n")

        case .generalLedgerReport:
            var lines = ["Page: General Ledger Report (detailed transaction-level account history)."]
            lines.append("Transactions synced: \(transactions.count)")
            return lines.joined(separator: "\n")

        case .chartOfAccountsCleanup:
            var lines = ["Page: Chart of Accounts Cleanup (account structure and organization)."]
            lines.append("Total accounts: \(accounts.count)")
            return lines.joined(separator: "\n")

        case .cashFlowForecast:
            var lines = ["Page: Cash Flow Forecast (12-month projection of cash position)."]
            if !cashFlowForecast.horizons.isEmpty {
                lines.append("Forecast horizons: \(cashFlowForecast.horizons.count)")
            }
            return lines.joined(separator: "\n")

        case .recurringVendors:
            var lines = ["Page: Recurring Vendors (detected recurring transactions and patterns)."]
            lines.append("Missing recurring vendor configurations: \(missingRecurringVendors.count)")
            if !transactions.isEmpty {
                let topVendors = VendorSpendSummary.top(10, from: transactions)
                lines.append("Top vendors by spend: \(topVendors.map { $0.vendorName }.joined(separator: ", "))")
            }
            return lines.joined(separator: "\n")

        case .amountSearch:
            var lines = ["Page: Amount Search (find transactions matching a specific dollar amount)."]
            lines.append("Total transactions available: \(transactions.count)")
            return lines.joined(separator: "\n")

        case .pricingCalculator:
            return "Page: Pricing Calculator (estimate service fees and project scope for a prospect — not connected to any client)."

        case .intakeQuestions:
            return "Page: Intake Questions (discovery call script for prospect qualification and client onboarding)."

        case .complianceCalendar:
            var lines = ["Page: Compliance Calendar (filing and delivery dates for this client, next 120 days)."]
            lines += complianceDeadlines.prefix(12).map { "- \($0.date.formatted): \($0.title) — \($0.detail)" }
            return lines.joined(separator: "\n")

        case .scopeRequests:
            var lines = ["Page: Scope Requests (out-of-scope requests and their prices for this client)."]
            lines += scopeRequests.prefix(20).map { "- \($0.title): \($0.priceText), \($0.status.label)" }
            return lines.joined(separator: "\n")

        case .chartsGallery:
            return "Page: Charts & Cards (a clickable list of every card and chart Moneypenny can show)."

        case .industrySetup:
            let c = industryComparison
            return (["Page: Industry Setup (\(practiceProfile.industry.label) chart of accounts comparison).", "Missing recommended accounts: " + c.missing.map(\.name).joined(separator: ", ")]).joined(separator: "\n")

        case .diagnostics:
            guard let history = historySnapshot else {
                return "Page: Client Diagnostics. No multi-month history loaded yet — the person can press Load 24-Month History."
            }
            var lines = ["Page: Client Diagnostics (history \(history.from.formatted) to \(history.through.formatted), \(history.monthsCovered) months)."]
            if let scope = cleanupScopeScore {
                lines.append("Cleanup scope score: \(scope.score)/100 (\(scope.band)). Recommended cleanup quote \(scope.cleanupQuote.accountingDescription), \(scope.estimatedHoursLow)-\(scope.estimatedHoursHigh) hours; monthly retainer \(scope.monthlyRetainer.monthlyInvestment.accountingDescription).")
                lines.append("Inputs: \(scope.unreconciledMonths) unreconciled months (owner-entered), \(scope.openAnomalies) open anomalies, \(scope.uncategorizedTransactions) uncategorized, \(scope.undepositedPaymentCount) undeposited payments (\(scope.agedOver90Count) over 90 days), \(scope.duplicateAccountGroups) duplicate account groups, \(scope.averageMonthlyTransactions) transactions/month.")
            }
            let stale = bankFeedActivity.filter(\.isStale)
            lines.append(stale.isEmpty ? "Bank feeds: all active within 5 days." : "Stale bank feeds: " + stale.map { "\($0.accountName) (last posting \($0.lastActivity?.formatted ?? "none"))" }.joined(separator: "; "))
            lines.append(fluxAlerts.isEmpty ? "Flux: no P&L line swung >20% and >$500." : "Flux alerts: " + fluxAlerts.map { "\($0.label) \($0.current.accountingDescription) vs trailing avg \($0.trailingAverage.accountingDescription)" }.joined(separator: "; "))
            if let kpi = kpiSummary { lines.append("KPIs: " + kpi.emailBullets.joined(separator: "; ")) }
            return lines.joined(separator: "\n")

        default:
            let pageName = String(describing: screen)
            return "Page: \(pageName)"
        }
    }
}
