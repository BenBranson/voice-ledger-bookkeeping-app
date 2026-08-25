import Foundation

/// docs/VOICE_LEDGER_SPEC.md's Firm Cockpit Close Package section: "carry-
/// forward items." A human's explicit decision to defer an open finding to
/// next period rather than resolve or dismiss it now — recorded, same
/// attestation posture as `ChecklistItemCompletion` (`CLAUDE.md`:
/// attestation is a record, not proof). **Never changes `Finding.status`**
/// — a carried-forward finding stays `.open` and keeps appearing on its
/// normal pages exactly as before; this mark only adds it to the Close
/// Package's carry-forward list.
public struct CarryForwardMark: Identifiable, Codable, Sendable, Equatable {
    /// Equal to `findingID` — at most one active mark per finding, so
    /// marking an already-marked finding again (e.g. an updated reason)
    /// replaces the prior record rather than accumulating duplicates, the
    /// same upsert-by-key shape `ChecklistItemCompletion` uses.
    public let id: String
    public let findingID: String
    public let period: AccountingPeriod
    public let markedAt: Date
    public let markedBy: String
    public let reason: String?

    public init(findingID: String, period: AccountingPeriod, markedAt: Date = Date(), markedBy: String, reason: String? = nil) {
        self.id = findingID
        self.findingID = findingID
        self.period = period
        self.markedAt = markedAt
        self.markedBy = markedBy
        self.reason = reason
    }
}
