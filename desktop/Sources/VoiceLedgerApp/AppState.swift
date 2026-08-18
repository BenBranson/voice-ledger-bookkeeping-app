import Foundation
import Observation
import Core
import IntegrationsQuickBooks
import IntegrationsImports
import DB

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
    }

    /// Which rules belong to the Cleanup Assessment view vs. Page 3's
    /// findings list — `Finding` itself doesn't carry a page/category
    /// distinction, only `ruleID`, so the view layer keys off the ID set.
    /// Fine at 3 rules; worth promoting to a real `Finding.sourcePage`
    /// field if the rule count grows enough to make this list unwieldy.
    public static let cleanupAssessmentRuleIDs: Set<String> = ["VL-CC-PAYMENT-001", "VL-PAYROLL-LUMP-001", "VL-OBE-BALANCE-001", "VL-BS-NEGBAL-001", "VL-DUP-VEND-001", "VL-DUP-BILL-001", "VL-DUP-INV-001", "VL-DUP-PAY-001", "VL-BS-UNDEP-001", "VL-VENDCREDIT-UNAPPLIED-001"]

    /// Page 8's rules — a subset of `cleanupAssessmentRuleIDs` that also
    /// belong to the real Balance Sheet Integrity workflow page, not just
    /// the cross-cutting Cleanup Assessment tool. The two sets overlapping
    /// is intentional (docs/backlog/CLEANUP_MODE.md's assessment is meant to
    /// span multiple pages' rules), not a bug.
    public static let balanceSheetIntegrityRuleIDs: Set<String> = ["VL-BS-NEGBAL-001", "VL-OBE-BALANCE-001", "VL-BS-UNDEP-001"]

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
    public private(set) var loadState: LoadState = .idle
    public var screen: Screen = .connection
    public let environment: QBOEnvironment

    // Connection Page (step 1.3) state.
    public private(set) var companyInfo: CompanyConnectionInfo?
    public private(set) var healthResult: HealthCheckResult?
    public private(set) var healthCheckError: String?
    public private(set) var isCheckingHealth = false
    public private(set) var writeAccessEnabled: Bool?
    public private(set) var isTogglingWriteAccess = false

    // Apply Fix (staged API write, VL-CC-PAYMENT-001's first consumer).
    public private(set) var isApplyingFix = false
    public private(set) var applyFixError: String?

    // Universal Ingestion Tier 1 — Bank Feed Cleanup (Page 4) import state.
    public struct PendingCSVImport {
        public let filename: String
        public let allRows: [[String]]
        public let hasHeaderRow: Bool
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
    public private(set) var pendingImport: PendingImport?
    public private(set) var importError: String?

    // Month-End Close checklist (Page 11) state.
    public private(set) var checklistCompletions: [ChecklistItemCompletion] = []

    // Reporting (Page 12) state.
    public private(set) var balanceSheetLines: [ReportLine] = []
    public private(set) var isLoadingBalanceSheet = false
    public private(set) var balanceSheetError: String?
    public private(set) var profitAndLossLines: [ReportLine] = []
    public private(set) var isLoadingProfitAndLoss = false
    public private(set) var profitAndLossError: String?

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
        loadState = .loading
        do {
            let syncedDataSet = try await syncClient.sync(realmID: realmID, period: period)
            coverage = syncedDataSet.coverage
            accounts = syncedDataSet.accounts

            // Merge in any previously-imported, persisted statement lines
            // (Universal Ingestion Tier 1) so VL-RECON-MISSING-001 sees them
            // on every sync, not just the run right after import.
            let importedLines = try await store.loadImportedStatementLines()
            let dataSet = NormalizedDataSet(
                realmID: syncedDataSet.realmID,
                period: syncedDataSet.period,
                transactions: syncedDataSet.transactions + importedLines,
                accounts: syncedDataSet.accounts,
                vendors: syncedDataSet.vendors,
                deposits: syncedDataSet.deposits,
                coverage: syncedDataSet.coverage,
                companyFacts: syncedDataSet.companyFacts
            )

            let context = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: dataSet.companyFacts)
            let evaluation = await engine.evaluate(pages: [.page3Transactions, .cleanupAssessment, .bankFeedCleanup], input: dataSet, context: context)

            var currentRunIDsByRule: [RuleID: Set<String>] = [:]
            for (ruleID, result) in evaluation.results {
                if case .findings(let ruleFindings) = result.outcome {
                    try await store.upsertFindings(ruleFindings)
                    currentRunIDsByRule[ruleID] = Set(ruleFindings.map(\.id))
                } else {
                    currentRunIDsByRule[ruleID] = []
                }
            }
            for (ruleID, currentIDs) in currentRunIDsByRule {
                try await store.reconcileAgainstLatestRun(currentRunFindingIDs: currentIDs, ruleID: ruleID)
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
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let ext = url.pathExtension.lowercased()
            if ext == "ofx" || ext == "qfx" {
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
            } else {
                let rows = CSVParser.parse(text)
                guard !rows.isEmpty else {
                    importError = "\(url.lastPathComponent) is empty."
                    return
                }
                pendingImport = .csv(PendingCSVImport(filename: url.lastPathComponent, allRows: rows, hasHeaderRow: true))
            }
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
            importError = "Import produced \(result.defects.count) issue(s): \(result.defects)"
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
            importError = "Import produced \(result.defects.count) issue(s): \(result.defects)"
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
            note: note
        )
        do {
            try await store.appendActivityLogEntry(entry)
            activityLog = try await store.loadActivityLog()
        } catch {
            loadState = .failed("\(error)")
        }
        screen = .list
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
              let details = action.apiWriteDetails else { return }

        isApplyingFix = true
        applyFixError = nil
        do {
            let result = try await syncClient.reclassifyPurchaseLine(
                realmID: realmID,
                purchaseID: details.purchaseID,
                lineID: details.lineID,
                expectedSyncToken: details.expectedSyncToken,
                newAccountID: details.suggestedAccountID
            )
            guard result.verified else {
                applyFixError = "QBO did not confirm the change — nothing was recorded as resolved. Re-sync and check the transaction directly before retrying."
                isApplyingFix = false
                return
            }
            let entry = ActivityLogEntry(
                realmID: realmID,
                actor: .user(actorName),
                kind: .apiWriteApplied,
                findingID: findingID,
                ruleID: finding.ruleID,
                ruleVersion: finding.ruleVersion,
                note: "Reclassified purchase \(details.purchaseID) line \(details.lineID) from \(details.currentAccountName) to \(details.suggestedAccountName), QBO-verified"
            )
            try await store.appendActivityLogEntry(entry)
            activityLog = try await store.loadActivityLog()
            isApplyingFix = false
            // The finding only actually resolves once a resync sees the
            // corrected account — same posture as attestCompletion's doc
            // comment: this is not treated as proof by itself.
            await syncAndEvaluate()
            screen = .list
        } catch {
            applyFixError = "\(error)"
            isApplyingFix = false
        }
    }
}
