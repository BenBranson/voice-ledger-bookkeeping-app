import Foundation

/// docs/phase-0/09_INGESTION_PIPELINE.md §9.3: "A deterministic parse either
/// succeeded or produced a `NormalizationDefect`; a confidence score would
/// imply a probabilistic process that didn't happen." Only the defects Tier
/// 1 CSV parsing can actually produce — not a speculative full set for
/// tiers not built yet.
public enum NormalizationDefect: Hashable, Sendable {
    /// §9.3: "Date format ambiguity is a defect, not a guess." `03/04/2026`
    /// is unresolvable without evidence — no day value across the column
    /// exceeds 12, so neither MM/DD nor DD/MM can be ruled out. Silently
    /// choosing US format is how transactions land in the wrong month.
    case ambiguousDateFormat(column: String, sampleValues: [String])
    case unparsableDate(row: Int, column: String, value: String)
    case unparsableAmount(row: Int, column: String, value: String)
    /// A `ColumnMapping` for a required field (`date`, `amount`) was never
    /// confirmed — refuse to import rather than trust it unconfirmed.
    case requiredMappingUnconfirmed(target: MappedField)
    /// A required field (`date` or `amount`) has no `ColumnMapping` at all.
    case requiredFieldUnmapped(target: MappedField)
    case emptyFile
}
