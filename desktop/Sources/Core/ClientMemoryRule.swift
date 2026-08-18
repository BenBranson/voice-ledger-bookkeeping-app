import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit: "Client Memory, With Approval —
/// learns categories and patterns, but never silently: 'Always categorize
/// future Odessa Water transactions as Utilities?'" The full spec version
/// implies an actual recategorization; this is scoped down to what's safe
/// to build without a second write operation: remembering that a specific
/// (rule, vendor) pair is a known non-issue for this client, so it's
/// auto-dismissed on future syncs instead of asked about again — never
/// silently created (an explicit "Remember this vendor" action, never
/// bundled into Dismiss itself), and every auto-dismissal it causes is
/// still logged to the Activity Log with the rule's own id as the reason,
/// not hidden.
///
/// **Deliberately conservative matching, same lesson as `VL-DUP-VEND-001`/
/// `VL-COA-DUPACCT-001`'s false-positive findings**: exact vendor-name match
/// (case/whitespace-insensitive) only, scoped to one specific rule — never
/// fuzzy, never applied across rules. A memory rule for `VL-CC-PAYMENT-001`
/// + "VL Spike Amex" does not suppress `VL-PAYROLL-LUMP-001` findings for
/// the same vendor, even though both are "about" the same vendor — they are
/// different judgments about different things.
public struct ClientMemoryRule: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let ruleID: RuleID
    public let vendorName: String
    public let createdAt: Date
    public let createdBy: String
    public let note: String?

    public init(
        id: String = UUID().uuidString,
        ruleID: RuleID,
        vendorName: String,
        createdAt: Date = Date(),
        createdBy: String,
        note: String? = nil
    ) {
        self.id = id
        self.ruleID = ruleID
        self.vendorName = vendorName
        self.createdAt = createdAt
        self.createdBy = createdBy
        self.note = note
    }

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `findingVendorName` is `Finding.vendorName` — `nil` for a rule that
    /// has no single clear vendor never matches anything, by construction.
    public func matches(ruleID: RuleID, findingVendorName: String?) -> Bool {
        guard let findingVendorName else { return false }
        return self.ruleID == ruleID && Self.normalize(self.vendorName) == Self.normalize(findingVendorName)
    }
}
