import Foundation
import Core

/// docs/phase-0/07_CLIENT_ISOLATION.md §7.1: "one SQLite database per
/// `realmId`, plus a phantom type... not a `realm_id` column with a WHERE
/// clause." **This implementation is a scoped-down substitute, not the
/// spec'd SQLite store**: one JSON file pair per realm, under a
/// per-realm directory, so a cross-realm read is a wrong file path (still
/// structurally awkward to get wrong by accident) rather than a wrong SQL
/// predicate. It satisfies the isolation *property* §7.1 cares about — no
/// shared table a missed `WHERE` could leak across — without pulling in a
/// SQLite dependency for this pass. Swapping the storage engine later
/// (`FileManager` → SQLite) does not change this type's public API, since
/// callers only see `RealmID`-scoped operations.
public actor ClientStore {
    private let realmID: RealmID
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(realmID: RealmID, rootDirectory: URL) throws {
        self.realmID = realmID
        // §7.1's isolation key, made a path component — not a `WHERE`
        // clause, and not a mutable "current client" variable read from
        // shared state (CLAUDE.md rule 9).
        self.directory = rootDirectory.appending(path: realmID.rawValue, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    private var findingsURL: URL { directory.appending(path: "findings.json") }
    private var activityLogURL: URL { directory.appending(path: "activity-log.json") }
    private var importedStatementLinesURL: URL { directory.appending(path: "imported-statement-lines.json") }
    private var checklistCompletionsURL: URL { directory.appending(path: "checklist-completions.json") }
    private var mappingHintsURL: URL { directory.appending(path: "mapping-hints.json") }
    private var clientMemoryRulesURL: URL { directory.appending(path: "client-memory-rules.json") }
    private var engagementScopeURL: URL { directory.appending(path: "engagement-scope.json") }
    private var periodLockURL: URL { directory.appending(path: "period-lock.json") }
    private var periodLockSnapshotURL: URL { directory.appending(path: "period-lock-snapshot.json") }
    private var bankStatementReconciliationSnapshotsURL: URL { directory.appending(path: "bank-statement-reconciliation-snapshots.json") }
    private var carryForwardMarksURL: URL { directory.appending(path: "carry-forward-marks.json") }
    private var salesTaxAttestationURL: URL { directory.appending(path: "sales-tax-attestation.json") }
    private var taxEstimateSettingsURL: URL { directory.appending(path: "tax-estimate-settings.json") }

    // MARK: - Findings

    public func loadFindings() throws -> [Finding] {
        try load([Finding].self, from: findingsURL, default: [])
    }

    /// Upserts by `id` (deterministic per §8.5 — re-detection of the same
    /// problem produces the same ID, so this is idempotent across resyncs).
    public func upsertFindings(_ findings: [Finding]) throws {
        var existing = try loadFindings()
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for finding in findings {
            // Preserve status (open/resolved/dismissed) across a resync
            // that re-detects the same finding — a new detection of an
            // already-resolved problem should not silently reopen it.
            // Known landmine (Gauntlet Loop, Gauntlet B round 12,
            // 2026-08-24, `ResolvedFindingRecurrenceTests.swift`,
            // `docs/VOICE_LEDGER_HANDOFF.md`): this also means a GENUINE
            // recurrence (the rule re-detects the identical
            // affected-transaction set — same id — because the underlying
            // problem actually came back, e.g. an un-voided transaction) is
            // silently swallowed the same way, with no Activity Log trace
            // and a now-false "appears to be fixed" note left standing.
            // Deliberately not fixed here — this is a resolve/reopen
            // semantics decision, not a rendering/logging gap.
            if let prior = byID[finding.id], prior.status != .open {
                var carried = finding
                carried.status = prior.status
                byID[finding.id] = carried
            } else {
                byID[finding.id] = finding
            }
        }
        existing = Array(byID.values).sorted { $0.id < $1.id }
        try save(existing, to: findingsURL)
    }

    /// Marks a finding dismissed — the human's own call that this isn't
    /// worth acting on, distinct from `.resolved` (the underlying problem
    /// is actually fixed). Idempotent: dismissing an already-dismissed or
    /// already-resolved finding is a silent no-op rather than an error, so
    /// a caller never needs to check status first. No corresponding
    /// "un-dismiss" exists yet — a real gap, not an oversight; see
    /// `AppState.dismissFinding`'s doc comment.
    ///
    /// Returns whether this call actually changed the finding's status.
    /// Gauntlet Loop, Gauntlet B round 22 (2026-08-24): `AppState
    /// .dismissFinding` used to log a `.findingDismissed` Activity Log
    /// entry unconditionally after calling this, even on the silent-no-op
    /// path — reachable when a manual dismiss races a concurrent sync (a
    /// resync's `isVoided` exclusion, or the client-memory auto-dismiss
    /// loop, resolving/dismissing the same finding first). The Activity
    /// Log would then contain a false, user-attributed claim for a finding
    /// whose real on-disk status was actually system-driven — the exact
    /// class of dishonesty rounds 10/11 fixed for `findingResolved`, here
    /// on the write side instead of the read side.
    @discardableResult
    public func dismissFinding(id: String) throws -> Bool {
        var existing = try loadFindings()
        guard let index = existing.firstIndex(where: { $0.id == id }), existing[index].status == .open else { return false }
        existing[index].status = .dismissed
        try save(existing, to: findingsURL)
        return true
    }

    /// A finding present in `stillDetectedIDs`' complement (i.e. no longer
    /// re-detected this sync) but still `.open` is NOT auto-resolved here —
    /// only an explicit exclusion match (like `isVoided`, evaluated by the
    /// rule itself) resolves a finding. This function exists so the Branch B
    /// resolution path (§11.1) is explicit: a finding resolves because the
    /// rule stopped producing it (the exclusion fired), which
    /// `reconcileAgainstLatestRun` below makes visible.
    /// Returns the findings this call actually resolved, so the caller can
    /// log each one. Gauntlet Loop, Gauntlet B round 10 (2026-08-24): this
    /// used to just flip `status` with no return value — `ActivityKind
    /// .findingResolved` existed in `Core/ActivityLog.swift` with its own
    /// label but was never actually produced anywhere, so a finding could
    /// silently vanish from the open list (an exclusion like `isVoided`
    /// firing) with zero record of when or why, unlike a human dismissal
    /// (`AppState.dismissFinding`), which always logs. A bookkeeper reading
    /// the Activity & Correction Log — or a client asking why a finding
    /// disappeared — had nothing to point to.
    @discardableResult
    public func reconcileAgainstLatestRun(currentRunFindingIDs: Set<String>, ruleID: RuleID) throws -> [Finding] {
        var existing = try loadFindings()
        var resolved: [Finding] = []
        for i in existing.indices where existing[i].ruleID == ruleID && existing[i].status == .open {
            if !currentRunFindingIDs.contains(existing[i].id) {
                existing[i].status = .resolved
                resolved.append(existing[i])
            }
        }
        try save(existing, to: findingsURL)
        return resolved
    }

    // MARK: - Imported statement lines (Universal Ingestion Tier 1)

    /// Persisted so an imported statement survives an app relaunch and is
    /// re-merged into every subsequent sync's `NormalizedDataSet`, not just
    /// evaluated once at import time — `VL-RECON-MISSING-001` needs to see
    /// it on every run, the same way a synced `Purchase` is.
    public func loadImportedStatementLines() throws -> [LedgerTransaction] {
        try load([LedgerTransaction].self, from: importedStatementLinesURL, default: [])
    }

    /// Upserts by `id` (stable per `BankStatementCSVImporter`'s
    /// `documentID-rowN` scheme, so reimporting the same file is a no-op
    /// merge, not a duplicate) — same idempotency shape as `upsertFindings`.
    public func upsertImportedStatementLines(_ lines: [LedgerTransaction]) throws {
        var existing = try loadImportedStatementLines()
        var byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for line in lines { byID[line.id] = line }
        existing = Array(byID.values).sorted { $0.id < $1.id }
        try save(existing, to: importedStatementLinesURL)
    }

    // MARK: - Month-End Close checklist

    /// All completions ever recorded for this realm, across every period —
    /// callers filter by `period` themselves (mirrors how `findings` are
    /// loaded whole and filtered by the view layer).
    public func loadChecklistCompletions() throws -> [ChecklistItemCompletion] {
        try load([ChecklistItemCompletion].self, from: checklistCompletionsURL, default: [])
    }

    /// Upserts by `(itemID, period)` — re-marking the same item complete
    /// for the same period replaces the prior attestation (a corrected
    /// name/note) rather than accumulating duplicates.
    public func upsertChecklistCompletion(_ completion: ChecklistItemCompletion) throws {
        var existing = try loadChecklistCompletions()
        existing.removeAll { $0.itemID == completion.itemID && $0.period == completion.period }
        existing.append(completion)
        try save(existing, to: checklistCompletionsURL)
    }

    /// Un-marks an item complete for a period — the reverse of
    /// `upsertChecklistCompletion`, needed since an attestation can be a
    /// mistake (CLAUDE.md: attestation is recorded, not treated as proof).
    public func removeChecklistCompletion(itemID: ChecklistItemID, period: AccountingPeriod) throws {
        var existing = try loadChecklistCompletions()
        existing.removeAll { $0.itemID == itemID && $0.period == period }
        try save(existing, to: checklistCompletionsURL)
    }

    // MARK: - Learned column mappings (§9.6 stage 6)

    public func loadMappingHints() throws -> [MappingHint] {
        try load([MappingHint].self, from: mappingHintsURL, default: [])
    }

    /// Upserts by `MappingHint.makeID(headers:)` — a reimport of a file
    /// with the identical header row increments `timesUsed` and replaces
    /// `fields` with whatever was just confirmed (a correction to a
    /// previously-learned mapping sticks; it is not silently overridden by
    /// the older one).
    public func upsertMappingHint(headers: [String], fields: [MappedField]) throws {
        let id = MappingHint.makeID(headers: headers)
        var existing = try loadMappingHints()
        let timesUsed = (existing.first { $0.id == id }?.timesUsed ?? 0) + 1
        existing.removeAll { $0.id == id }
        existing.append(MappingHint(id: id, headers: headers, fields: fields, timesUsed: timesUsed, lastUsedAt: Date()))
        try save(existing, to: mappingHintsURL)
    }

    // MARK: - Client memory rules

    public func loadClientMemoryRules() throws -> [ClientMemoryRule] {
        try load([ClientMemoryRule].self, from: clientMemoryRulesURL, default: [])
    }

    public func addClientMemoryRule(_ rule: ClientMemoryRule) throws {
        var existing = try loadClientMemoryRules()
        existing.append(rule)
        try save(existing, to: clientMemoryRulesURL)
    }

    /// The reversal for `addClientMemoryRule` — "with approval" cuts both
    /// ways; a client memory rule the human no longer wants must be just as
    /// easy to remove as it was to create.
    public func removeClientMemoryRule(id: String) throws {
        var existing = try loadClientMemoryRules()
        existing.removeAll { $0.id == id }
        try save(existing, to: clientMemoryRulesURL)
    }

    // MARK: - Scope & Period Lock (docs/VOICE_LEDGER_SPEC.md Page 2)

    public func loadEngagementScope() throws -> EngagementScope {
        try load(EngagementScope.self, from: engagementScopeURL, default: EngagementScope())
    }

    public func saveEngagementScope(_ scope: EngagementScope) throws {
        try save(scope, to: engagementScopeURL)
    }

    /// `nil` means no lock has ever been set for this realm — distinct from
    /// a lock existing at some far-past period, so callers can tell "never
    /// locked" from "locked, just not recently."
    public func loadPeriodLock() throws -> PeriodLock? {
        try load(PeriodLock?.self, from: periodLockURL, default: nil)
    }

    public func savePeriodLock(_ lock: PeriodLock) throws {
        try save(lock, to: periodLockURL)
    }

    /// The reverse of `savePeriodLock` — a lock set in error must be as
    /// removable as a checklist completion (§11.4's same posture: an
    /// attestation is a record, not an irreversible fact).
    public func clearPeriodLock() throws {
        guard FileManager.default.fileExists(atPath: periodLockURL.path) else { return }
        try FileManager.default.removeItem(at: periodLockURL)
        // The snapshot is only meaningful alongside its lock — an orphaned
        // snapshot from a cleared lock would let `VL-CLOSED-PERIOD-DRIFT-001`
        // compare against a period nobody currently considers locked.
        try? FileManager.default.removeItem(at: periodLockSnapshotURL)
    }

    /// `VL-CLOSED-PERIOD-DRIFT-001`'s baseline — `nil` when the current
    /// lock (if any) predates this feature, or no lock has been set.
    public func loadPeriodLockSnapshot() throws -> PeriodLockSnapshot? {
        try load(PeriodLockSnapshot?.self, from: periodLockSnapshotURL, default: nil)
    }

    public func savePeriodLockSnapshot(_ snapshot: PeriodLockSnapshot) throws {
        try save(snapshot, to: periodLockSnapshotURL)
    }

    // MARK: - Bank statement reconciliation snapshots (VL-RECON-DIFF-001)

    public func loadBankStatementReconciliationSnapshots() throws -> [BankStatementReconciliationSnapshot] {
        try load([BankStatementReconciliationSnapshot].self, from: bankStatementReconciliationSnapshotsURL, default: [])
    }

    /// Upserts by `accountID` — a later statement import for the same
    /// account replaces the earlier snapshot rather than accumulating a
    /// history, since only the most recent statement is a meaningful
    /// reconciliation baseline.
    public func saveBankStatementReconciliationSnapshot(_ snapshot: BankStatementReconciliationSnapshot) throws {
        var existing = try loadBankStatementReconciliationSnapshots()
        existing.removeAll { $0.accountID == snapshot.accountID }
        existing.append(snapshot)
        try save(existing, to: bankStatementReconciliationSnapshotsURL)
    }

    // MARK: - Carry-forward marks (Close Package)

    public func loadCarryForwardMarks() throws -> [CarryForwardMark] {
        try load([CarryForwardMark].self, from: carryForwardMarksURL, default: [])
    }

    /// Upserts by `findingID` — re-marking an already-marked finding
    /// replaces the prior mark (an updated reason) rather than
    /// accumulating duplicates.
    public func addCarryForwardMark(_ mark: CarryForwardMark) throws {
        var existing = try loadCarryForwardMarks()
        existing.removeAll { $0.findingID == mark.findingID }
        existing.append(mark)
        try save(existing, to: carryForwardMarksURL)
    }

    /// The reversal — a carry-forward mark set in error must be as
    /// removable as a checklist completion.
    public func removeCarryForwardMark(findingID: String) throws {
        var existing = try loadCarryForwardMarks()
        existing.removeAll { $0.findingID == findingID }
        try save(existing, to: carryForwardMarksURL)
    }

    // MARK: - Sales Tax Review attestation (Page 9)

    public func loadSalesTaxAttestation() throws -> SalesTaxAttestation {
        try load(SalesTaxAttestation.self, from: salesTaxAttestationURL, default: SalesTaxAttestation())
    }

    public func saveSalesTaxAttestation(_ attestation: SalesTaxAttestation) throws {
        try save(attestation, to: salesTaxAttestationURL)
    }

    // MARK: - Tax estimate settings (Page 10)

    public func loadTaxEstimateSettings() throws -> TaxEstimateSettings {
        try load(TaxEstimateSettings.self, from: taxEstimateSettingsURL, default: TaxEstimateSettings())
    }

    public func saveTaxEstimateSettings(_ settings: TaxEstimateSettings) throws {
        try save(settings, to: taxEstimateSettingsURL)
    }

    // MARK: - Activity log

    /// Append-only per §10.8 — no update, no delete method exists on this
    /// store for the activity log, which is what makes append-only a
    /// property of the API, not a convention someone could forget.
    public func appendActivityLogEntry(_ entry: ActivityLogEntry) throws {
        var existing = try load([ActivityLogEntry].self, from: activityLogURL, default: [])
        existing.append(entry)
        try save(existing, to: activityLogURL)
    }

    public func loadActivityLog() throws -> [ActivityLogEntry] {
        try load([ActivityLogEntry].self, from: activityLogURL, default: [])
    }

    // MARK: - Helpers

    private func load<T: Decodable>(_ type: T.Type, from url: URL, default defaultValue: T) throws -> T {
        guard FileManager.default.fileExists(atPath: url.path) else { return defaultValue }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return defaultValue }
        return try decoder.decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
