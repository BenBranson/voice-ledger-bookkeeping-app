import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 12 (Type A). A flattened line from a QBO
/// report — QBO's own report JSON is a recursive section tree (verified
/// live against a real `BalanceSheet`: `ASSETS > Current Assets > Bank
/// Accounts > Checking`, 4 levels deep). `depth` preserves the section
/// nesting for indentation without keeping the tree structure itself,
/// deliberately simpler than a fully faithful nested UI — real value
/// without over-building a general report-tree renderer this pass doesn't
/// need yet.
public struct ReportLine: Identifiable, Hashable, Sendable, Codable {
    public let id: String
    public let label: String
    public let amount: Money?
    public let depth: Int
    /// True for a section's own total row (QBO's `Summary`) — rendered
    /// distinctly (e.g. bold) so "Total Current Assets" doesn't read like
    /// just another account line.
    public let isSummary: Bool
    /// QBO's Account Id for an account row (report ColData `id`); `nil` for
    /// section headers, totals, and computed rows like Net Income.
    public let accountID: String?

    public init(label: String, amount: Money?, depth: Int, isSummary: Bool, accountID: String? = nil) {
        self.id = "\(depth)-\(label)-\(isSummary)-\(UUID().uuidString.prefix(8))"
        self.label = label
        self.amount = amount
        self.depth = depth
        self.isSummary = isSummary
        self.accountID = accountID
    }

    /// Stable across refreshes: the account ID when QBO supplies one,
    /// otherwise the label (never an array position or random ID).
    public var stableKey: String { accountID.map { "acct:\($0)" } ?? "label:\(label)" }
}

extension Array where Element == ReportLine {
    /// "Truck: Original Cost" for an account row nested directly under a parent
    /// ACCOUNT heading (a heading with an account id). Section headings like
    /// "Bank Accounts" carry no account id and never prefix. Keyed by line id.
    public func qualifiedLabels() -> [String: String] {
        var headings: [ReportLine] = []
        var out: [String: String] = [:]
        for line in self {
            while let top = headings.last, top.depth >= line.depth { headings.removeLast() }
            if line.amount == nil && !line.isSummary { headings.append(line); continue }
            if !line.isSummary, let parent = headings.last, parent.accountID != nil, parent.depth == line.depth - 1,
               !line.label.hasPrefix(parent.label) {
                out[line.id] = "\(parent.label): \(line.label)"
            }
        }
        return out
    }
}
