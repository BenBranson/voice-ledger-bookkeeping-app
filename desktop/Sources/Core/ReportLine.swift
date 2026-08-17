import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 12 (Type A). A flattened line from a QBO
/// report — QBO's own report JSON is a recursive section tree (verified
/// live against a real `BalanceSheet`: `ASSETS > Current Assets > Bank
/// Accounts > Checking`, 4 levels deep). `depth` preserves the section
/// nesting for indentation without keeping the tree structure itself,
/// deliberately simpler than a fully faithful nested UI — real value
/// without over-building a general report-tree renderer this pass doesn't
/// need yet.
public struct ReportLine: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let amount: Money?
    public let depth: Int
    /// True for a section's own total row (QBO's `Summary`) — rendered
    /// distinctly (e.g. bold) so "Total Current Assets" doesn't read like
    /// just another account line.
    public let isSummary: Bool

    public init(label: String, amount: Money?, depth: Int, isSummary: Bool) {
        self.id = "\(depth)-\(label)-\(isSummary)-\(UUID().uuidString.prefix(8))"
        self.label = label
        self.amount = amount
        self.depth = depth
        self.isSummary = isSummary
    }
}
