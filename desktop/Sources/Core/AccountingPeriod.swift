import Foundation

/// A calendar month, the unit docs/phase-0/11_VERTICAL_SLICE.md §11.2 scopes
/// detection to. docs/phase-0/04_DATA_MODEL.md.
public struct AccountingPeriod: Hashable, Codable, Sendable {
    public let year: Int
    public let month: Int // 1...12

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "month must be 1...12")
        self.year = year
        self.month = month
    }

    public func contains(_ date: AccountingDate) -> Bool {
        date.year == year && date.month == month
    }

    /// The calendar month immediately before this one — December wraps to
    /// November of the prior year. Used for variance analysis's default
    /// comparison ("vs. last month"), the simplest and least surprising
    /// baseline; a same-month-prior-year comparison is a real, different
    /// question this doesn't answer and isn't built.
    public var previousMonth: AccountingPeriod {
        month == 1 ? AccountingPeriod(year: year - 1, month: 12) : AccountingPeriod(year: year, month: month - 1)
    }

    /// Added for `AgingSummary.daysOutstanding` (DSO/DPO estimates) — a
    /// plain calendar fact, not a QBO-sourced value, so no "not available"
    /// case is needed.
    public var daysInMonth: Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear ? 29 : 28
        default: return 30
        }
    }

    private var isLeapYear: Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}

/// A calendar date with no time-of-day or timezone component. QBO's
/// `TxnDate` is a date, not an instant — treating it as one invites
/// off-by-one-day bugs across timezones.
public struct AccountingDate: Hashable, Codable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses QBO's `TxnDate` shape, `"YYYY-MM-DD"`. Traps on malformed
    /// input — callers own validating data that crossed a trust boundary
    /// before this point; this type has no silent fallback date.
    public init(qboDateString: String) {
        let parts = qboDateString.split(separator: "-")
        precondition(parts.count == 3, "Malformed QBO date: \(qboDateString)")
        guard let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            preconditionFailure("Malformed QBO date: \(qboDateString)")
        }
        self.year = y
        self.month = m
        self.day = d
    }

    /// UTC calendar date components of `date` — used for "as of today"
    /// comparisons (e.g. `VL-BS-UNDEP-001`'s aging check), never for
    /// re-deriving a QBO `TxnDate` (which already has its own
    /// `qboDateString` initializer).
    public init(date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = comps.year!
        self.month = comps.month!
        self.day = comps.day!
    }

    public static func < (lhs: AccountingDate, rhs: AccountingDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// `"YYYY-M-D"`, matching the convention `DuplicatePostedExpenseRule`
    /// deliberately kept (its own doc comment: consistency with sibling
    /// rules' identical convention outweighs polish for one rule in
    /// isolation). Shared here so every rule's evidence/narrative text uses
    /// the same format rather than each rewriting it.
    public var formatted: String { "\(year)-\(month)-\(day)" }

    /// Absolute difference in days. Proleptic Gregorian via `Calendar`,
    /// sufficient for T3's ±3-day window (docs/phase-0/11_VERTICAL_SLICE.md
    /// §11.2) — no calendar-library dependency needed for that.
    public static func daysBetween(_ a: AccountingDate, _ b: AccountingDate) -> Int {
        abs(dayCount(a) - dayCount(b))
    }

    private static func dayCount(_ d: AccountingDate) -> Int {
        var comps = DateComponents()
        comps.year = d.year
        comps.month = d.month
        comps.day = d.day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: comps)!
        return Int(date.timeIntervalSince1970 / 86_400)
    }

    /// Added 2026-09-06 for `RecurringVendorDetector`/`CashFlowForecastEngine`
    /// — projecting a next-expected date forward by N days. Proleptic
    /// Gregorian via `Calendar`, same posture as `daysBetween` above.
    public func adding(days: Int) -> AccountingDate {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: comps)!
        let shifted = calendar.date(byAdding: .day, value: days, to: date)!
        return AccountingDate(date: shifted)
    }
}
