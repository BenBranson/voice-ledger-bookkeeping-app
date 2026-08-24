import Foundation
import Observation
import AppKit
import Core
import IntegrationsQuickBooks
import IntegrationsImports
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
        case connection
        case list
        case detail(findingID: String)
        case procedure(findingID: String, actionID: String)
        case activityLog
        case cleanupAssessment
        case balanceSheetIntegrity
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
    }

    /// Which rules belong to the Cleanup Assessment view vs. Page 3's
    /// findings list — `Finding` itself doesn't carry a page/category
    /// distinction, only `ruleID`, so the view layer keys off the ID set.
    /// Fine at 3 rules; worth promoting to a real `Finding.sourcePage`
    /// field if the rule count grows enough to make this list unwieldy.
    public static let cleanupAssessmentRuleIDs: Set<String> = ["VL-CC-PAYMENT-001", "VL-PAYROLL-LUMP-001", "VL-OBE-BALANCE-001", "VL-BS-NEGBAL-001", "VL-DUP-VEND-001", "VL-DUP-BILL-001", "VL-DUP-INV-001", "VL-DUP-PAY-001", "VL-BS-UNDEP-001", "VL-VENDCREDIT-UNAPPLIED-001", "VL-FORCED-RECON-001", "VL-REPORT-TIE-001", "VL-FEE-AVOIDABLE-001"]

    /// Page 8's rules — a subset of `cleanupAssessmentRuleIDs` that also
    /// belong to the real Balance Sheet Integrity workflow page, not just
    /// the cross-cutting Cleanup Assessment tool. The two sets overlapping
    /// is intentional (docs/backlog/CLEANUP_MODE.md's assessment is meant to
    /// span multiple pages' rules), not a bug.
    public static let balanceSheetIntegrityRuleIDs: Set<String> = ["VL-BS-NEGBAL-001", "VL-OBE-BALANCE-001", "VL-BS-UNDEP-001", "VL-FORCED-RECON-001", "VL-REPORT-TIE-001"]

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
    /// All-time count of persisted imported statement lines for this realm
    /// (not period-filtered) — feeds `ReconciliationSummary.compute`'s
    /// `totalStatementLines`. Refreshed on every `syncAndEvaluate()`.
    public private(set) var importedStatementLineCount: Int = 0
    public private(set) var loadState: LoadState = .idle
    public var screen: Screen = .connection
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
        /// The file's own stated ending balance, shown to the user for a
        /// manual comparison against their bank's own statement — not an
        /// automated check (see `OFXBankStatementImporter.Result`'s doc
        /// comment for why). `nil` when the file has no `<LEDGERBAL>`.
        public let statedEndingBalance: Money?
        public let statedAsOfDate: AccountingDate?
    }
    public enum PendingImport {
        case csv(PendingCSVImport)
        case ofx(PendingOFXImport)
    }
    /// Known gap (Gauntlet Loop, Gauntlet B round 21, 2026-08-24,
    /// deliberately NOT fixed here): the same "single scalar meant for one
    /// in-flight operation, actually shared across however many a user can
    /// start" shape that `applyingFixFindingIDs`/`findingActionInFlightIDs`
    /// had before rounds 19/20 fixed them. `ImportBankStatementView`'s
    /// Cancel is never disabled while `confirmCSVImport`/`confirmOFXImport`
    /// awaits — cancel this import, start a second one on a different
    /// file, and the FIRST import's `Task` resuming later unconditionally
    /// overwrites `pendingImport`/`importError` with `nil`/its own value,
    /// silently discarding the second import's confirm-sheet state (or a
    /// real newer error) with zero indication anything happened. Correctly
    /// out of scope for THIS hardening run: Bank Feed Cleanup (Page 4) is
    /// a genuinely different page from `FindingDetailView`/`VL-DUP-EXP-001`'s
    /// finding surface — the same scope test round 17 applied to
    /// `removeClientMemoryRule`. Needs the identical `Set`/keyed-by-id
    /// treatment (or a simpler "only one import confirm sheet can be open,
    /// disable Cancel while confirming" guard) whenever Bank Feed Cleanup
    /// itself is hardened.
    public private(set) var pendingImport: PendingImport?
    public private(set) var importError: String?
    /// Loaded on launch and refreshed after every confirmed CSV import —
    /// `selectFileForImport` (synchronous, called from inside a
    /// `.fileImporter` completion) reads this in-memory cache rather than
    /// hitting the store itself, since it has no `async` context to do so.
    public private(set) var mappingHints: [MappingHint] = []
    /// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit "Client Memory, With
    /// Approval" — loaded at launch and refreshed after every mutation,
    /// same caching reason as `mappingHints`.
    public private(set) var clientMemoryRules: [ClientMemoryRule] = []

    // Month-End Close checklist (Page 11) state.
    public private(set) var checklistCompletions: [ChecklistItemCompletion] = []

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

    private let realmID: RealmID
    private let period: AccountingPeriod
    /// Exposed read-only so the view layer can filter period-scoped state
    /// (e.g. `checklistCompletions`) without duplicating the period value.
    public var currentPeriod: AccountingPeriod { period }
    private let backend: BackendClient
    private let syncClient: QBOSyncClient
    private let store: ClientStore
    private let engine: RuleEngine

    public init(realmID: RealmID, environment: QBOEnvironment, period: AccountingPeriod, backend: BackendClient, store: ClientStore) {
        self.realmID = realmID
        self.environment = environment
        self.period = period
        self.backend = backend
        self.syncClient = QBOSyncClient(backend: backend)
        self.store = store
        // All rules, not just Page 3's — Cleanup Assessment's rules must be
        // evaluated in the SAME engine call for §8.2a's relationship
        // gating to see both classes together (RuleEngineActor.swift).
        self.engine = RuleEngine(rules: RuleRegistry.all)
    }

    public func loadFromDiskOnly() async {
        loadState = .loading
        do {
            findings = try await store.loadFindings()
            activityLog = try await store.loadActivityLog()
            checklistCompletions = try await store.loadChecklistCompletions()
            mappingHints = try await store.loadMappingHints()
            clientMemoryRules = try await store.loadClientMemoryRules()
            loadState = .loaded
        } catch {
            loadState = .failed("\(error)")
        }
    }

    /// docs/VOICE_LEDGER_SPEC.md Page 11 — a human attestation, recorded not
    /// treated as proof (§11.4's same posture for finding completion).
    public func completeChecklistItem(_ itemID: ChecklistItemID, actorName: String, note: String?) async {
        do {
            let completion = ChecklistItemCompletion(itemID: itemID, period: period, completedBy: actorName, note: note)
            try await store.upsertChecklistCompletion(completion)
            checklistCompletions = try await store.loadChecklistCompletions()
        } catch {
            loadState = .failed("\(error)")
        }
    }

    public func uncompleteChecklistItem(_ itemID: ChecklistItemID) async {
        do {
            try await store.removeChecklistCompletion(itemID: itemID, period: period)
            checklistCompletions = try await store.loadChecklistCompletions()
        } catch {
            loadState = .failed("\(error)")
        }
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
            balanceSheetError = "\(error)"
        }
        isLoadingBalanceSheet = false
    }

    public func loadProfitAndLoss() async {
        isLoadingProfitAndLoss = true
        profitAndLossError = nil
        do {
            profitAndLossLines = try await syncClient.fetchProfitAndLoss(realmID: realmID, period: period)
        } catch {
            profitAndLossError = "\(error)"
        }
        isLoadingProfitAndLoss = false
    }

    public func loadCashFlow() async {
        isLoadingCashFlow = true
        cashFlowError = nil
        do {
            cashFlowLines = try await syncClient.fetchCashFlow(realmID: realmID, period: period)
        } catch {
            cashFlowError = "\(error)"
        }
        isLoadingCashFlow = false
    }

    public func loadTrialBalance() async {
        isLoadingTrialBalance = true
        trialBalanceError = nil
        do {
            trialBalanceLines = try await syncClient.fetchTrialBalance(realmID: realmID, period: period)
        } catch {
            trialBalanceError = "\(error)"
        }
        isLoadingTrialBalance = false
    }

    public func loadAgedReceivables() async {
        isLoadingAgedReceivables = true
        agedReceivablesError = nil
        do {
            agedReceivablesLines = try await syncClient.fetchAgedReceivables(realmID: realmID)
        } catch {
            agedReceivablesError = "\(error)"
        }
        isLoadingAgedReceivables = false
    }

    public func loadAgedPayables() async {
        isLoadingAgedPayables = true
        agedPayablesError = nil
        do {
            agedPayablesLines = try await syncClient.fetchAgedPayables(realmID: realmID)
        } catch {
            agedPayablesError = "\(error)"
        }
        isLoadingAgedPayables = false
    }

    public func loadGeneralLedger() async {
        isLoadingGeneralLedger = true
        generalLedgerError = nil
        do {
            generalLedgerLines = try await syncClient.fetchGeneralLedger(realmID: realmID, period: period)
        } catch {
            generalLedgerError = "\(error)"
        }
        isLoadingGeneralLedger = false
    }

    /// docs/phase-0/02_QBO_CAPABILITY_MATRIX.md row C1: a live, timestamped
    /// call, never a cached assumption — the same guarantee
    /// `voiceledger-devtool health` already proved from the CLI, now
    /// reachable from inside the app itself (step 1.3).
    public func checkHealth() async {
        isCheckingHealth = true
        healthCheckError = nil
        do {
            async let health = backend.healthCheck(realmID: realmID)
            async let info = syncClient.fetchCompanyInfo(realmID: realmID)
            async let writeAccess = backend.getWriteAccess(realmID: realmID)
            let (healthResultValue, infoValue, writeAccessValue) = try await (health, info, writeAccess)
            healthResult = healthResultValue
            companyInfo = infoValue
            writeAccessEnabled = writeAccessValue
        } catch {
            healthCheckError = "\(error)"
        }
        isCheckingHealth = false
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
            healthCheckError = "\(error)"
        }
        isTogglingWriteAccess = false
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
            coverage = syncedDataSet.coverage
            accounts = syncedDataSet.accounts

            // Merge in any previously-imported, persisted statement lines
            // (Universal Ingestion Tier 1) so VL-RECON-MISSING-001 sees them
            // on every sync, not just the run right after import.
            let importedLines = try await store.loadImportedStatementLines()
            importedStatementLineCount = importedLines.count

            // VL-FORCED-RECON-001 needs the P&L report (see that rule's doc
            // comment for why — the only API surface that shows a forced
            // reconciliation's discrepancy). Fetched here, not just on the
            // P&L page's own lazy Refresh, so the rule runs on every sync
            // rather than only after someone happens to visit that page.
            // A fetch failure here does NOT fail the whole sync — it just
            // means this one rule reports .cannotEvaluate, same as any
            // other optional-coverage source.
            let profitAndLossLines = (try? await syncClient.fetchProfitAndLoss(realmID: realmID, period: period)) ?? []
            // VL-REPORT-TIE-001 needs Balance Sheet + both aging reports, in
            // the SAME NormalizedDataSet the rule receives — added
            // 2026-08-18 immediately alongside the rule itself specifically
            // to avoid repeating the vendorCredits/profitAndLossLines
            // omission bugs found earlier this session in this exact spot.
            // Each fetched independently and `try?`-wrapped: one report
            // failing must not fail the whole sync, and must not silently
            // make another report's rule look unrelatedly broken.
            let balanceSheetLines = (try? await syncClient.fetchBalanceSheet(realmID: realmID, period: period)) ?? []
            let agedReceivablesLines = (try? await syncClient.fetchAgedReceivables(realmID: realmID)) ?? []
            let agedPayablesLines = (try? await syncClient.fetchAgedPayables(realmID: realmID)) ?? []

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
                coverage: syncedDataSet.coverage,
                companyFacts: syncedDataSet.companyFacts
            )

            // Loaded fresh, not read from `self.findings` — this must
            // reflect exactly what's on disk right now, not whatever the
            // last render happened to hold. A rule checks this set to skip
            // reproducing a finding at all (`CLAUDE.md` rule 2's
            // dismiss-is-real posture — not just hidden by a UI filter).
            let dismissedFindingIDs = Set(try await store.loadFindings().filter { $0.status == .dismissed }.map(\.id))
            let context = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: dataSet.companyFacts, dismissedFindingIDs: dismissedFindingIDs)
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
                    try await store.dismissFinding(id: finding.id)
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

            findings = try await store.loadFindings()
            activityLog = try await store.loadActivityLog()
            loadState = .loaded
        } catch {
            loadState = .failed("\(error)")
        }
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
    public func selectFileForImport(url: URL) {
        importError = nil
        let ext = url.pathExtension.lowercased()
        do {
            if ext == "ofx" || ext == "qfx" {
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

    public func cancelPendingImport() {
        pendingImport = nil
    }

    /// The confirm step (§9.4) — `mappings` are already `confirmed: true`
    /// by the time they reach here (`ImportBankStatementView` only emits
    /// confirmed mappings via its Confirm button). Persists the normalized
    /// lines via `ClientStore` and immediately re-evaluates so the result
    /// is visible without a separate manual sync.
    public func confirmCSVImport(mappings: [ColumnMapping], statementAccountID: String) async {
        guard case .csv(let pending) = pendingImport else { return }
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
            importError = "\(error)"
        }
    }

    /// OFX's counterpart — no column mapping to confirm (self-describing
    /// tags), so only the account needs an explicit human choice.
    public func confirmOFXImport(statementAccountID: String) async {
        guard case .ofx(let pending) = pendingImport else { return }
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
            pendingImport = nil
            await syncAndEvaluate()
        } catch {
            importError = "\(error)"
        }
    }

    public func finding(id: String) -> Finding? {
        findings.first { $0.id == id }
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
                screen = .list
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
                try await self.store.dismissFinding(id: finding.id)
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

            self.clientMemoryRules = try await self.store.loadClientMemoryRules()
            self.findings = try await self.store.loadFindings()
            self.activityLog = try await self.store.loadActivityLog()
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
                loadState = .failed("\(error)")
            }
        }
    }

    /// The reversal for `createClientMemoryRule`. Does NOT retroactively
    /// un-dismiss findings that were already auto-dismissed by it — same
    /// one-way posture `ClientStore.dismissFinding` already has, documented
    /// there as a real, acknowledged gap rather than an oversight.
    ///
    /// Known gap (Gauntlet Loop, Gauntlet B round 17, 2026-08-24, deliberately
    /// NOT fixed here): this has the identical silent-failure shape rounds
    /// 13-16 fixed everywhere on `VL-DUP-EXP-001`'s own finding surface —
    /// on failure it only sets the unread `loadState.failed`, and its only
    /// caller, `ClientMemoryView` (via `RootView.swift`'s `onForget`), has
    /// no error parameter to render one even if this method grew one.
    /// Correctly out of scope for THIS run: `ClientMemoryView` is a
    /// separate page (`.clientMemory`), not `FindingDetailView` or any type
    /// this rule's finding surface renders — unlike round 16's finding
    /// (buttons literally ON `FindingDetailView`), this one doesn't meet
    /// this run's own scope test. Needs its own error field (not
    /// `findingActionError` — this method isn't scoped to a finding, it
    /// acts on a `ClientMemoryRule.id`) and its own UI plumbing in
    /// `ClientMemoryView.swift` whenever that page is hardened.
    public func removeClientMemoryRule(id: String, actorName: String) async {
        guard let rule = clientMemoryRules.first(where: { $0.id == id }) else { return }
        do {
            try await store.removeClientMemoryRule(id: id)
            try await store.appendActivityLogEntry(ActivityLogEntry(
                realmID: realmID,
                actor: .user(actorName),
                kind: .clientMemoryRuleRemoved,
                ruleID: rule.ruleID,
                note: "No longer always dismissing \(rule.ruleID.rawValue) findings for \(rule.vendorName)"
            ))
            clientMemoryRules = try await store.loadClientMemoryRules()
            activityLog = try await store.loadActivityLog()
        } catch {
            loadState = .failed("\(error)")
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

    public func clearExportError() {
        exportError = nil
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
            try await self.store.dismissFinding(id: findingID)
            try await self.store.appendActivityLogEntry(entry)
            self.findings = try await self.store.loadFindings()
            self.activityLog = try await self.store.loadActivityLog()
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

        applyingFixFindingIDs.insert(findingID)
        // Gauntlet Loop, Gauntlet B round 20 (2026-08-24): scoped to THIS
        // finding, matching `performFindingAction`'s entry clearing —
        // unconditional clears here would wipe a different, still-valid
        // finding's error the instant Apply Fix started on this one.
        if applyFixError?.findingID == findingID { applyFixError = nil }
        if findingActionError?.findingID == findingID { findingActionError = nil }
        do {
            let result = try await syncClient.reclassifyPurchaseLine(
                realmID: realmID,
                purchaseID: details.purchaseID,
                lineID: details.lineID,
                expectedSyncToken: details.expectedSyncToken,
                newAccountID: details.suggestedAccountID
            )
            guard result.verified else {
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
                screen = .list
            }
        } catch {
            applyFixError = (findingID: findingID, message: "\(error)")
            try? await store.appendActivityLogEntry(ActivityLogEntry(
                realmID: realmID,
                actor: .user(actorName),
                kind: .apiWriteRejected,
                findingID: findingID,
                ruleID: finding.ruleID,
                ruleVersion: finding.ruleVersion,
                findingSummary: finding.title,
                note: "Attempted to reclassify purchase \(details.purchaseID) line \(details.lineID) from \(details.currentAccountName) to \(details.suggestedAccountName) — the call failed before QBO could respond: \(error)"
            ))
            activityLog = (try? await store.loadActivityLog()) ?? activityLog
            applyingFixFindingIDs.remove(findingID)
        }
    }
}
