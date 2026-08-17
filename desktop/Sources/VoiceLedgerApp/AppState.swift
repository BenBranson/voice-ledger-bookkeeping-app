import Foundation
import Observation
import Core
import IntegrationsQuickBooks
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
    }

    /// Which rules belong to the Cleanup Assessment view vs. Page 3's
    /// findings list — `Finding` itself doesn't carry a page/category
    /// distinction, only `ruleID`, so the view layer keys off the ID set.
    /// Fine at 3 rules; worth promoting to a real `Finding.sourcePage`
    /// field if the rule count grows enough to make this list unwieldy.
    public static let cleanupAssessmentRuleIDs: Set<String> = ["VL-CC-PAYMENT-001", "VL-PAYROLL-LUMP-001", "VL-OBE-BALANCE-001", "VL-BS-NEGBAL-001", "VL-DUP-VEND-001", "VL-DUP-BILL-001"]

    /// Page 8's rules — a subset of `cleanupAssessmentRuleIDs` that also
    /// belong to the real Balance Sheet Integrity workflow page, not just
    /// the cross-cutting Cleanup Assessment tool. The two sets overlapping
    /// is intentional (docs/backlog/CLEANUP_MODE.md's assessment is meant to
    /// span multiple pages' rules), not a bug.
    public static let balanceSheetIntegrityRuleIDs: Set<String> = ["VL-BS-NEGBAL-001", "VL-OBE-BALANCE-001"]

    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var findings: [Finding] = []
    public private(set) var activityLog: [ActivityLogEntry] = []
    public private(set) var coverage: Coverage = .partial(reason: "not synced yet")
    public private(set) var loadState: LoadState = .idle
    public var screen: Screen = .connection
    public let environment: QBOEnvironment

    // Connection Page (step 1.3) state.
    public private(set) var companyInfo: CompanyConnectionInfo?
    public private(set) var healthResult: HealthCheckResult?
    public private(set) var healthCheckError: String?
    public private(set) var isCheckingHealth = false

    private let realmID: RealmID
    private let period: AccountingPeriod
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
            loadState = .loaded
        } catch {
            loadState = .failed("\(error)")
        }
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
            let (healthResultValue, infoValue) = try await (health, info)
            healthResult = healthResultValue
            companyInfo = infoValue
        } catch {
            healthCheckError = "\(error)"
        }
        isCheckingHealth = false
    }

    /// docs/phase-0/11_VERTICAL_SLICE.md §11.2 pipeline steps 2-6: sync,
    /// normalize, evaluate, persist, re-render. Re-running this is what
    /// makes the isVoided exclusion resolve a finding (§11.1) — see
    /// `ClientStore.reconcileAgainstLatestRun`.
    public func syncAndEvaluate() async {
        loadState = .loading
        do {
            let dataSet = try await syncClient.sync(realmID: realmID, period: period)
            coverage = dataSet.coverage

            let context = RuleContext(period: period, materiality: .defaultPolicy, companyFacts: dataSet.companyFacts)
            let evaluation = await engine.evaluate(pages: [.page3Transactions, .cleanupAssessment], input: dataSet, context: context)

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
}
