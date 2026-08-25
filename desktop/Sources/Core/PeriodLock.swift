import Foundation

/// docs/VOICE_LEDGER_SPEC.md Page 2 (Type A + C), scoped-down slice:
/// engagement scope plus Voice Ledger's own stricter period lock. "Reads
/// QBO's `BookCloseDate`" stays out of scope — checked live and confirmed
/// absent from this sandbox's `Preferences` response (see
/// `MonthEndChecklist.swift`'s note, `VL-PERIOD-CLOSED-001` in
/// `08_RULE_ENGINE.md` §8.8), so there is no verified field to read yet.
/// Catching QBO error codes 6200/6210 also stays out of scope — the app has
/// no batch write path that would hit a closed-period rejection (Page 7,
/// not built).
public struct EngagementScope: Codable, Sendable, Equatable {
    public var servicesIncluded: Set<String>
    public var qboaAccountantAccessAttested: Bool
    public var attestedBy: String?
    public var attestedAt: Date?

    public init(servicesIncluded: Set<String> = [], qboaAccountantAccessAttested: Bool = false, attestedBy: String? = nil, attestedAt: Date? = nil) {
        self.servicesIncluded = servicesIncluded
        self.qboaAccountantAccessAttested = qboaAccountantAccessAttested
        self.attestedBy = attestedBy
        self.attestedAt = attestedAt
    }

    /// The service list `docs/VOICE_LEDGER_HANDOFF.md` §2 names as what the
    /// owner actually offers. Not exhaustive by design — AR/AP work is
    /// deliberately excluded, matching "He does NOT do AR or AP work."
    public static let availableServices: [String] = [
        "Reconciliations",
        "Monthly closing",
        "Transaction categorization",
        "Duplicate fixing",
        "Cleanup of messy books"
    ]
}

/// A lock the bookkeeper sets inside Voice Ledger itself: every period up to
/// and including `lockedThrough` is closed to further review by this app,
/// independent of whatever QBO's own closing date says. **This is a local
/// convention, not a QBO write** — setting it never touches QBO and never
/// blocks a QBO write; it only warns Voice Ledger's own screens.
public struct PeriodLock: Codable, Sendable, Equatable {
    public let lockedThrough: AccountingPeriod
    public let lockedAt: Date
    public let lockedBy: String
    public let note: String?

    public init(lockedThrough: AccountingPeriod, lockedAt: Date = Date(), lockedBy: String, note: String? = nil) {
        self.lockedThrough = lockedThrough
        self.lockedAt = lockedAt
        self.lockedBy = lockedBy
        self.note = note
    }

    /// True when `date` falls in `lockedThrough`'s month or any earlier one.
    public func isLocked(_ date: AccountingDate) -> Bool {
        (date.year, date.month) <= (lockedThrough.year, lockedThrough.month)
    }
}

public enum PeriodLockCheck {
    /// Non-voided transactions dated on or before `lock.lockedThrough` —
    /// Voice Ledger's own closed-period warning. A void is a correction to
    /// existing activity, not new activity landing in a closed period, so
    /// voided transactions are excluded the same way `VL-DUP-EXP-001` and
    /// friends exclude them from detection.
    public static func transactionsInLockedPeriod(_ transactions: [LedgerTransaction], lock: PeriodLock) -> [LedgerTransaction] {
        transactions.filter { !$0.isVoided && lock.isLocked($0.txnDate) }
    }
}
