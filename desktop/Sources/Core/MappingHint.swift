import Foundation
import CryptoKit

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.6/stage 6: "column mappings are
/// learned per client, so re-importing a similar export doesn't repeat the
/// same confirm-and-correct work." Matched by an EXACT header-row fingerprint
/// (same header text, same order, case/whitespace-insensitive) — a bank
/// export with even one column reordered or renamed gets a different `id`
/// and a fresh, unprefilled mapping screen, never a fuzzy "close enough"
/// reuse. This is what keeps `MappingOrigin.learned` (`ColumnMapping.swift`)
/// honest: a learned suggestion is still just a suggestion, shown
/// unconfirmed, and the human can always correct it before importing.
public struct MappingHint: Identifiable, Hashable, Codable, Sendable {
    public let id: MappingHintID
    /// The exact header row this hint was learned from, in file order.
    public let headers: [String]
    /// Parallel to `headers` — `fields[i]` is the confirmed target for
    /// `headers[i]` the last time this header shape was imported.
    public let fields: [MappedField]
    public let timesUsed: Int
    public let lastUsedAt: Date

    public init(id: MappingHintID, headers: [String], fields: [MappedField], timesUsed: Int, lastUsedAt: Date) {
        self.id = id
        self.headers = headers
        self.fields = fields
        self.timesUsed = timesUsed
        self.lastUsedAt = lastUsedAt
    }

    /// Deterministic — the same header row always produces the same id, so
    /// `ClientStore.upsertMappingHint` can update the existing hint (and
    /// increment `timesUsed`) instead of accumulating a duplicate per import.
    public static func makeID(headers: [String]) -> MappingHintID {
        let normalized = headers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let joined = normalized.joined(separator: "|")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return MappingHintID(rawValue: digest.map { String(format: "%02x", $0) }.joined())
    }
}
