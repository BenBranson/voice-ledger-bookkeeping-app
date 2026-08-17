import Foundation

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.4 — "column mapping with a
/// confirm-and-correct step, never a silent guess." `unmapped` is deliberately
/// distinct from `ignored` (see the spec's own note): a column nobody looked
/// at and a column you consciously excluded are different situations, and
/// collapsing them is how a fee column goes missing from a statement.
public struct ColumnMapping: Hashable, Codable, Sendable {
    public let sourceColumn: Int
    public let sourceHeader: String?
    public let target: MappedField
    public let origin: MappingOrigin
    /// No mapping is used unconfirmed on first sight (§9.4). This pass has
    /// no confirm-and-correct UI yet — callers construct `ColumnMapping`
    /// directly with `confirmed: true`, which stands in for a human having
    /// already confirmed it out-of-band. `BankStatementCSVImporter` refuses
    /// to use an unconfirmed mapping rather than silently trusting it.
    public let confirmed: Bool

    public init(sourceColumn: Int, sourceHeader: String?, target: MappedField, origin: MappingOrigin, confirmed: Bool) {
        self.sourceColumn = sourceColumn
        self.sourceHeader = sourceHeader
        self.target = target
        self.origin = origin
        self.confirmed = confirmed
    }
}

public enum MappingOrigin: Hashable, Codable, Sendable {
    case learned(hintID: MappingHintID, timesUsed: Int)
    case suggested(confidence: Double)
    case userSpecified
}

public struct MappingHintID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public enum MappedField: Hashable, Codable, Sendable {
    case date, description, amount, debit, credit, runningBalance
    case referenceNumber, checkNumber, transactionType
    case ignored
    case unmapped
}
