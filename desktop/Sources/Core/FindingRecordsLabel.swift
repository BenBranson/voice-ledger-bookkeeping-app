import Foundation

/// How many underlying records a finding is about, in words the owner uses.
/// A duplicate "pair" shows one dollar amount but two records; without this
/// label a row reads as if only one transaction were involved.
public enum FindingRecordsLabel {
    /// nil when the finding is about a single record (the common case).
    public static func text(for finding: Finding) -> String? {
        let n = Set(finding.evidence.map(\.transactionID)).count
        guard n > 1 else { return nil }
        let rule = finding.ruleID.rawValue
        if rule == "VL-DUP-VEND-001" { return "\(n) vendor records" }
        if rule.hasPrefix("VL-DUP-") { return "\(n) records (a duplicate pair)" }
        return "\(n) records"
    }
}
