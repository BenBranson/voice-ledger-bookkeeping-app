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

    /// A finding present in `stillDetectedIDs`' complement (i.e. no longer
    /// re-detected this sync) but still `.open` is NOT auto-resolved here —
    /// only an explicit exclusion match (like `isVoided`, evaluated by the
    /// rule itself) resolves a finding. This function exists so the Branch B
    /// resolution path (§11.1) is explicit: a finding resolves because the
    /// rule stopped producing it (the exclusion fired), which
    /// `reconcileAgainstLatestRun` below makes visible.
    public func reconcileAgainstLatestRun(currentRunFindingIDs: Set<String>, ruleID: RuleID) throws {
        var existing = try loadFindings()
        for i in existing.indices where existing[i].ruleID == ruleID && existing[i].status == .open {
            if !currentRunFindingIDs.contains(existing[i].id) {
                existing[i].status = .resolved
            }
        }
        try save(existing, to: findingsURL)
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
