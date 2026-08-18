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

    /// The confirm screens previously interpolated `NormalizationDefect`
    /// directly into an error string (`"\(result.defects)"`), which prints
    /// Swift's default enum description (`ambiguousDateFormat(column: "Date",
    /// sampleValues: [...])`) — technically informative, not something a
    /// bookkeeper should have to read. A real, human-readable message per
    /// case instead.
    public var humanDescription: String {
        switch self {
        case .ambiguousDateFormat(let column, let sampleValues):
            return "Column \"\(column)\" has an ambiguous date format (could be MM/DD or DD/MM) — sample values: \(sampleValues.joined(separator: ", "))"
        case .unparsableDate(let row, let column, let value):
            return "Row \(row + 1): could not parse \"\(value)\" in column \"\(column)\" as a date"
        case .unparsableAmount(let row, let column, let value):
            return "Row \(row + 1): could not parse \"\(value)\" in column \"\(column)\" as an amount"
        case .requiredMappingUnconfirmed(let target):
            return "The \(target) column mapping was not confirmed"
        case .requiredFieldUnmapped(let target):
            return "No column was mapped to \(target) — it's required"
        case .emptyFile:
            return "The file is empty"
        }
    }
}
